{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an IGG / PCGamesTorrents pre-installed
  # repack (directory drop, no origin archive) of the Windows build,
  # Steam appid 2257440 (Tom the Postgirl, Oopsie Daisies / ARTE
  # France, released 2026-10-29; store appdetails type "game"). Unity
  # 6000.0.78f1 Mono. 1,367,336,914 bytes, sha256
  # fcb3f287f2434d9b564e2eb7178ff6141e902460f959e16d7e8f41a8fedc6d75.
  # Curated from the drop's game/ tree with two exclusions: the
  # 545.3 MB TomThePostgirl-Artbook.pdf (sold separately as appid
  # 5445770; stays with the drop) and TomThePostgirl.exe.bak. The
  # exe decision: the shipped TomThePostgirl.exe is the Steam-CEG
  # unwrapped player (PE entry RVA 0x1264 inside .text, decrypted
  # text; sha256 3dbe00b47264ca5ab503c60e17d3ccccd60d8f73f8b3ed3f7b
  # 2d6217496c6124) while the .bak is the DRM-wrapped original
  # (entry RVA 0xa8310 inside the Steam .bind section) and cannot
  # run outside Steam. Steam emu: GSE (Goldberg fork) at
  # TomThePostgirl_Data/Plugins/x86_64/steam_api64.dll (10.7 MB,
  # original Steamworks dll kept beside it as steam_api64.dll.bak)
  # with steam_settings/ (appid 2257440); it replaces the Steamworks
  # API DLL itself, ships no steamclient64.dll, and is not subject
  # to the AGENTS.md lsteamclient-disable rule for
  # steamclient-shipping emu packs. No non-IPFS mirror of these
  # bytes exists (the paid Steam build is the only official source),
  # so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeiadjrutaf5o5hi42w64kjtiz7n7knzkc4cpincsktwdizamjhcbny";
    fallbackUrl = "";
    hash = "sha256-/LPyh/JDTZtWTi63F4/2FB6QJGD5WeFtfo9BqP7cbXU=";
    name = "tom-the-postgirl-igg-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "tom-the-postgirl";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout mirrors the AnkerGames drops: one root game
  # folder (TomThePostgirl/ with TomThePostgirl.exe +
  # TomThePostgirl_Data/ + UnityPlayer.dll + MonoBleedingEdge + the
  # D3D12 Agility SDK dir) and nothing else at the zip root; the
  # repack site's promo files never entered this zip. Members are
  # deflate-compressed (448 of 475 entries); 7zz extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/TomThePostgirl/"* "$out"/
  '';

  runtime = "proton";

  executable = "TomThePostgirl.exe";

  # Unity 6000.0.78f1 Mono persistentDataPath from app.info
  # (company "OopsieDaisies", product "TomThePostgirl"): Player.log
  # writes its saves to Saves/<steamid64>/*.json beneath it (observed
  # in the prefix on first boot; Player.log names the exact paths).
  # GSE Saves is the emu's settings/cloud-simulation root and
  # GameAnalytics its Unity SDK state; unlike the casualties RUNE
  # root both sit under steamuser, so saveLocations can express
  # them with no preRun copy-out.
  saveLocations = [
    "AppData/LocalLow/OopsieDaisies/TomThePostgirl"
    "AppData/Roaming/GSE Saves"
    "AppData/Local/GameAnalytics"
  ];

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
    description = "Tom the Postgirl (Oopsie Daisies / ARTE France 2026, small-town stalking adventure, Unity 6 Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "tom-the-postgirl";
  };
}
