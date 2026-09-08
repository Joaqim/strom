{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "risk-of-rain";

  # The game tree, pinned as one reproducible tar.zst bundle: the desktop
  # extracts it into the overlay base and the Android client into its
  # game directory, from the same CID.
  #
  # Provenance. Risk of Rain (2013, Hopoo Games) v1.2.2 Windows build,
  # as archive.org's RiskOfRain1.2.2.7z item preserves it ("Risk of Rain
  # 1.2.2.7z", CID QmUiGfcZ9zbgubBA8RZCwGvMhz4drAKztWZr3eKZ9s4C3m,
  # https://archive.org/download/RiskOfRain1.2.2.7z/Risk%20of%20Rain%201.2.2.7z).
  # The tree is that archive's single top-level "Risk of Rain" directory
  # extracted with 7z and folded to the root, byte for byte: the original
  # GameMaker Studio executable plus its bundled DirectX/GameMaker DLLs.
  # Nothing is patched or replaced. No Linux native build was ever
  # shipped on archive.org, so this runs via Proton. The bundled
  # steam_api.dll is a stub: the steamclient-stub provided by
  # lib/proton.nix satisfies its few imports.
  src = fetchIpfs {
    cid = "bafybeiflztreidm3byvpskl3y7bybkqdboq2czi56744xpinrfhjx2l5uy";
    bundle = true;
    hash = "sha256-oAVYDphUkKWtFf44ZWLzm9AhjiImmKMi5M0sahm6sl0=";
    name = "risk-of-rain";
    size = 70696934;
  };

  runtime = "proton";
  executable = "Risk of Rain.exe";

  saveLocations = [ "AppData/Local/ROR_GMS_controller" ];

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
    description = "Risk of Rain (2013 Hopoo Games, original v1.2.2 Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risk-of-rain";
  };
}
