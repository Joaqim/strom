{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "blood-omen-legacy-of-kain";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. Blood Omen: Legacy of Kain (Silicon Knights / Crystal
  # Dynamics 1996; the Semi Logic Win32 port, 1997), GOG re-release v1.0
  # hotfix build 50548. The origin is archive.org's
  # blood-omen-legacy-of-kain-gog item, a single RAR (CID
  # QmUB18G41smnpTJUE3sb3YjZstM1kxB9BU2V8X3ChtDNKk, fallback
  # https://archive.org/download/blood-omen-legacy-of-kain-gog/Blood%20Omen%20Legacy%20of%20Kain%20%28GOG%29.rar,
  # sha256-bnYOFtA5HFtu8zQmgbQrffxIfv6hj5oZibwhyizKxKs=) holding the GOG
  # Inno Setup installer setup_blood_omen_legacy_of_kain_1.0_hotfix_(50548).exe
  # plus concept art and a 1.0->hotfix patch exe, both ignored. The tree is
  # exactly what `innoextract --gog` yields from that installer at the root:
  # Kain.exe (native Win32 binary), the Kain/ data dir (.JAM movies, .VAG
  # audio, PILL.BIG), Cfg/ config, game.chm, plus GOG's own bundled
  # DirectDraw/DirectInput wrapper (ddraw.dll, dinput.dll, dixi.ini) and the
  # dxcfg graphics tool (dxcfg.exe, dxcfg.ini). GOG installer debris and
  # Galaxy bits were dropped (app/, __redist/, __support/, tmp/,
  # commonappdata/, goggame-*.info/.hashdb/.script/.id, galaxy_*.exe,
  # autorun.exe, autorun.inf). No file is patched or replaced.
  #
  # Unlike most DirectDraw-era ports, GOG does NOT wrap this in DOSBox: Kain.exe
  # runs natively and GOG ships its own 1.5 MiB ddraw.dll + 364 KiB dinput.dll
  # shim (dixi.ini configures gamepad->DirectInput remapping) that makes the
  # game render and take input on modern Windows. We keep that shim and force
  # both DLLs native under Proton so Wine loads GOG's wrapper instead of its
  # builtin ddraw/dinput - the same arrangement the sibling Soul Reaver package
  # uses. (Verok's KainGL OpenGL wrapper is the alternative DirectDraw fix, but
  # it targets the raw retail CD and would collide with GOG's shim; left as a
  # fallback if GOG's ddraw misbehaves under Proton.)
  src = fetchIpfs {
    cid = "bafybeiewk3f2jefhvu52g3wsfcwlk5gjbmbzibfr5ojhjnjdkcjtvkeulu";
    bundle = true;
    hash = "sha256-FF88ZbrhUJg3UibWvgjOPNTzF2Afpnl7W72c9BaCDaA=";
    name = "blood-omen-legacy-of-kain";
    size = 481788662;
  };

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (the GOG build writes
  # its saves under the game's own Saves/ next to Kain.exe, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "Kain.exe";

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

  env = {
    STEAM_COMPAT_CONFIG = "sdlinput";
    # Force GOG's bundled DirectDraw/DirectInput wrapper DLLs native so Wine
    # loads them instead of its builtin ddraw/dinput (mirrors Soul Reaver).
    WINEDLLOVERRIDES = "ddraw,dinput=n,b";
  };

  meta = {
    description = "Blood Omen: Legacy of Kain (Silicon Knights / Crystal Dynamics 1996, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "blood-omen-legacy-of-kain";
  };
}
