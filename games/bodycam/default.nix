{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/bodycam) of the Windows build, Steam
  # appid 2406770 (Bodycam, Reissad Studio, released 2024-06-03 early
  # access; the appid comes from Steam appdetails, which resolve
  # 2406770 to this exact name and developer). UE 5.5 (SteamCorePro_5.5
  # plugin, D3D12 Agility SDK, DirectML, boost python311 DLL set,
  # SDL2; D3D12 renderer with DLSS 8.9.0 / FSR 4.1.1 / XeSS 3.0.5 /
  # Streamline plugin trees). The drop carries an EasyAntiCheat (EOS
  # flavour) tree at the game root. Origin: the site zip
  # Bodycam-AnkerGames.zip, 67,631,001,916 bytes, sha256
  # b7e5fbadcb9c57c605f846540099c7e72a1fa94906711eb3026a55ae100920a2,
  # a genuine zip64 with zstd-compressed members (7zz 26.02 decodes),
  # 570 files, 111 folders, 74,778,936,813 bytes uncompressed, holding
  # the game root folder beside root-level site debris. The game root
  # Bodycam/ holds the nested project dir Bodycam/Bodycam/
  # (Binaries/Win64/Bodycam-Win64-Shipping.exe, 180,773,376 bytes)
  # plus Engine/, the 3.9 MB Easy Anti-Cheat Bootstrapper v1.9.0 (EOS
  # flavour) Bodycam.exe and _CommonRedist/. The curated zip of the
  # drop minus exactly three exclusions ("AnkerGames - Free
  # Pre-installed PC Games.url", "Read Me.txt", "Run Me!.bat") is the
  # canonical artifact: 67,632,978,155 bytes, sha256
  # 5606be9234497f30ad84acd51b502caac16ae9a29c4e4422cc3da2028fcf6a79,
  # deflate members (on this mostly-incompressible pak data, 0.003
  # percent larger than the zstd origin), single root folder "Bodycam"
  # (567 files); per-file sha256 manifests of the untouched drop
  # (Bodycam-AnkerGames-origin-drop.sha256, 570 files) and of the
  # curated zip's member contents (Bodycam-AnkerGames-zip-contents.
  # sha256, 567 files, streamed per-member sha256 -- byte-identical to
  # a hash of the extracted tree) are byte-identical modulo those
  # exclusions. Steam emu: the repack ships a Goldberg-family emu
  # applied in-tree at Bodycam/Bodycam/Plugins/SteamCorePro_5.5/
  # Source/ThirdParty/SteamLibrary/redistributable_bin/win64/
  # (steam_api64.dll 11,235,240 B + steam_settings/, original kept as
  # steam_api64.dll.bak); the tree ships no steamclient64.dll. No
  # non-IPFS mirror of these bytes exists (the paid Steam build is the
  # only official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeih2fltvaazjpfz4ux3fdo2jss7gkvp5uprbdwd5pwcp5hf4tcqc3a";
    fallbackUrl = "";
    hash = "sha256-Vga+kjRJfzCthKzVG1AsqsFq6aKcTkQizD2iAo/Pank=";
    name = "Bodycam-AnkerGames-Repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bodycam";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root game
  # folder ("Bodycam/" with the nested UE project Bodycam/
  # (Binaries/Win64/Bodycam-Win64-Shipping.exe), Engine/, the EAC
  # bootstrapper Bodycam.exe and _CommonRedist/) and nothing else at
  # the zip root; the site debris never entered this zip. Members are
  # deflate-compressed; 7zz extracts cleanly. The /. form of the copy
  # also preserves any root dotfiles, which a * glob would skip.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Bodycam/." "$out"/
  '';

  runtime = "proton";

  # The root Bodycam.exe is the Easy Anti-Cheat Bootstrapper v1.9.0
  # (EOS flavour), not the game; the game itself is the UE shipping
  # exe nested under the project dir (the colony-ship
  # nested-shipping-exe shape). The repack runs on its in-tree
  # Goldberg emu, and the EAC bootstrapper is bypassed by launching
  # the shipping exe directly.
  executable = "Bodycam/Binaries/Win64/Bodycam-Win64-Shipping.exe";

  # UE5 writes saves and settings under %LOCALAPPDATA%\Bodycam\Saved
  # (drive_c/users/steamuser/AppData/Local/Bodycam/Saved) -- the
  # standard UE relocation path (colony-ship convention): relocate
  # the whole Saved tree so settings survive a prefix wipe too.
  saveLocations = [ "AppData/Local/Bodycam/Saved" ];

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
    description = "Bodycam (Reissad Studio 2024 UE5 ultra-realistic multiplayer shooter built around bodycam footage, Windows build via Proton; single-player on the repack's Goldberg emu)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bodycam";
  };
}
