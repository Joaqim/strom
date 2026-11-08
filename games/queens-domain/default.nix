{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Operator drop: /var/lib/steam/game-archives/Queens-Domain-AnkerGames.zip
  # (1,010,230,487 bytes, sha256 e6a6d872...64d15422), an AnkerGames
  # pre-installed tree (https://ankergames.net/game/queens-domain)
  # of the Windows build, not an installer. Added to the local kubo
  # daemon (system ipfs service, repo /var/lib/ipfs, PeerID
  # 12D3KooWDoqC29n4gsnVVpPLwiw6q9caJukL91GAqFVmEpQmhZfH) by direct
  # path (the drop mount is traversable by the ipfs user) as the CIDv1
  # below, cross-checked against an offline --only-hash --raw-leaves.
  # The v0 form of the same bytes
  # (QmbePXWEWme6oTtpfukHCd2TQshbsWmsXEcMxj3cd1BFK8) is not what
  # gateways serve for a file of this size (AGENTS.md, 44 MiB rule)
  # and is not pinned. Verified by range GET (206, zip magic) on
  # 127.0.0.1:8080. Upstream identity: Steam appid 1799840 (Freshly
  # Baked Games LLC / Future Friends Games, 2026-10-30, Windows-only).
  # No non-IPFS mirror of these bytes exists (the paid Steam build is
  # the only official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeiavo75kjo336omu5b3mv6y5edjp6n7wfj47fx7zqi6h5jsw2f4suq";
    fallbackUrl = "";
    hash = "sha256-5qbYclkojOSGagqfNbcEj41meRvzvYm/AIUAkmTRVCI=";
    name = "queens-domain-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "queens-domain";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # AnkerGames zip layout: QueensDomain/ (the UE4 game tree) beside
  # root-level debris (AnkerGames advert .url, readme.txt, "Run Me!.bat",
  # Redist/ installers); copying only the QueensDomain/ subtree drops
  # the debris. The zip members are stored uncompressed (method 0),
  # which both Info-ZIP unzip and p7zip read; p7zip matches the other
  # AnkerGames recipes (gloomwood). Unreal Engine 4, evidenced by the
  # pak suffix (QueensDomain-WindowsNoEditor.pak; UE5 uses -Windows),
  # UE4PrereqSetup_x64.exe and the PhysX3/APEX VS2015 third-party DLLs.
  # AnkerGames' own "Run Me!.bat" starts the Shipping binary, not the
  # root 265 KB bootstrapper exe.
  buildScript = ''
    mkdir -p "$out"
    7z x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/QueensDomain/"* "$out"/
  '';

  runtime = "proton";

  executable = "QueensDomain/Binaries/Win64/QueensDomain-Win64-Shipping.exe";

  # UE4 writes saves/config under %LOCALAPPDATA%\<GameName>\Saved (see
  # games/gamedec, games/colony-ship-a-post-earth-role-playing-game);
  # the RUNE Steam emu's ini declares its data root at
  # Users\Public\Documents\Steam\RUNE\1799840 (see games/routine).
  # Phase 2 interactive audit (launch, write a save, find newer dirs)
  # still pending with the operator.
  saveLocations = [
    "AppData/Local/QueensDomain/Saved"
    "Public/Documents/Steam/RUNE/1799840"
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
    description = "Queen's Domain (Freshly Baked Games LLC 2026, retro-fantasy action RPG, Unreal Engine 4 via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "queens-domain";
  };
}
