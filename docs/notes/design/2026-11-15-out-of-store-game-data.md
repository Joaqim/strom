# Out-of-store game data mode

Working note recording the approved design direction for games whose bytes never enter the nix store.
Date: 2026-11-15.
Status: implemented on develop — lib mode 7304400 (`lib/mk-game.nix`, `lib/data-materializer.sh`, android guard), infamous switch 54863a5, closure check d47220c; verification ladder pending.

## Problem

Two drops waiting in `/var/lib/steam/game-archives` are an order of magnitude larger than anything packaged so far: Infamous-Second-Son-AnkerGames.zip (22,999,779,341 bytes) and the South of Midnight v1.3.0 repack — a 70,804,351,871-byte Rar5 named South-of-Midnight.zip whose transfer was still running at orientation time, so the 36 GB zip then visible was a partial artifact and every reading taken from it is void.
The established recipe materializes game bytes twice: once as the `fetchIpfs` fixed-output derivation (the canonical archive) and once as the extracted tree in the game's `_gameData` output.
For these two that is roughly 94 GB of origin archives plus an estimated 100 GB of extracted trees, into a store with 198 GB free — near-capacity after one arc.

The second consequence is redistribution exposure.
harmonia serves every path present in this host's store on the tailnet, and game trees are store paths today; `probably-stolen` and `tom-the-postgirl-inner` outputs are present and therefore served right now.
Severity is calibrated, not catastrophic: the cache is reachable but not advertised (no substituter is published in the flake), so the audience is the fleet plus anyone who already knows the address.
The operator's decision is to accept the existing exposure and migrate existing games later, while making the new mode the only path for future large games.

## Goal and non-goals

Goal: an `mkGame` mode in which the flake references game data by attestable metadata only — CID, sha256, archive layout — and the bytes are materialized at launch time into the state dir from local sources, never entering a derivation output.

Non-goals for this arc: migrating the existing `fetchIpfs` games (follow-up arcs, one per game), hardening or relocating harmonia, and any public-gateway fetch of unfree bytes (the local kubo gateway and the static archives directory are the only sources).

A pivot under consideration but not chosen: a filtered cache exposure, fronting harmonia with a proxy that only forwards narinfo/NAR requests for an allowlisted closure.
That filter is the only mechanism that could actually block serving, because caches are path-addressed and never consult derivation meta: unfree paths are absent from cache.nixos.org since hydra never builds them, not because a cache refuses to serve them, and harmonia likewise serves by store path.
On a host that builds its games locally, the only real filters are "the bytes never enter this store" (this mode) or an explicit fronting allowlist; the mode makes the filter question moot for these games.

`meta.unfree = true` is deferred for repository-wide consideration: no existing game sets it, a consumer expects a new game to just work (the flag fails evaluation for `allowUnfree = false` consumers), and flagging only these two would make them the exceptions in the catalog.
The eventual decision belongs to the whole games tree, not to these patches.

## Relationship to existing mechanisms

The repo already has a canonical no-archive-in-store shape: `fetchIpfs { bundle = true; }` (14 games) fetches and extracts a reproducible tar.zst inside one fixed-output build, so the archive never lands in the store — only the tree does.
It does not apply here, for two reasons.
The tree is the copy this mode removes: a 58 GB uncompressed store tree is exactly what harmonia would serve, and the operator's requirement is bytes-nowhere-derivational.
And the bundle pipeline routes uploads through the anonymous public pin host, while the operator's policy for these unfree drops is the local kubo pin pipeline only.

Two existing mechanisms carry over as precedent rather than mechanism: `games/magicka` proves state-dir runtime extraction with a completion sentinel (a wineprefix, in kind only), and `copyGlobs` plus the saveLocations relocation loop prove store-tree-to-state-dir materialization at launch.
The fuse-overlay lower/upper split is unchanged: materialized data acts as the lowest lower, writes copy up to the state dir as today.

AGENTS.md's convergence rule ("pin the game tree, not the installer") labels the zip-plus-buildScript shape the pre-pin state, so the upstream patches deliberately carry a shape the repo considers transitional — that is the probably-stolen and tom-the-postgirl AnkerGames-drop precedent, and convergence for these games cannot route through the public pin host anyway.
Pin-after-test discipline applies to the public host; the local kubo pin of the curated zip follows the probably-stolen operator precedent instead.

