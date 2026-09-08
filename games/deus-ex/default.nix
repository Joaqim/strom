{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "deus-ex";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. Deus Ex GOTY (2000, Ion Storm / Eidos), the GOG build
  # 1.112fm (installer 45326), as archive.org's deus-ex-goty-edition item
  # preserves it: a rar (CID QmYirjSSa4qwbxoBWH3Cc2g8Ywn1ZwUa3hphcmH7phq8bg,
  # https://archive.org/download/deus-ex-goty-edition/Deus%20Ex%20-%20GOTY%20Edition.rar)
  # bundling the self-contained GOTY installer
  # "setup_deus_ex_goty_1.112fm(revision_1.6.1.0)_(45326).exe" and a
  # separate Revision-mod installer with a .bin slice, which is not used.
  # The tree is what `innoextract --gog` unpacks from that GOTY .exe:
  # the game files at the root (System/, Maps/, Textures/, Sounds/,
  # Music/, Help/, manual.pdf and the goggame-1207658995.* metadata),
  # minus __redist, tmp, commonappdata and app/ (app/ holds only the GOG
  # icon, webcache.zip and an empty Save dir). No binaries are replaced;
  # one file is edited over that:
  #
  #  - System/DeusEx.ini (CRLF): FirstRun=0 -> FirstRun=1100, because
  #    FirstRun=0 makes DeusEx.exe pop the hardware-detection wizard on
  #    launch and any non-zero engine build number skips it.
  #    FullscreenViewportX/Y 640x480 -> 1920x1080; FullscreenColorBits,
  #    WindowedColorBits and ColorDepth 16 -> 32; GameRenderDevice and
  #    RenderDevice GlideDrv.GlideRenderDevice -> D3DDrv.D3DRenderDevice,
  #    WindowedRenderDevice SoftDrv.SoftwareRenderDevice ->
  #    D3DDrv.D3DRenderDevice; UseDirectDraw=True -> False.
  src = fetchIpfs {
    cid = "bafybeidi56b5rop235n5ubnh3fhbiykgc6dmjnvthczszjcqpgknavvjoq";
    bundle = true;
    hash = "sha256-uCd91epz4HqzmPsNFrPwJxjz+IPQoupde+VzWXNuW84=";
    name = "deus-ex";
    size = 377968614;
  };

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # System/User.ini, System/DeusEx.ini, Save/ next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "System/DeusEx.exe";
  # Force resolution at launch — the Unreal-1 engine probes the X server
  # for video modes and picks something tiny in the gamescope nested
  # session, ignoring whatever we pre-wrote into DeusEx.ini.
  executableArgs = [
    "-ResX=1920"
    "-ResY=1080"
    "-32bit"
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
    description = "Deus Ex GOTY (2000, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "deus-ex";
  };
}
