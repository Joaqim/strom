# Anker Launcher AppImage static study

Working note recording a static inventory of AnkerGames' official Linux launcher, taken to evaluate convergence opportunities with strom's acquisition and distribution pipeline.
Date: 2026-11-15.
Status: study complete; integration deferred by operator decision (study-only scope).

## Scope and method

Studied: `AnkerLauncher-0.1.30-x86_64.AppImage` (108,095,992 bytes, sha256 `8fa554f24316fe05dd156dde9094b9aba5450edaf6819187288f898fa2c07b0c`), with `0.1.28` (sha256 `ed529a8010c6dd9787c037aa6029e4cb9326bbd5563eeff0933bb16dd53f9950`) used only for a file-list delta.
Method was static only: the squashfs payload was carved at its `hsqs` magic offset (944632 for both versions; both embed a byte-identical AppImageKit runtime) and extracted with `unsquashfs`; findings come from `strings`, `readelf -d`, and `rg -a` over the extracted tree.
Nothing was executed, including `--appimage-extract` (which runs the embedded runtime), so nothing here validates runtime behavior; all claims are verified against 0.1.30 unless stated.
The vendor's FAQ positions the launcher as the closed front end for ankergames.net downloads: it requests links, applies per-plan limits, and verifies files, precisely to keep automated scraping off their hosting.
That rationale is respected here — this study reads the artifact as data and does not attempt to reconstruct or automate the download API.

## Stack

The launcher is Tauri 2.11.5 (Rust), not Electron or Qt: cargo registry paths for `tauri-2.11.5/src/app.rs` are embedded in the stripped main binary `usr/bin/anker-launcher` (33.9 MiB, version string `0.1.30stable`, identifier `net.ankergames.launcher`).
Its dynamic dependencies are exactly the GTK set (`libwebkit2gtk-4.1`, `libjavascriptcoregtk-4.1`, `libgtk-3`, `libsoup-3.0`); everything else — rustls, ring, serde, aria2 control, the updater — is statically linked into the Rust binary.
Two sidecars ship beside it: `aria2c` 1.36.0 (Ubuntu 22.04 package; the launcher drives the bundled `libaria2.so.0` over localhost JSON-RPC with a per-session secret) and `ludusavi` v0.31.0 (official mtkennerly build, save-game backup).
Uncompressed payload is ~968 MiB, dominated by webkit2gtk (85.8 MiB) and javascriptcore (32.2 MiB).

Internal module names recovered from panic strings read like a peer of strom: `crates/anker-core/src/` holds `session`, `device_key`, `catalog`, `launch`, `launch_settings`, `launch_profile`, `library_scan`, `steam_shortcuts`, `proton`, `protondb`, `save_sync`, `community`, and `download/{retry,limiter,state,probe,verify}`, plus `torrent/{mod,space}` and `installation/relocation`.

## Network surface

The only embedded vendor host is `https://ankergames.net` — no `api.`/`cdn.`/`dl.` subdomains, and the FAQ's term "DataNodes" appears nowhere in the binary or tree; CDN and file hosts must arrive at runtime inside download grants.
Endpoint fragments visible statically: `/media/access_token`, `/authorize`, `/api_session`, `net.ankergames.launcher/device-identity/v1`; most REST paths are constructed at runtime from API schema structs (`GameRequest`, `Catalog`, `HomeShelves`, `DownloadGrant`, `ClientUpdate`), so the full API is not statically enumerable.
The API base is overridable via `ANKER_API_BASE`; other honored env vars include `ANKER_USER` and `ANKER_WINE_PREFIX`.
Custom headers: `X-Anker-Link-Handler`, `X-Anker-Game`, and grant headers `X-Game-Slug`, `X-Artifact-Type`, `X-Artifact-Build-Id`, `X-Artifact-Sha256`.
Third-party traffic: Steam store API (`IStoreBrowseService/GetItems`), protondb report summaries, steamgriddb and steamstatic CDNs for artwork, `github.com/Open-Wine-Components/umu-launcher/releases` for runtime downloads, and ludusavi's manifest on raw.githubusercontent.com.
Cloudflare awareness is explicit: a `cf-mitigated` state string explains the bot filter "wants a browser sign-in".

## Distribution and update machinery