## Mode contract

A new `dataArchive` option on `mkGame`, mutually exclusive with `src` plus `buildScript`:

```nix
dataArchive = {
  cid = "bafy...";
  sha256 = "<64 hex chars>";   # raw sha256sum form of the curated zip (not SRI)
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
- Tools: `_7zz` for extraction of the curated zips (both are `7zz a -tzip` deflate archives, so decoder coverage is self-evident) and `curl` for the gateway fetch; both are free software and stay in the wrapper's closure.
  The origin formats are irrelevant to the materializer but recorded for curation context: the Infamous origin is zstd-in-zip that `_7zz` 26.02 decodes, while the SOM origin is a Rar5 (with a cosmetic `.zip` filename) that `_7zz` 26.02 cannot decode at all — curation used `unrar` 7.3.2 for it.
- After a successful extraction the downloaded zip is deleted; the static archive in `$STROM_ARCHIVES` is never modified.

State-dir deletion or corruption self-heals: the next launch re-materializes from the same attested sources, which also retires the FOD-garbage-collected-and-reseeded failure mode recorded in memory for the current recipe.

## What the store still holds, and the tradeoff

The wrapper derivation's closure contains only free software: bwrap, the FHS, proton, gamescope, the materializer tools.
The flake stays publishable and harmonia never holds a game-byte path for games in this mode.
The tradeoff stated plainly: nix no longer verifies the game tree.
The archive is attested by the sha256 in the flake and verified host-side at materialization time, which is the same trust boundary the curated-zip recipe already uses (per-file manifests against the untouched drop), but the extracted tree itself is not content-addressed by the build system.
First launch pays the extraction cost (tens of GB from local disk, minutes, with progress output).

## Android

Unaffected by construction in principle: the phone fetches by CID client-side and `dataArchive.cid` is exactly the metadata that path will consume.
As landed (7304400), a `dataArchive` game's metadata carries `cids = [ ]` and the `androidPayloads` derivation throws a clear not-yet-supported message, while the android manifest and metadata-sync gates stay green.
Wiring `dataArchive.cid` into the client-side fetch is a follow-up for when that consumer gains archive-fetch support; the deviation from "the CID alone" is deliberate laziness, not an omission.

## Curation pipeline delta

The curated-zip recipe is unchanged up to and including the kubo pin: curation with exclusions, per-file manifests, provenance comment, local pin.
CIDs follow the AGENTS.md 44 MiB rule — files above it must be added with `--cid-version=1`, which at these sizes is mandatory, not stylistic (a `--raw-leaves`-only root disagrees with what pin infrastructure serves).
What changes is consumption — the game file records `dataArchive` metadata instead of a `fetchIpfs` call.
For South of Midnight the operator approved five exclusions: the two root debris files, the root `Back Crack/` RUNE-emu fragment, the root `Bonus/` soundtrack (1.95 GB FLAC+MP3), and the whole `DigitalExtras` tree including its own Engine/ subtree (24.3 GB extracted, documentaries and videos, not needed to play); the exclusions go into the provenance comment exactly like the Redist/ precedent.
The curated zip holds `SouthOfMidnight/` complete otherwise — Midnight/, Engine/ (plausibly load-bearing), GamingServices/, installscript.vdf, NOTICE.txt — 577 files plus 64 dir entries, 60.1 GiB extracted, 45,358,644,519 bytes (42.2 GiB) zipped; manifest equality with the origin is machine-verified modulo exactly those five exclusions (231 files).

## Upstream patch relationship and local divergence

Both games are bound for upstream radicle patches that diverge from upstream/master by their own addition alone.
Games are auto-discovered (`builtins.readDir ./games` in the flake's `legacyPackages` wiring), so a game patch is purely a new `games/<slug>/` directory and cannot conflict with the stacked develop patches.
Upstream master has no `dataArchive`, so the patch carries the game in the established `fetchIpfs` form, and this mode applies as a fork-develop local layer:

- The upstream-form game file (fetchIpfs FOD plus buildScript) is the unit cherry-picked onto the clean base; it is never contaminated by local-mode content.
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

South of Midnight's crack class is settled by the completed curation (2026-11-15): the build is the GDK/Xbox runtime — `Midnight/Binaries/Win64/` holds `SouthOfMidnight.exe` with `libHttpClient.GDK.dll`, `Microsoft.Xbox.Services.GDK.C.Thunks.dll`, `XCurl.dll`, and `MicrosoftGame.config`, and no `steam_api` anywhere under `Midnight/`.
The RUNE emu is applied in-tree at `SouthOfMidnight/Engine/Binaries/ThirdParty/Steamworks/Steamv152/Win64/` (`steam_api64.dll` 1,025,632 B, `steam_api64.rne` renamed original, `steam_emu.ini`), and the root `Back Crack/` fragment the RAR also carried was a byte-identical duplicate of exactly that trio (equal sha256 on both sides in the origin manifest), excluded by curation.
`GamingServices/` is a single vestigial `GamingRepair.exe` (570,984 B), kept.
The recipe arc applies the RUNE preRun rule for the Engine Steamworks path.

## Disk end-state (operator decision 2026-11-15)

The steam pool cannot host the build peak (origin 70.8 GiB + kept-set extraction 60.2 GiB + curated zip ~55 GiB) nor the permanent end state (both curated zips plus both state copies); curation stages extraction and zip construction on the /nix dataset (198 GiB free) and moves only the finished zip back.
State copies are self-healing caches by design, not permanent commitments: re-materialization from the attested sources means a copy can be deleted for space and rebuilt on demand, so arc 3 frees or redirects each game's materialized copy before its playtest rather than pre-reserving ~100 GiB that the pool does not have.

## Open questions resolved by the implementation (7304400)

Naming landed as proposed (`dataArchive`, `rootFolder` — the root name is provenance, so a `stripRoot` bool lost); `sha256` is raw hex because the comparison is a host-side `sha256sum`, never a nix FOD hash; `size` is advisory (a non-fatal preflight warning naming actual free bytes); the submodule shape keeps a multi-archive list expressible without inviting it yet; and every materializer phase logs `strom-data[<game>]` naming which source satisfied the fetch.
One deliberate ordering refinement over this note: the materializer runs before the proton instance lock, so a second launch during first-time extraction waits on the data flock and only genuinely concurrent instances reach the instance-lock failure.

## Pivot after the first lived runs (2026-11-15)

The first boots re-framed the storage premise that motivated this mode.
The "double storage" it removes was waste only while the store was the sole home for both the archive and the tree: with the cold archives living on a spinning disk and the cache audience gated, the established `fetchIpfs` recipe remains the default for games that fit the store, and `dataArchive` settles into its demonstrated role — the opt-in mode for drops whose scale keeps them out of the store entirely.
The lived costs that shaped this: a one-time extraction per materialization (~2-3 min Infamous, ~5 min SOM) and, for drops whose zips actually compress, a net tree premium (SOM +18 GiB); against native-read speed forever, a store holding zero unfree bytes, and no FOD-GC churn.

Operator decisions (2026-11-15, taken during SOM's first boot):
- Infamous and SOM keep `dataArchive` locally; no revert.
The switch commits stand and the dual-form upstream strategy is unchanged.
- The cache gate is network-level only: the serving channel is restricted to fleet identities, and within it harmonia serves what the store holds (gated audience, not gated content — a fronting proxy with a closure allowlist was considered and declined for now).
- The spinning disk takes the archives alone ($STROM_ARCHIVES relocation at the environment level; the lib default is unchanged).
A second nix store for game closures and a full store migration were both declined.

Queued follow-ups: the network-level gate on the mirror module and the archives relocation are host-infra arcs, sequenced after the landing pipeline.

## Verification plan

A `dataArchive` game exercises the mode end to end at the existing verification ladder (static eval, boot verify, operator playthrough, save-across-relaunch), plus two mode-specific checks: a store-closure assertion that the wrapper references no archive bytes, and a re-materialization check (delete the state dir, relaunch, confirm self-heal).
The games inventory, AGENTS.md workflow, and per-game recipe details for the two drops land with their implementation arcs.
