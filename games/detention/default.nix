{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "detention";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. Detention (Red Candle Games 2017), Unity Mono / Windows
  # build. Origin is archive.org's detention-x32-x64 item, Detention.iso
  # (CID QmTJWi1w8iBVv9jpecNCTeFJ5Lou7W4JM4ubJve5XnxVKY, fallback
  # https://archive.org/download/detention-x32-x64/Detention.iso). The
  # iso is only a wrapper: besides cover/trailer fluff (dropped) it holds
  # a single setup_Detention.exe, which despite the "setup_*" name is a
  # RAR self-extracting archive, not Inno; unar unpacks it to a
  # Detention/ directory. The tree is exactly that Detention/ subtree
  # folded to the root: Detention.exe, the Unity Mono runtime and
  # Detention_Data/. Nothing is patched or replaced.
  src = fetchIpfs {
    cid = "bafybeigcq4wwnsgvfwvrw45npcbydilwv3tf5k6v63lhq3lo2xp577wjey";
    bundle = true;
    hash = "sha256-ABvU5E2WGwZmBwbjhA9KExQjCRNN9tZ8Q7XR899W8e8=";
    name = "detention";
    size = 664399956;
  };

  runtime = "proton";
  executable = "Detention.exe";

  # Unity Mono game; saves under AppData/LocalLow per Unity convention.
  saveLocations = [ "AppData/LocalLow/Red Candle Games/Detention" ];

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

  meta = {
    description = "Detention (Red Candle Games 2017, Taiwanese-school horror, Unity / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "detention";
  };
}
