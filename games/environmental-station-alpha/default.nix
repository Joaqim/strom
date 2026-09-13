{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "environmental-station-alpha";

  # The game tree, pinned as one reproducible tar.zst bundle: the desktop
  # extracts it into the overlay base and the Android client into its
  # game directory, from the same CID.
  #
  # Provenance. Hempuli's 2015 Environmental Station Alpha, the 2020-06-02
  # build as archive.org's environmental-sa-v-02.06.2020 item preserves it
  # ("Environmental SA [v02.06.2020].rar", CID
  # QmSKfKZbygBUXXknED9vQUpaY4yjApjHMqTXq4cwtDD9xQ, fallback
  # https://archive.org/download/environmental-sa-v-02.06.2020/Environmental%20SA%20%5Bv02.06.2020%5D.rar).
  # The RAR holds "Environmental Station Alpha [v02.06.2020]/" with two
  # subdirectories: "Environmental SA [20-06-20]/", the actual game
  # (Environmental Station Alpha.exe plus Data/), and "_Redist/", the
  # vcredist installers. The tree is that game subdirectory folded to the
  # root, verbatim and unpatched; _Redist/ is dropped since Proton
  # supplies the runtime.
  src = fetchIpfs {
    cid = "bafybeififv4nvehim7fr43bnzmzyurn2h5kheiwmlg4vkg3h76jhccvwzu";
    bundle = true;
    hash = "sha256-XoTQChCkosQlDVzAJrOmx0Tuwdp3Q/8Fe5KMsU3yAsE=";
    name = "environmental-station-alpha";
    size = 85879245;
  };

  runtime = "proton";
  executable = "Environmental Station Alpha.exe";

  saveLocations = [ "AppData/Roaming/MMFApplications" ];

  # Clickteam Fusion 2 runtime (the MMFApplications save dir above is its
  # tell): a 32-bit Direct3D 8 / DirectDraw renderer. GameNative's default
  # dxvk has no D3D8 path, so the exe never maps a window and the launch
  # sits on "Launching game..." forever. wined3d is what GameNative itself
  # picks for a Steam title whose store page says DirectX <= 8.
  android.containerConfig.dxwrapper = "wined3d";

  # A Multimedia Fusion 2 game reads the keyboard only: the pad GameNative
  # exposes as XInput/DirectInput is never read (measured on the Thor:
  # injected key events drove the menu, the Odin pad did nothing). Its
  # defaults, as its Settings screen lists them: arrows move, C jump,
  # X shoot, Z and D the two abilities, Enter confirms, Escape pauses.
  android.padKeys = {
    leftStick = "arrows";
    dpad = "arrows";
    a = "C";
    b = "X";
    x = "Z";
    y = "D";
    start = "ENTER";
    select = "ESC";
  };

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
    description = "Environmental Station Alpha (Hempuli, 2015, Clickteam Fusion 2, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "environmental-station-alpha";
  };
}