Torrent distribution is first-class: `prefer_torrents`, community seeding (`share_downloads`), `upload_limit_kb`, `seed_minutes`, webseed and peer progress fields, and a fallback path when "the torrent made no progress with no peers and no webseed".
Per-download integrity is corroborated: `expected_sha256`, the `X-Artifact-Sha256` header, checksum-verification error strings, and persisted download receipts ("Could not locate verified download records").
Self-update is Velopack-based in-place AppImage replacement: it writes a verified `AnkerLauncher-update-recovery-*.AppImage` beside the running file, retains `.anker-previous-*` copies, refuses linked or relative AppImage paths ("use the website download instead"), and gates on `ClientUpdate` fields including `signature`, `package_sha256`, `mandatory`, and `minimum_version`.
`check_updates_at_startup` exists as a setting; no verification keys ship as files — they live inside the binary, and the exact signature scheme is not statically labeled (ring's Ed25519 and RSA-PSS code is present but also serves rustls).
Runtime and redistributable installers are separately signature-checked ("a runtime installer is not signed by its maker; it is not run").

## Sign-in and anonymous use

Sign-in is website-mediated pairing: OAuth2-device-flow fields (`device_code`, `user_code`, `verification_uri_complete`) plus a `PairingChallenge`, with the token handed back through the `ankergames://` deep link; no third-party OAuth brands appear.
UI strings tie sign-in to specific features only — website notifications, community participation, and subscription-gated cloud save backup ("Sign in with an eligible subscription to back up to the cloud").
No string requires sign-in to browse the catalog or start a download, and there are no guest-mode strings either.
Enforcement is server-side regardless: `DownloadGrant`/`GrantedFile`, `DownloadEntitlement` (concurrent slots, connections per download, wait seconds, daily/monthly quota used), `RequiredTier` on games, and device-bound links validated against `device-key.json` ("device key not registered; download links stay bound to the address alone").
Whether a signed-out client can receive grants for any game is therefore indeterminate statically; it needs one interactive operator test.
Credentials are stored as plain files in the launcher data dir (`device-key.json`, session token), not a keyring — libsecret is bundled only as a WebKitGTK dependency.

## On-disk layout

Games land under a user-chosen library root (default-path candidates `Downloads`/`AnkerGames`), tracked by marker files inside each game folder: `.anker-library.json`, `.anker-source`, `.anker-shortcuts-*`, `.anker-save-*`, `.anker-redistributables.json`, `.anker-write-test-*`.
`.anker-source` in particular is provenance metadata written by the launcher itself — the same role our per-file sha256 manifests play in the curated-zip recipe.
The launcher scans and imports existing installs (`library_scan`) and classifies them by scene-release markers (`CODEX`, `Online-Fix`, `EMPRESS`, `SKIDROW`, `SmartSteamEmu`, `RAZOR1911`, `3DM`).
Windows games run through discovered umu-launcher/Proton installs (Steam/Heroic/Lutris paths), with `WINEPREFIX` management, gamescope options, and run-as-admin; per-game desktop entries use `net.ankergames.launcher.game-*` identifiers.

## Licensing

`usr/lib/Anker Launcher/THIRD-PARTY-NOTICES.txt` (~1 MB) is thorough: GPL-compliant sidecar disclosure publishes the aria2 source beside every release at `https://github.com/zororver/anker-launcher/releases` (offered on request for 3+ years), ludusavi is MIT, and 96 Ubuntu 22.04 system packages carry per-package Debian `copyright` files.
The launcher's own code is explicitly outside those licences; no ToS or redistribution-constraint text exists anywhere in the artifact, so redistribution terms live only on the website and remain unchecked.

The 0.1.28 → 0.1.30 delta swaps exactly 18 files — the launcher binary, the GLib family, and GStreamer base libs — with an identical file list otherwise; a release is an in-place content swap, and the GitHub releases repo above is the artifact to watch for tracking them.

## Observations for strom

These are observational, not proposals — the operator scoped this session to study only.

The launcher and strom solve the same couch-gaming distribution problem from opposite ends, and the module list shows it: both have save sync (ludusavi vs our syncthing fleet), Steam shortcuts (their `steam_shortcuts` vs our host-realize design), Proton/umu orchestration, gamescope tuning, and library import.
Their distribution layer is torrent-plus-webseed with community seeding, where ours is IPFS pins plus gateways; both are P2P content-addressed channels with a cold-start problem (their no-peers-no-webseed fallback vs our cold-gateway 504s), so their `prefer_torrents` and seed-window design is at least a pattern worth having read.
Their per-download sha256 receipts and `.anker-source` markers converge on the same provenance discipline as our curated-zip manifests, which means a future acquisition flow could anchor provenance on the launcher's own records rather than re-deriving them.
If the launcher-as-strom-entry idea is ever revisited, two hard constraints are now known up front: Velopack replaces the AppImage in place and refuses linked or relative paths, so a nix store path cannot self-update and `check_updates_at_startup` must be off; and webkit2gtk-4.1 plus the GTK loader set means an FHS-style wrapper, which our `mk-game` machinery already builds.

## Open questions

Whether a signed-out launcher can browse and download anything (interactive operator test; the operator currently has no account).
What the website terms say about redistributing the AppImage itself (website check; nothing in-artifact).
Which signature scheme protects `ClientUpdate` and the runtime installers (would require runtime observation or deeper binary analysis, neither in scope).
