{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/probably-stolen-cyberpunk-shopkeeper-sim)
  # of the Windows build, Steam appid 4348910 (Probably Stolen -
  # Cyberpunk Shopkeeper Sim, Questing Goose Studio / tinyBuild,
  # released 2026-10-28). Unity 2021.3.45f2 Mono, Steamworks.NET
  # 2025.163.0 (Steamworks SDK 1.63). Origin: the site zip
  # Probably-Stolen-Cyberpunk-Shopkeeper-Sim-AnkerGames.zip, sha256
  # 852f298dd848601e50e8dfadf6a20a5f803e6da2f18bb8664c73045db5b7e219,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly five exclusions
  # (AnkerGames.url, readme.txt, "Run Me!.bat", Redist/DXWebSetup.exe,
  # Redist/vc_redist.x64.exe) is the canonical artifact: 396,357,536
  # bytes, sha256
  # 7b242fa6f699dcdb69f6e0f457859ddfa4a3a952efeb493ca817c105e6880fd3;
  # per-file sha256 manifests of the untouched drop and the zip's
  # extracted contents match modulo those exclusions. The player exe
  # carries no CEG .bind section. Steam emu: RUNE family
  # (steam_api64.dll + steam_emu.ini replacing the Steamworks API
  # DLL, originals kept as .rne beside it, appid 4348910); it ships
  # no steamclient64.dll, so the AGENTS.md lsteamclient-disable rule
  # for steamclient-shipping emu packs does not apply. The shipped
  # empty Mods/ runtime dir survives as a zip directory entry. No
  # non-IPFS mirror of these bytes exists (the paid Steam build is
  # the only official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeihf4eeb44pin76jw5wigswxusu6ujyffoovegu36hz4kjjf7f7pvm";
    fallbackUrl = "";
    hash = "sha256-eyQvpvaZ3Ntp9uD0V4Wd36SjqVLv60k8qBfBBeaID9M=";
    name = "probably-stolen-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "probably-stolen";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Probably Stolen/" with "Probably Stolen.exe" +
  # Probably Stolen_Data/ + UnityPlayer.dll + MonoBleedingEdge + the
  # RUNE emu under Plugins/x86_64/ and the empty Mods/ dir) and
  # nothing else at the zip root; the site debris never entered this
  # zip. Members are deflate-compressed; 7zz extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Probably Stolen/"* "$out"/
  '';

  runtime = "proton";

  executable = "Probably Stolen.exe";

  # Unity 2021.3.45f2 Mono persistentDataPath from app.info
  # (company "Questing Goose Studio", product "Probably Stolen");
  # observed created in the prefix on first boot.
  saveLocations = [ "AppData/LocalLow/Questing Goose Studio/Probably Stolen" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\4348910; remote/,
  # local/, achievements.ini and leaderboards.ini observed there on
  # first boot) at drive_c/users/Public/Documents/Steam/RUNE/4348910,
  # which
  # saveLocations cannot express: its relocation loop is hardcoded to
  # drive_c/users/steamuser/. Apply the same copy-out-and-symlink
  # mechanism from preRun for the Public path (casualties-unknown
  # precedent).
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/4348910"
    __strom_rune_dst="$STROM_GAMEDIR/rune-4348910"
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
    description = "Probably Stolen - Cyberpunk Shopkeeper Sim (Questing Goose Studio 2026, fence-shop management on a dystopian space station, Unity 2021.3 Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "probably-stolen";
  };
}
