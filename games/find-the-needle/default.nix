{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator drop: /var/lib/steam/game-archives/Find-The-Needle.zip
  # (2,154,215,659 bytes, sha256 52e1b53b...11c302ca), an AnkerGames
  # pre-installed tree (https://ankergames.net/game/find-the-needle)
  # of the Windows build, not an installer. Added to the local kubo
  # daemon (system ipfs service, repo /var/lib/ipfs, PeerID
  # 12D3KooWDoqC29n4gsnVVpPLwiw6q9caJukL91GAqFVmEpQmhZfH) via stdin
  # pipe as the CIDv1 below (the drop mount is not traversable by the
  # ipfs user), cross-checked against an offline
  # --only-hash --raw-leaves. The v0 form of the same bytes
  # (QmNoAqRNPBBRQszbftE1qfPZot52bt8pSGHZkLXnzSwpP7) is not what
  # gateways serve for a file of this size (AGENTS.md, 44 MiB rule)
  # and is not pinned. Verified by range GET (206, zip magic) on
  # 127.0.0.1:8080. Upstream identity: Steam appid 5160800 (Needless
  # Games, 2026-11-06, Windows-only, Early Access). No non-IPFS
  # mirror of these bytes exists (the paid Steam build is the only
  # official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeifhtpeffvahvlcocibbmmbc2o3zzw5kytfhc636jp5ys42os22riy";
    fallbackUrl = "";
    hash = "sha256-UuG1O5FPK9xNvoVL/oYM6Lq9XHaAI0x51W/b4RHDAso=";
    name = "find-the-needle-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "find-the-needle";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # AnkerGames zip layout: Find The Needle/ (FindTheNeedle.exe +
  # FindTheNeedle.pck + GDExtension DLLs + the tenoke Steam emu)
  # beside root-level debris (AnkerGames advert .url, "Read Me.txt",
  # "Run Me!.bat"); copying only the game subdir drops the debris. The
  # zip members are zstd-compressed, which p7zip 16.02 cannot read
  # (its listing shows Errors: 1); 7-Zip 26.04 extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Find The Needle/"* "$out"/

    # The shipped override.cfg pins Godot's D3D12 backend, which under
    # Proton routes through vkd3d-proton; the SPIR-V vkd3d emits for
    # this game's compute shaders segfaults RADV 26.1.5 in
    # radv_shader_spirv_to_nir (rad issue 7bf4b8c1bd31a8a41b97834d2f622b0a39b54024).
    # Godot's native Vulkan backend emits its own SPIR-V, which the
    # same driver compiles fine (operator-verified: rendering works and
    # game logic runs past setup2), so replace the file with the
    # operator's hand-tuned variant: vulkan primary, d3d12 fallback.
    cat > "$out/override.cfg" <<'EOF'
    [rendering]

    rendering_device/driver.windows="vulkan"
    rendering_device/fallback_to_vulkan=false
    rendering_device/fallback_to_d3d12=true
    rendering_device/fallback_to_opengl3=false
    driver/threads/thread_model.template=2
    EOF
  '';

  runtime = "proton";

  executable = "FindTheNeedle.exe";

  # Godot 4 export: user:// maps to
  # AppData/Roaming/Godot/app_userdata/<product name>. The pck is
  # encrypted (no GDPC magic, no plaintext directory), so the product
  # name cannot be read from the tree; observed live in the prefix
  # after the operator's runs: app_userdata/FindTheNeedle/ (one word,
  # godot log dir beneath it) — not the display name "Find The Needle".
  saveLocations = [ "AppData/Roaming/Godot/app_userdata/FindTheNeedle" ];

  # tenoke's Steamworks layer loads its steamclient by ABSOLUTE path
  # (C:\Program Files (x86)\Steam\steamclient64.dll, wine trace in the
  # launch logs) instead of from the exe dir, so WINEDLLOVERRIDES
  # cannot redirect it — overrides only intercept load-by-name. Drop
  # the game tree's steamclient64.dll at that prefix path from preRun
  # (AGENTS.md's sanctioned manual-DLL-drop mechanism, automated).
  # install -C skips the copy while the prefix copy still matches the
  # game tree, so relaunches do not rewrite the file.
  preRun = ''
    __strom_steam="$STROM_COMPATDATA/0/pfx/drive_c/Program Files (x86)/Steam"
    mkdir -p "$__strom_steam"
    install -C -m0644 "$GAMEDIR/steamclient64.dll" "$__strom_steam/steamclient64.dll"
  '';

  # Proton's builtin lsteamclient hook-patches the exports of a loaded
  # native steamclient64.dll, laid out for Valve's genuine client. On
  # tenoke's modified binary the CreateInterface trampoline lands two
  # bytes off and leaves 0x60 (pusha, illegal in 64-bit mode) as the
  # export's first byte, so SteamAPI_Init dies with SIGILL at
  # steamclient64+0xbe460 (wine-staging 11.0 / GE-Proton11-1,
  # measured 2026-11-08). Keeping the builtin out of the process lets
  # the emu's own client serve CreateInterface.
  env.WINEDLLOVERRIDES = "lsteamclient=";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Find The Needle (Needless Games 2026, Early Access haystack-digging automation sim, Godot 4 via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "find-the-needle";
  };
}
