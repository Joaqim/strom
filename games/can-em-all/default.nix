{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/can-em-all) of the Windows build,
  # Steam appid 5133900 (Can 'Em All, LuisDev, released 2026-10-30;
  # the appid
  # comes from the RUNE emu ini and Steam appdetails, which resolves
  # 5133900 to this exact name and developer). Unity 6000.2.15f1
  # IL2CPP (GameAssembly.dll +
  # il2cpp_data/Metadata/global-metadata.dat), Steam Audio
  # (phonon.dll, TrueAudioNext.dll, audioplugin_phonon.dll), D3D12
  # Agility SDK (D3D12/D3D12Core.dll), hdr-display-enabled=0 in
  # boot.config. Origin: the site zip Can-Em-All-AnkerGames.zip,
  # 425,737,381 bytes, sha256
  # ff680d89713ee0e954d6214a1ffbc99bea5ac55b0a23594be530d43a8c80c17a,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly five exclusions
  # (AnkerGames.url, readme.txt, "Run Me!.bat", Redist/DXWebSetup.exe,
  # Redist/vc_redist.x64.exe) is the canonical artifact: 410,796,374
  # bytes, sha256
  # 581ce5801bf923d9b518050f5a389b56ede63b123c1cd15c69179347613a9385,
  # deflate members, single root folder "Can 'Em All" (38 files,
  # 9 dir entries); per-file sha256 manifests of the untouched drop
  # (Can-Em-All-AnkerGames-origin-drop.sha256, 43 lines) and of the
  # curated zip's extracted contents (Can-Em-All-AnkerGames-zip-
  # contents.sha256, 38 lines) are byte-identical modulo those
  # exclusions. Steam emu: RUNE family (steam_api64.dll +
  # steam_emu.ini at Plugins/x86_64/ replacing the Steamworks API
  # DLL, original kept as steam_api64.rne beside it, appid 5133900,
  # BuildId 26596503; the 32-bit steam_api.dll is the original). It
  # ships no steamclient64.dll, so the AGENTS.md lsteamclient-disable
  # rule for steamclient-shipping emu packs does not apply. No
  # non-IPFS mirror of these bytes exists (the paid Steam build is
  # the only official source), so fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeidi5qzg4xqucz2ra75fv44wmilp5sce47ooa75bqr4onlumccylze";
    fallbackUrl = "";
    hash = "sha256-WBzlgBv5I9m1GAUPWjibVu3mOxI8HNFcaReTR2E6k4U=";
    name = "can-em-all-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "can-em-all";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Can 'Em All/" with "Can 'Em All.exe" +
  # Can 'Em All_Data/ + UnityPlayer.dll + GameAssembly.dll + the
  # RUNE emu under Plugins/x86_64/ + the D3D12 Agility SDK dir) and
  # nothing else at the zip root; the site debris never entered this
  # zip. Members are deflate-compressed; 7zz extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Can 'Em All/"* "$out"/
  '';

  runtime = "proton";

  executable = "Can 'Em All.exe";

  # Unity 6000.2.15f1 IL2CPP persistentDataPath from app.info
  # (company "LuisDev", product "Can 'Em All"); observed created
  # in the prefix on first boot (Player.log + settings.sav).
  saveLocations = [ "AppData/LocalLow/LuisDev/Can 'Em All" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\5133900) at
  # drive_c/users/Public/Documents/Steam/RUNE/5133900, which
  # saveLocations cannot express: its relocation loop is hardcoded to
  # drive_c/users/steamuser/. Apply the same copy-out-and-symlink
  # mechanism from preRun for the Public path (probably-stolen
  # precedent). The in-tree steam_emu.ini gets the same treatment
  # (south-of-midnight precedent): copy it out to the state dir and
  # symlink back, so the emu's runtime writes to its ini land in the
  # persistent state dir directly instead of depending on overlay
  # copy-up next to the read-only store tree.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/5133900"
    __strom_rune_dst="$STROM_GAMEDIR/rune-5133900"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"

    __strom_ini="Can 'Em All_Data/Plugins/x86_64/steam_emu.ini"
    __strom_ini_dst="$STROM_GAMEDIR/rune-5133900-steam-emu.ini"
    if [ ! -e "$__strom_ini_dst" ] && [ -f "$GAMEDIR/$__strom_ini" ]; then
      cp "$GAMEDIR/$__strom_ini" "$__strom_ini_dst"
    fi
    rm -f "$GAMEDIR/$__strom_ini"
    ln -snf "$__strom_ini_dst" "$GAMEDIR/$__strom_ini"
  '';

  # No gamescope overrides: fullscreen and resolution behavior are
  # unverified pending the operator playthrough.

  meta = {
    description = "Can 'Em All (LuisDev 2026 first-person incremental factory game, blast cute creatures and can them for profit, Unity 6000.2 IL2CPP via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "can-em-all";
  };
}
