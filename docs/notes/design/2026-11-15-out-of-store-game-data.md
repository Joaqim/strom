# Out-of-store game data mode

Working note recording the approved design direction for games whose bytes never enter the nix store.
Date: 2026-11-15.
Status: direction approved in session (three operator decisions recorded below); pending implementation arcs.

## Problem

Two drops waiting in `/var/lib/steam/game-archives` are an order of magnitude larger than anything packaged so far: Infamous-Second-Son-AnkerGames.zip (22,999,779,341 bytes) and South-of-Midnight.zip (36,277,583,872 bytes).
The established recipe materializes game bytes twice: once as the `fetchIpfs` fixed-output derivation (the canonical zip) and once as the extracted tree in the game's `_gameData` output.
For these two that is roughly 59 GB of zips plus an estimated 80-100 GB of extracted trees, into a store with 198 GB free — near-capacity after one arc.

The second consequence is redistribution exposure.
harmonia serves every path present in this host's store on the tailnet, and game trees are store paths today; `probably-stolen` and `tom-the-postgirl-inner` outputs are present and therefore served right now.
Severity is calibrated, not catastrophic: the cache is reachable but not advertised (no substituter is published in the flake), so the audience is the fleet plus anyone who already knows the address.
The operator's decision is to accept the existing exposure and migrate existing games later, while making the new mode the only path for future large games.

## Goal and non-goals

Goal: an `mkGame` mode in which the flake references game data by attestable metadata only — CID, sha256, archive layout — and the bytes are materialized at launch time into the state dir from local sources, never entering a derivation output.

Non-goals for this arc: migrating the existing `fetchIpfs` games (follow-up arcs, one per game), hardening or relocating harmonia, and any public-gateway fetch of unfree bytes (the local kubo gateway and the static archives directory are the only sources).

A pivot under consideration but not chosen: a filtered cache exposure, fronting harmonia with a proxy that only forwards narinfo/NAR requests for an allowlisted closure.
`meta.unfree = true` on the game derivations is semantically correct and worth setting regardless — it gates evaluation for `allowUnfree = false` consumers — but it blocks nothing by itself: unfree paths are absent from cache.nixos.org because hydra never builds them, not because a cache refuses to serve them, and harmonia serves by store path without consulting meta.
On a host that builds its games locally, the only real filters are "the bytes never enter this store" (this mode) or an explicit fronting allowlist; the mode makes the filter question moot for these games.

## Mode contract

A new `dataArchive` option on `mkGame`, mutually exclusive with `src` plus `buildScript`:

```nix
dataArchive = {
  cid = "bafy...";
  sha256 = "sha256-...";       # of the curated zip
  size = 22999779341;          # bytes, for preflight and progress display
  fileName = "infamous-second-son-ankergames.zip";  # curated archive name
  rootFolder = "Infamous Second Son";               # single-root layout, stripped on extract
};
```

`src` remains the default path and every existing game keeps evaluating unchanged.
When `dataArchive` is set, `_gameData` is not a derivation at all; the overlay's base lower becomes the literal state path `$STROM_GAMEDIR/.strom-data/<sha256-prefix>`, which the inner script expands at runtime exactly as `overlay.upper` and `overlay.work` already do (both are `$STROM_GAMEDIR`-relative strings interpolated into the fuse-overlayfs invocation inside the inner command in `gameModule`'s bwrap defaults).
No change to `copyGlobs`, `preRun`, `saveLocations`, or `modLayers` semantics: the materialized directory is simply the lowest-priority lower, mods stay above it.

## Source resolution order

The materializer resolves the archive in this order and fails with an error naming every source it tried:

1. `$STROM_ARCHIVES/<fileName>` — default `/var/lib/steam/game-archives`, the operator's static archive directory.
2. The local kubo gateway by CID, honoring `STROM_IPFS_GATEWAYS` (set system-wide by the mirror module since 2026-11-11).

Both paths verify the sha256 recorded in the flake before extraction; a mismatch is a hard failure that removes the partial download and says so.
Public gateways are deliberately not consulted: fetching unfree bytes from `ipfs.io`-class endpoints is the same redistribution the mode exists to avoid.

## Materialization lifecycle

The fragment runs in the wrapper's preHook (host side, before bwrap), generated like the existing `pad-to-kb-launcher.sh` inclusion rather than inlined nix strings:

- Target: `$STROM_GAMEDIR/.strom-data/<sha256-prefix>/` holding the root folder's contents (root stripped).
- Atomicity: extract into `.strom-data/.partial-<pid>/`, verify, then rename; presence of the final directory is the completion marker.
- Concurrency: a flock on `.strom-data/.lock` so a second launch during first-time extraction waits instead of erroring (the proton instance lock already reserves failure for genuinely concurrent instances).
- Space: the gateway path downloads the zip to a temporary file first (peak usage = zip plus extracted); the archive-directory path streams from the local file with no second copy.
- Tools: `_7zz` for extraction — both drops are zstd-in-zip, verified extractable by the pinned `_7zz` 26.02 this session — and `curl` for the gateway fetch; both are free software and stay in the wrapper's closure.
- After a successful extraction the downloaded zip is deleted; the static archive in `$STROM_ARCHIVES` is never modified.

