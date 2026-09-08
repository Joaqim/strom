{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "dungeon-keeper";

  # The game tree, pinned as one reproducible tar.zst bundle: the desktop
  # extracts it into the overlay base and the Android client into its
  # game directory, from the same CID.
  #
  # Provenance. The tree is exactly what the previous archive-based build
  # produced from two sources, unpatched (KeeperFX is itself the
  # community engine replacement, so no crack is involved):
  #
  #  - KeeperFX 1.3.1 "complete" release (keeperfx_1_3_1_complete.7z from
  #    github.com/dkfans/keeperfx/releases/download/v1.3.1/, sha256
  #    j61vNUnRpp0bhpa1I0x8SuzEzDNBhwMz79GNiBzmYoo=), extracted verbatim
  #    at the root: keeperfx.exe and its DLLs, fxdata/, campgns/,
  #    creatrs/, ldata/, levels/, mods/, music/, its own data/ and
  #    sound/ subsets, the launcher, save/ and scrshots/ placeholders.
  #  - The original 1997 Dungeon Keeper data, archive.org's
  #    msdos_Dungeon_Keeper_1997 item (Dungeon_Keeper_1997.zip, CID
  #    Qmez7AYzB1fAm129WEkUafvBnshvSfM5hPozpjQcZV8m3y, fallback
  #    https://archive.org/download/msdos_Dungeon_Keeper_1997/Dungeon_Keeper_1997.zip,
  #    sha256 7/DKaLonPKI6uH0a0vwesqM4d4AGIvoC2/ZPVRnFXJo=). The build
  #    took dungkeep/DATA and dungkeep/SOUND (it also looked for LDATA
  #    and LEVELS, which this zip does not contain), recursively renamed
  #    them to lowercase (data/, sound/) to match the layout KeeperFX
  #    ships and expects, and copied them under the KeeperFX tree
  #    without overwriting: any file KeeperFX already ships wins over
  #    the original. The rest of the zip (KEEPER.EXE, DOS4GW.EXE,
  #    KEEPER.CFG, SAVE/, cd/ disc image) was dropped.
  src = fetchIpfs {
    cid = "bafybeifforqoqoa55kv73sd7hvfch6c3huunapljvn4oi2p32zqmzdplzu";
    bundle = true;
    hash = "sha256-7emxeco4u1MTM24/UoV7hIYXenG8DRN3+PnBWZAqHAM=";
    name = "dungeon-keeper";
    size = 400604962;
  };

  copyGlobs = [ ];

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # save/*.sav + settings.dat next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "keeperfx.exe";
  env = {
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # KeeperFX writes saves into save/ next to its binary; create it before
  # launch so the first save doesn't fail on a missing directory. (The
  # framework supplies the outer gamescope nest and a dedicated DXVK state
  # cache, so neither is set here.)
  preRun = ''
    mkdir -p "$GAMEDIR/save"
  '';

  meta = {
    description = "Dungeon Keeper (KeeperFX, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-keeper";
  };
}
