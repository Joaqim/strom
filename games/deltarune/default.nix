{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "deltarune";

  # The game tree, pinned as one reproducible tar.zst bundle: the desktop
  # extracts it into the overlay base and the Android client into its
  # game directory, from the same CID.
  #
  # Provenance. DELTARUNE (Toby Fox, 2018-2025, chapters 1-4), the
  # Windows GameMaker build as the LinuxRuleZ YAD self-extracting
  # installer DELTARUNE.sh on archive.org's deltarune_20250916 item
  # wraps it (CID QmSSr7w3G9i3EidAK51sjnpGUuDEX55q2cp3FwLefQN2UV,
  # https://archive.org/download/deltarune_20250916/DELTARUNE.sh,
  # sha256-Koq80dStkCpX+Hk058rK4VVGPvwPBU7s40emZEneID0=). The .sh tail
  # is an xz-compressed tarball of 928825096 bytes; the tree is exactly
  # its `DELTARUNE/game/prefix/drive_c/game/` subtree with those five
  # leading components stripped: the GameMaker runner (DELTARUNE.exe +
  # data.win), the chapter data directories and the music. The repack's
  # own bundled wine and its portable prefix under
  # `DELTARUNE/game/{wine,prefix}/` are left out so Proton and this
  # repo's `mk-game.nix` manage the prefix and the game integrates with
  # saveLocations + gamescope. No file is patched or replaced. The one
  # difference from the old recipe's build output: its `cp -r ./*` also
  # swept stdenv's `env-vars` (build debris full of store paths, which a
  # fixed-output fetch of the tree rejects) into the root; the bundle
  # omits that file.
  src = fetchIpfs {
    cid = "bafybeifbvwpqdjwg2o5d5quxcjxswwwckjxyht3mivpqlllkwebwcnza4a";
    bundle = true;
    hash = "sha256-xZCN2M+f95VmfRek2UTSPGEZ32O7H4PH8F5CCvTeje4=";
    name = "deltarune";
    size = 391822613;
  };

  runtime = "proton";
  executable = "DELTARUNE.exe";
  saveLocations = [ "AppData/Local/DELTARUNE" ];

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
    description = "DELTARUNE (Toby Fox 2018-2025, chapters 1-4, GameMaker / Windows via Proton; LinuxRuleZ repack)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "deltarune";
  };
}
