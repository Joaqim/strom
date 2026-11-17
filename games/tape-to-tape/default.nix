{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/tape-to-tape) of the Windows build,
  # Steam appid 1566200 (Tape to Tape, Excellent Rectangle, released
  # 2026-10-23; the appid comes from the RUNE emu ini and Steam
  # appdetails, which resolves 1566200 to this exact name and
  # developer). Unity 6000.0.79f1 IL2CPP (GameAssembly.dll +
  # il2cpp_data/Metadata/global-metadata.dat, data.unity3d bundle),
  # FMOD (fmodstudio.dll + resonanceaudio.dll + fmod_bitcrusher),
  # Rewired input, Sentry crash reporting, D3D12 Agility SDK
  # (D3D12/D3D12Core.dll), hdr-display-enabled=0 in boot.config.
  # Origin: the site zip Tape-to-Tape-AnkerGames.zip, 1,008,421,591
  # bytes, sha256
  # c90557f6a6d0e9227eae2a7c2e6c05df074371a34c1ade7d293fd0781c6e836e,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly five exclusions
  # (AnkerGames.url, readme.txt, "Run Me!.bat", Redist/DXWebSetup.exe,
  # Redist/vc_redist.x64.exe) is the canonical artifact: 997,387,026
  # bytes, sha256
  # 030730f18ea7244dfa7349c0cb12306cd50278a6c821875df2c35750f3fef57c,
  # deflate members, single root folder "Tape to Tape" (372 files,
  # 14 dir entries); per-file sha256 manifests of the untouched drop
  # (Tape-to-Tape-AnkerGames-origin-drop.sha256, 377 lines) and of
  # the curated zip's extracted contents (Tape-to-Tape-AnkerGames-
  # zip-contents.sha256, 372 lines) are byte-identical modulo those
  # exclusions. Steam emu: RUNE family (steam_api64.dll +
  # steam_emu.ini at Plugins/x86_64/ replacing the Steamworks API
  # DLL, original kept as steam_api64.rne beside it, appid 1566200,
  # BuildId 26471720; the 32-bit steam_api.dll/steam_api.rne pair is
  # the same treatment). It ships no steamclient64.dll, so the
  # AGENTS.md lsteamclient-disable rule for steamclient-shipping emu
  # packs does not apply. No non-IPFS mirror of these bytes exists
  # (the paid Steam build is the only official source), so
  # fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeicd7llvb2znhgj7qw4qpfxgyb2oexwyiccifbfyx3zqtlffvjowty";
    fallbackUrl = "";
    hash = "sha256-Awcw8Y6nJE36c0nAyxIwbNUCeKbIIYdd8sNXUPP+9Xw=";
    name = "tape-to-tape-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "tape-to-tape";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Tape to Tape/" with "Tape to Tape.exe" +
  # Tape to Tape_Data/ + UnityPlayer.dll + GameAssembly.dll + the
  # RUNE emu under Plugins/x86_64/ + the D3D12 Agility SDK dir) and
  # nothing else at the zip root; the site debris never entered this
  # zip. Members are deflate-compressed; 7zz extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Tape to Tape/"* "$out"/
  '';

  runtime = "proton";

  executable = "Tape to Tape.exe";

  # Unity 6000.0.79f1 IL2CPP persistentDataPath from app.info
  # (company "Excellent Rectangle", product "Tape to Tape").
  saveLocations = [ "AppData/LocalLow/Excellent Rectangle/Tape to Tape" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\1566200) at
  # drive_c/users/Public/Documents/Steam/RUNE/1566200, which
  # saveLocations cannot express: its relocation loop is hardcoded to
  # drive_c/users/steamuser/. Apply the same copy-out-and-symlink
  # mechanism from preRun for the Public path (probably-stolen
  # precedent). The in-tree steam_emu.ini gets the same treatment
  # (can-em-all precedent): copy it out to the state dir and symlink
  # back, so the emu's runtime writes to its ini land in the
  # persistent state dir directly instead of depending on overlay
  # copy-up next to the read-only store tree.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/1566200"
    __strom_rune_dst="$STROM_GAMEDIR/rune-1566200"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"

    __strom_ini="Tape to Tape_Data/Plugins/x86_64/steam_emu.ini"
    __strom_ini_dst="$STROM_GAMEDIR/rune-1566200-steam-emu.ini"
    if [ ! -e "$__strom_ini_dst" ] && [ -f "$GAMEDIR/$__strom_ini" ]; then
      cp "$GAMEDIR/$__strom_ini" "$__strom_ini_dst"
    fi
    rm -f "$GAMEDIR/$__strom_ini"
    ln -snf "$__strom_ini_dst" "$GAMEDIR/$__strom_ini"
  '';

  # No gamescope overrides: fullscreen and resolution behavior are
  # unverified pending the operator playthrough.

  meta = {
    description = "Tape to Tape (Excellent Rectangle 2026 roguelite hockey game, build the best hockey team on a road trip of choices, synergies and bribed referees, Unity 6000.0 IL2CPP via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "tape-to-tape";
  };
}
