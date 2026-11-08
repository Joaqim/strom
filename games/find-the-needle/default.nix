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
  '';

  runtime = "proton";

  executable = "FindTheNeedle.exe";

  # Godot 4 export: user:// maps to
  # AppData/Roaming/Godot/app_userdata/<project name>. The pck is
  # encrypted (no GDPC magic, no plaintext directory), so the project
  # name cannot be read short of running the game; "Find The Needle"
  # is the display-name guess. Phase 2 interactive audit (launch,
  # write a save, find newer dirs) still pending with the operator.
  saveLocations = [ "AppData/Roaming/Godot/app_userdata/Find The Needle" ];

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