State-dir deletion or corruption self-heals: the next launch re-materializes from the same attested sources, which also retires the FOD-garbage-collected-and-reseeded failure mode recorded in memory for the current recipe.

## What the store still holds, and the tradeoff

The wrapper derivation's closure contains only free software: bwrap, the FHS, proton, gamescope, the materializer tools.
The flake stays publishable and harmonia never holds a game-byte path for games in this mode.
The tradeoff stated plainly: nix no longer verifies the game tree.
The archive is attested by the sha256 in the flake and verified host-side at materialization time, which is the same trust boundary the curated-zip recipe already uses (per-file manifests against the untouched drop), but the extracted tree itself is not content-addressed by the build system.
First launch pays the extraction cost (tens of GB from local disk, minutes, with progress output).

## Android

Unaffected by construction: the phone already fetches by CID client-side, and `dataArchive.cid` is exactly the metadata that path consumes.
`ipfsSources` for a `dataArchive` game is the archive's CID alone.

## Curation pipeline delta

The curated-zip recipe is unchanged up to and including the kubo pin: curation with exclusions, per-file manifests, provenance comment, local pin.
What changes is consumption — the game file records `dataArchive` metadata instead of a `fetchIpfs` call.
For South of Midnight the operator approved excluding `DigitalExtras/MidnightPremium` (documentaries and music videos, roughly 14 GB of the zip and 20 GB extracted, not needed to play); the exclusion goes into the provenance comment exactly like the Redist/ precedent.

## Upstream patch relationship and local divergence

Both games are bound for upstream radicle patches that diverge from upstream/master by their own addition alone.
Games are auto-discovered (`builtins.readDir ./games` in the flake's `legacyPackages` wiring), so a game patch is purely a new `games/<slug>/` directory and cannot conflict with the stacked develop patches.
Upstream master has no `dataArchive`, so the patch carries the game in the established `fetchIpfs` form, and this mode applies as a fork-develop local layer:

- The upstream-form game file (fetchIpfs FOD plus buildScript, `meta.unfree = true`) is the unit cherry-picked onto the clean base; it is never contaminated by local-mode content.
- The dataArchive lib extension and a per-game switch commit (src mechanism swap only) live on the fork's develop and are never cherry-picked.
- The pipeline's trees-converge check is deliberately relaxed for these two game files: convergence is expected modulo exactly the switch commits, provable by a diff that shows only the src-mechanism change.
- Patch-form verification stays eval-level: the patch's FOD hash equals the curated zip's sha256 that the local materializer already extracted and verified byte-for-byte at runtime, so a worktree build of the upstream form re-verifies almost nothing — and it would transiently pull the full zip plus extracted tree into this host's store, recreating the exposure and the 150 GB growth for the lifetime of the worktree result.
A full worktree build remains available as an operator opt-in when disk headroom allows.

The runtime verification ladder (boot verify, playthrough, save-across-relaunch) runs against the local form, because that is the form this machine executes; the mode-specific checks (closure assertion, re-materialization self-heal) ride the same ladder.

## Game-specific notes from the orientation pass

Both drops follow the single-root AnkerGames layout with site debris at the zip root (`.url`, `Read Me.txt`, and for Infamous also `Run Me!.bat` and `HOW TO RUN THE GAME.txt`), matching the established exclusion pattern.

Infamous is not a PC port in the usual sense: it is the issn_pc project (GPL v2+, shadPS4-derived graphics core via axylpup, gow3_pc lineage) bundled with a PS4 dump under `user/` and `game/art/cache/psarc/`.
It is Vulkan-1.3-native, writes settings and lock files beside its exe (`issn.ini`, `.iss-launcher.lock`, `launcher/`, `out/`), and its launcher wants the `game/` folder selected once; the overlay upper and a `preRun` carry that.
The host GPU (RX 9070, RADV, Vulkan 1.4.363) clears the requirement and enables FSR 4.

South of Midnight is the UE5 GDK (Game Pass) build, not Steam: `Microsoft.Xbox.Services.GDK.C Thunks.dll`, `libHttpClient.GDK.dll`, and a bundled `GamingServices/` folder with a repair tool.
GDK builds under Proton are a known trouble class; the boot-verification stage must budget for studying what the bundled GamingServices folder actually does before trusting it.

## Open questions for the implementation arcs

- Option and field naming (`dataArchive` proposed; `rootFolder` vs a `stripRoot` bool).
- Whether `size` is advisory or enforced as a preflight check with a clear out-of-space error.
- Multi-archive games (split zips): out of scope until one arrives, but the contract should not preclude a list.
- Whether the materializer reports CID-vs-sha256 provenance of which source satisfied the fetch, for the operator log.

## Verification plan

A `dataArchive` game exercises the mode end to end at the existing verification ladder (static eval, boot verify, operator playthrough, save-across-relaunch), plus two mode-specific checks: a store-closure assertion that the wrapper references no archive bytes, and a re-materialization check (delete the state dir, relaunch, confirm self-heal).
The games inventory, AGENTS.md workflow, and per-game recipe details for the two drops land with their implementation arcs.
