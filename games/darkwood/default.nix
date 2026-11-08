{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of Darkwood (v1.4.2 build 70215), mirrored on
  # archive.org by phoenix-games-lab. The installer is a bare mojosetup
  # .sh (shell-script header + zip archive), so unzip handles it
  # directly with no tar wrapper. The game is a Unity MonoBleedingEdge
  # build laid out under data/noarch/game/ as a tiny Darkwood.x86_64
  # launcher plus UnityPlayer.so and Darkwood_Data/.
  installer = fetchIpfs {
    cid = "bafybeidayvhvtes77d2jic7mvlr5h2m4gkbaj3bdjsgx6gegdmf3337jzi";
    fallbackUrl = "https://archive.org/download/darkwood-linux-gog-phoenix-games-lab/darkwood_1_4_2_70215.sh";
    hash = "sha256-4GqLO2vCHZhF7ufTS0gQPIpP2uNGVSC6FOSLo/1gXZ4=";
    name = "darkwood-linux-gog-1.4.2.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "darkwood-data";
    version = "1.4.2";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # Unity split-player: the 14K Darkwood.x86_64 launcher NEEDs only
    # UnityPlayer.so and the C runtime, and UnityPlayer.so NEEDs only
    # libc/libdl/libm/librt/libgcc_s/libpthread; the GL/X11/wayland/
    # audio/udev surface is dlopened by bare name at runtime.
    # autoPatchelf handles the NEEDED entries; LD_LIBRARY_PATH below
    # provides the dlopen targets.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      # mojosetup .sh: unzip warns about the shell header ("extra bytes
      # at beginning") and exits 1 while extracting everything fine.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out/"
      # Strip the GOG shim files; we don't ship the galaxy integration.
      rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb
      # Drop the Stadia-only plugins: they NEED libggp.so (Google Games
      # Platform, never distributed outside Stadia) plus libc++abi, and
      # the engine loads them only on that platform. Removing them keeps
      # autoPatchelf strict instead of carrying an ignore list and a
      # dead dependency into the closure.
      rm -f "$out/Darkwood_Data/Plugins/libunitystadia.so" \
            "$out/Darkwood_Data/Plugins/libunitystadia_preview.so"
      chmod +x "$out/Darkwood.x86_64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "darkwood";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Darkwood.x86_64";

  # -force-glcore: this build's intended renderer is OpenGL Core (it
  # only falls back to Vulkan when GL init fails), but the Vulkan
  # fallback path segfaults under gamescope - SDL creates the window,
  # Unity asks for X11 window info to build the Vulkan surface, the
  # handle is invalid ("Error getting system window info"), and the
  # player dies at the first resize. With mesa's GLX vendor on
  # LD_LIBRARY_PATH (below) the GL path initializes and the game
  # boots to its menu.
  executableArgs = [
    "-force-glcore"
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # Unity's UnityPlayer.so dlopens GL/X11/wayland/audio/udev/dbus by
    # bare name; provide the full set on LD_LIBRARY_PATH. mesa is on
    # the list for its GLX vendor + DRI drivers: without them the
    # -force-glcore renderer can't find an OpenGL core profile.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        mesa
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        wayland
        libxkbcommon
        udev
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  # Force X11 so SDL builds its window on gamescope's Xwayland: GLX
  # needs an X window, and letting SDL pick wayland (gamescope exposes
  # one to its children) leaves Unity without a usable GL/Vulkan
  # surface ("Error getting system window info", then a segfault).
  # This must happen in runScript, not env: gamescope sanitizes
  # SDL_VIDEODRIVER out of the child environment it spawns (measured),
  # and runScript execs the game as gamescope's grandchild, after that
  # sanitization.
  runScript = ''
    export SDL_VIDEODRIVER=x11
    unset WAYLAND_DISPLAY
    exec "$STROM_OVERLAY/Darkwood.x86_64" "$@"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    # No --expose-wayland: Unity 2021.3's SDL2 grabs the exposed wayland
    # backend for its window and then dies asking for X11 window info to
    # build the Vulkan surface (see SDL_VIDEODRIVER above). Unexposed,
    # SDL lands on gamescope's Xwayland, which the player handles.
  };

  meta = {
    description = "Darkwood (native Linux, GOG v1.4.2 build 70215)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "darkwood";
  };
}
