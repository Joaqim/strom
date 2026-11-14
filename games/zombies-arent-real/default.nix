{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an IGG / PCGamesTorrents pre-installed
  # repack of the Windows build, Steam appid 5185890 (Zombies Aren't
  # Real, Jogamedev, Early Access released 2026-11-13; the Supporter
  # Pack DLC appid 5488850 is a separate app and not in this drop).
  # Custom C++ engine on D3D11, no middleware. Origin: single RAR
  # Zombies.Arent.Real.rar, sha256
  # fb92d188f22c3c52d0bf815f306c7dd91ec59ff01e2cd119938b493f79ac5a3d
  # (torrent info-hash
  # A4C3A21DB3A8890BC160483933E4A4F9A88BF4F6), extracted to a
  # directory drop: Zombies.Arent.Real/ = game/ plus five
  # repack-site files. The curated zip of the drop minus exactly
  # those five exclusions (IGG-GAMES.COM.url, OneHack.Us.txt,
  # PCGAMESTORRENTS.COM.url, README.txt, _INSTALL TUTORIAL.txt) is
  # the canonical artifact: 325,361,091 bytes, sha256
  # f1dd5d98040e4d6f152c8161e03d675fb350dc0e3789c1c87e74fe4c388ea926.
  # The drop's empty runtime dirs survive as zip directory entries:
  # game/assets/, game/cache/, game/steam_cloud/ and
  # game/steam_settings/achievement_images/. Steam emu: goldberg
  # family (steam_api64.dll 10.7 MB + steam_settings/, appid
  # 5185890) replacing the Steamworks API DLL itself; it ships no
  # steamclient64.dll, so the AGENTS.md lsteamclient-disable rule
  # for steamclient-shipping emu packs does not apply. No non-IPFS
  # mirror of these bytes exists (the paid Steam build is the only
  # official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeihs6h3qeynff532osje5s2dwalpryy77srxcatgsg4xh7o6doseu4";
    fallbackUrl = "";
    hash = "sha256-8d1dmAQOTW8VLIFh4D1nX7NQ3A43icHIfnT+TDiOqSY=";
    name = "zombies-arent-real-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "zombies-arent-real";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Zip layout follows the AnkerGames / tom-the-postgirl precedent:
  # one root folder (Zombies.Arent.Real/) holding the drop's game/
  # tree (zombies-arent-real.exe + art/ + campaigns/ + maps/ + the
  # goldberg steam_settings/ and empty runtime dirs); the
  # repack-site files at the drop root never entered this zip.
  # Members are deflate-compressed; 7zz extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Zombies.Arent.Real/game/"* "$out"/
  '';

  runtime = "proton";

  executable = "zombies-arent-real.exe";

  # Saves persist via the per-game fuse-overlayfs upper: the custom
  # engine keeps its state next to its binary (config.ini,
  # balance.ini and unlocks.ini ship in the install dir, and the
  # goldberg emu's steam_cloud/ root sits beside the exe). Runtime
  # confirmation is deferred to the operator playthrough.
  saveLocations = [ ];

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
    description = "Zombies Aren't Real (Jogamedev 2026 Early Access, horde-defense strategy against a spreading zombie infection, custom C++ D3D11 via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "zombies-arent-real";
  };
}
