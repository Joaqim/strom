{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "anachronox";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. Anachronox (Ion Storm 2001), GOG re-release v1.02 build
  # 22258, as the archive.org gog_collection item repacks it: a single
  # RAR (CID Qma31wDiB337AYUrJqQmJfeuc7RoZCWDUtVdeWbQnLrojD, fallback
  # https://archive.org/download/gog_collection/anachronox.rar,
  # sha256-Sx09L1qkzEeXeOu7RfgD6cXQfrcED/4zFkJ1nobMUbE=) holding exactly
  # one entry, setup_anachronox_1.02_(22258).exe, a GOG Inno Setup
  # installer. The tree is what `innoextract --gog` yields from that
  # installer, minus the GOG debris: app/ tmp/ __redist/ commonappdata/
  # wise/, goggame-*.{info,hashdb,script,ico}, galaxy_anachronox_*.exe,
  # autorun.exe and autorun.inf are dropped since nothing needs them at
  # runtime. What remains is the game at the root: anox.exe, gamex86.dll,
  # the renderer DLLs (ref_gl.dll + metagl.dll, the OpenGL path Proton
  # drives via DXVK/Mesa; anoxgfx.dll), mss32.dll, the bundled MSVCRT /
  # MSVCP60 / MSCOMCTL, the anox_*gl.bat launchers, setupanox.exe, the
  # 1.02 patch readmes, manual.pdf and anoxdata/. No file is patched or
  # replaced; the engine is a modified Quake II. No exec bits or
  # symlinks in the tree.
  src = fetchIpfs {
    cid = "bafybeiaqg5ksnphgovjvqiebt3jshwg5hrw7ue6ydhwblcdp3j356rsble";
    bundle = true;
    hash = "sha256-yWJWHE/3kezSI51E/yCiwnye7NlcSiXnM5vTau9PB+s=";
    name = "anachronox";
    size = 963648627;
  };

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # next to its binary, not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "anox.exe";
  # Mirror anox_1280gl.bat (gl_mode 8 = 1280x1024, opengl32 renderer,
  # fullscreen via gamescope-nested). Without these the engine picks
  # gl_mode 3 (640x480) and various sound providers, which is the
  # combination that dies during the first map load under Proton.
  executableArgs = [
    "+set"
    "gl_driver"
    "opengl32"
    "+set"
    "gl_mode"
    "8"
    "+set"
    "u_gl_mode"
    "8"
    "+set"
    "vid_fullscreen"
    "1"
    "+set"
    "u_vid_fullscreen"
    "1"
    "+set"
    "s_initsound"
    "0"
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
    description = "Anachronox (Ion Storm 2001, GOG v1.02 build 22258, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anachronox";
  };
}
