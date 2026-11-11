{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator drop: /var/lib/steam/game-archives/Casualties-Unknown-AnkerGames.zip
  # (386,856,058 bytes, sha256 6ba47ffa...a9fe01c), an AnkerGames
  # pre-installed tree (https://ankergames.net) of the Windows build,
  # not an installer. Upstream identity: Steam appid
  # 4576490 (Casualties: Unknown, Orsoniks / Oro Interactive, released
  # 2026-11-09; store appdetails type "game", i.e. the full game, not
  # the separate demo app). The tree carries a RUNE steam emu
  # (Plugins/x86_64/steam_api64.dll + steam_emu.ini, original
  # steam_api64_o.dll kept beside it); it replaces the Steamworks API
  # DLL itself, ships no steamclient64.dll, and is not subject to the
  # AGENTS.md lsteamclient-disable rule for steamclient-shipping emu
  # packs. No non-IPFS mirror of these bytes exists (the paid Steam
  # build is the only official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeic7cjpvmvq5qsqhesqbtd2yqeum74nztbl5rh2wi3e4atexghv2aa";
    fallbackUrl = "";
    hash = "sha256-a6R/+u7DjyEm/TFv9pRzsHgOQe45A/wUWBD21Cqf4Bw=";
    name = "casualties-unknown-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "casualties-unknown";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # AnkerGames zip layout: "Casualties Unknown/" (CasualtiesUnknown.exe
  # + CasualtiesUnknown_Data/ + UnityPlayer.dll + MonoBleedingEdge +
  # the RUNE steam emu under Plugins/x86_64/) beside root-level debris
  # (AnkerGames advert .url, "Read Me.txt", "Run Me!.bat"); copying
  # only the game subdir drops the debris. The zip members are
  # zstd-compressed (177 of 198 entries; find-the-needle had the same
  # maker), which p7zip 16.02 cannot read; 7-Zip 26.04 extracts
  # cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Casualties Unknown/"* "$out"/
  '';

  runtime = "proton";

  executable = "CasualtiesUnknown.exe";

  # Unity 2022.3.62f3 Mono persistentDataPath from app.info
  # (company "Orsoniks", product "CasualtiesUnknown"); observed created
  # in the prefix on first boot.
  saveLocations = [ "AppData/LocalLow/Orsoniks/CasualtiesUnknown" ];

  # The RUNE emu keeps its Steam-Cloud emulation (remote/, local/,
  # achievements.ini, leaderboards.ini — observed in the prefix on
  # first boot) at drive_c/users/Public/Documents/Steam/RUNE/4576490,
  # which saveLocations cannot express: its relocation loop is
  # hardcoded to drive_c/users/steamuser/. Apply the same
  # copy-out-and-symlink mechanism from preRun for the Public path.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/4576490"
    __strom_rune_dst="$STROM_GAMEDIR/rune-4576490"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"
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
    description = "Casualties: Unknown (Orsoniks 2026, cave-exploration survival sim across 11 hostile layers, Unity 2022.3 Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "casualties-unknown";
  };
}
