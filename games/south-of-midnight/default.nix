{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/south-of-midnight, page "South of
  # Midnight Free Download (v1.3.0)") of the Windows build, Steam appid
  # 1934570 (South of Midnight, Compulsion Games, published by Xbox Game
  # Studios, released 2025-04-08; the appid comes from the RUNE emu ini
  # and Steam appdetails, which resolve 1934570 and have no page for the
  # 1577010 figure floating around early registration lists). UE 4.27.2
  # (PCGamingWiki-verified; the tree corroborates: PhysX3 with VS2015
  # runtimes and Steamworks SDK 1.52, both UE4.27-era, no Chaos). The
  # binary is a GDK/Xbox-runtime build: Midnight/Binaries/Win64/ holds
  # SouthOfMidnight.exe with libHttpClient.GDK.dll,
  # Microsoft.Xbox.Services.GDK.C.Thunks.dll, XCurl.dll and
  # MicrosoftGame.config, and no steam_api anywhere under Midnight/.
  # Origin: the site zip South-of-Midnight.zip, 70,804,351,871 bytes --
  # a RAR 5 archive with recovery record whose .zip extension is
  # cosmetic -- holding the game tree beside root-level site debris.
  # The curated zip of the drop minus exactly five exclusions (the
  # DigitalExtras tree including its Engine/, the Bonus soundtrack, the
  # root "Back Crack/" trio, AnkerGames.url, "Read Me.txt") is the
  # canonical artifact: 45,358,644,519 bytes, sha256
  # 72df1daffc8f82a282f9ef669ac6d6109ca26c66b5089310b678cbb1446e34af,
  # deflate members, single root folder "SouthOfMidnight" (577 files,
  # 64 dirs); per-file sha256 manifests of the untouched drop
  # (/var/lib/steam/game-archives/South-of-Midnight-AnkerGames-origin-
  # drop.sha256, 808 lines) and of the curated zip's extracted contents
  # (South-of-Midnight-AnkerGames-zip-contents.sha256, 577 lines) are
  # byte-identical modulo those exclusions. Steam emu: RUNE family
  # applied in-tree at Engine/Binaries/ThirdParty/Steamworks/Steamv152/
  # Win64/ (steam_api64.dll replacing the Steamworks API DLL, original
  # kept as steam_api64.rne beside it, steam_emu.ini pinning
  # AppId=1934570); the excluded root "Back Crack/" was a byte-identical
  # duplicate of that trio. The tree ships no steamclient64.dll, so the
  # AGENTS.md lsteamclient-disable rule for steamclient-shipping emu
  # packs does not apply. GamingServices/GamingRepair/GamingRepair.exe
  # and installscript.vdf are kept redist debris. No non-IPFS mirror of
  # these bytes exists (the paid Steam build is the only official
  # source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeid5u2vytmwmgs6rcanspuprxsdqpjl6yxftho4tqejdlqqbmbylmu";
    fallbackUrl = "";
    hash = "sha256-ct8dr/yPgqKC+e9mmsbWEJyibGa1CJMQtnjLsURuNK8=";
    name = "south-of-midnight-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "south-of-midnight";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root game
  # folder ("SouthOfMidnight/" with the UE project Midnight/ (Binaries/
  # Win64/SouthOfMidnight.exe, Content/Paks IoStore set), the Engine/
  # 4.27 subset carrying the RUNE emu trio, GamingServices/GamingRepair/,
  # installscript.vdf, NOTICE.txt) and nothing else at the zip root; the
  # site debris never entered this zip. Members are deflate-compressed;
  # 7zz extracts cleanly. The /. form of the copy also preserves any
  # root dotfiles, which a * glob would skip.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/SouthOfMidnight/." "$out"/
  '';

  runtime = "proton";

  # The real binary is the UE shipping exe nested under the project dir
  # (the colony-ship nested-shipping-exe shape); this drop ships no root
  # launcher shim.
  executable = "Midnight/Binaries/Win64/SouthOfMidnight.exe";

  # UE4 writes saves under %LOCALAPPDATA%\SouthOfMidnight\Saved
  # (PCGamingWiki: the SaveSystem slot for saves, Config\WindowsNoEditor
  # for settings), i.e. drive_c/users/steamuser/AppData/Local/
  # SouthOfMidnight/Saved -- the standard UE relocation path (colony-ship
  # convention): relocate the whole Saved tree so settings survive a
  # prefix wipe too.
  saveLocations = [ "AppData/Local/SouthOfMidnight/Saved" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\1934570; remote/,
  # local/, achievements.ini observed there on RUNE releases) at
  # drive_c/users/Public/Documents/Steam/RUNE/1934570, which
  # saveLocations cannot express: its relocation loop is hardcoded to
  # drive_c/users/steamuser/. Apply the copy-out-and-symlink mechanism
  # from preRun for the Public path (probably-stolen precedent). The
  # in-tree steam_emu.ini gets the same treatment: copy it out to the
  # state dir and symlink back, so the emu's runtime writes to its ini
  # land in the persistent state dir directly instead of depending on
  # overlay copy-up next to the read-only store tree.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/1934570"
    __strom_rune_dst="$STROM_GAMEDIR/rune-1934570"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"

    __strom_ini="Engine/Binaries/ThirdParty/Steamworks/Steamv152/Win64/steam_emu.ini"
    __strom_ini_dst="$STROM_GAMEDIR/rune-1934570-steam-emu.ini"
    if [ ! -e "$__strom_ini_dst" ] && [ -f "$GAMEDIR/$__strom_ini" ]; then
      cp "$GAMEDIR/$__strom_ini" "$__strom_ini_dst"
    fi
    rm -f "$GAMEDIR/$__strom_ini"
    ln -snf "$__strom_ini_dst" "$GAMEDIR/$__strom_ini"
  '';

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
    description = "South of Midnight (Compulsion Games 2025 gothic-Southern action-adventure, a weaver's magic through a mythic Deep South, UE 4.27 Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "south-of-midnight";
  };
}
