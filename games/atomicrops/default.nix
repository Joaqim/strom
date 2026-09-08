{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "atomicrops";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. Atomicrops (Bird Bath Games / Raw Fury, 2020), Unity
  # action-roguelite farming shooter, Windows-only on GOG (no native
  # Linux build). The tree is the old buildScript's output from the GOG
  # offline Inno setup v1.1.9a build 41296 (CID
  # QmYCBXRWtbgkSbRqsivK12M6MZi8GwnD5omJii2mkwxA97, fallback
  # https://archive.org/download/atomicrops-gog/setup_atomicrops_1.1.9a_%2841296%29.exe,
  # sha256-r2UV2j1m2jpTketz3lE+QOSpagsum8z6YqR95oJsxwE=): innoextract
  # --gog, the app/ component folded up to the root (Atomicrops.exe +
  # Atomicrops_Data/ + UnityPlayer.dll), the tmp/, commonappdata/ and
  # __redist/ components dropped along with the goggame-*.info / .hashdb
  # / .script / .ico galaxy metadata. One deliberate deletion on top:
  # UnityCrashHandler32.exe and UnityCrashHandler64.exe are removed.
  # Atomicrops.exe spawns the crash handler (--attach <pid>) to monitor
  # it; on a clean in-game quit the main process exits but the handler
  # lingers, and `proton waitforexitandrun` waits for every wine process
  # (and wineserver) to exit before returning, so the surviving handler
  # wedged proton open forever and the strom wrapper / gamescope never
  # tore down. Unity runs fine without it (just no crash reporter). No
  # files are patched or replaced.
  src = fetchIpfs {
    cid = "bafybeid2jcswo3po2rdfkb5tvvugjrthqdesvcld2kgd75xfkb6p7kfcyq";
    bundle = true;
    hash = "sha256-N2ZxYDO6JRLT9MS4qOPg3Q3Qh5vSqboPvJxLaPI52fE=";
    name = "atomicrops";
    size = 282003693;
  };

  runtime = "proton";
  executable = "Atomicrops.exe";

  # Atomicrops writes profile_v1_0*.banana saves into the Unity
  # LocalLow tree (AppData/LocalLow/Bird Bath Games/Atomicrops on
  # Windows).
  saveLocations = [ "AppData/LocalLow/Bird Bath Games/Atomicrops" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Atomicrops (Bird Bath Games 2020, Unity action-roguelite farming shooter, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "atomicrops";
  };
}
