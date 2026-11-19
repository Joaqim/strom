{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/potato-please, which 403s behind
  # Cloudflare when probed headlessly; the site origin is proven by
  # the drop's own debris - AnkerGames.url, readme.txt, "Run
  # Me!.bat") of the Windows build, Steam appid 5266240 (Potato
  # Please, Golden Horn Studios, released 2026-11-03; the appid
  # comes from the RUNE emu ini and Steam appdetails, which resolves
  # 5266240 to this exact name and developer). Unity 6000.3.11f1
  # IL2CPP (GameAssembly.dll +
  # il2cpp_data/Metadata/global-metadata.dat), Burst
  # (lib_burst_generated.dll), Addressables (StreamingAssets/aa),
  # D3D12 Agility SDK (D3D12/D3D12Core.dll), hdr-display-enabled=0
  # in boot.config. Origin: the site zip
  # Potato-Please-AnkerGames.zip, 1,054,082,916 bytes, sha256
  # 3187cb6ffd3a2b0672cf739c438f06964be6b8beff60550afd0a1de5dfd4bda4,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly five exclusions
  # (AnkerGames.url, readme.txt, "Run Me!.bat", Redist/DXWebSetup.exe,
  # Redist/vc_redist.x64.exe) is the canonical artifact:
  # 1,029,156,361 bytes, sha256
  # c5ef7271cc6e2031599de4a581a2ba53246de6189ac9dd06475ec0a1df38f0f8,
  # deflate members (two tiny ones stored), single root folder
  # "Potato Please" (77 files, 14 dir entries); per-file sha256
  # manifests of the untouched drop (Potato-Please-AnkerGames-origin-
  # drop.sha256, 82 lines) and of the curated zip's extracted
  # contents (Potato-Please-AnkerGames-zip-contents.sha256, 77 lines)
  # are byte-identical modulo those exclusions. Steam emu: RUNE
  # family (steam_api64.dll + steam_emu.ini at Plugins/x86_64/
  # replacing the Steamworks API DLL, original kept as steam_api64.rne
  # beside it, appid 5266240, BuildId 26529021). The 32-bit
  # steam_api.dll/steam_api.rne pair is byte-identical (sha256
  # f21bd0a0b2fd38580c72a89b1bc6cf417544a63edad31addc919f31211e207e3,
  # 924,824 B each) and matches neither Steamworks.NET.txt's
  # documented 32-bit original size (274,584 B) nor the pattern of
  # the 64-bit pair (rne = pristine original); inert for a 64-bit
  # game, provenance unclear. It ships no steamclient64.dll, so the
  # AGENTS.md lsteamclient-disable rule for steamclient-shipping emu
  # packs does not apply. No non-IPFS mirror of these bytes exists
  # (the paid Steam build is the only official source), so
  # fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeih7abvspmhj7tkbtw5dxo7tbw4f4ityrao5ihnc4giwmb2iezw5pm";
    fallbackUrl = "";
    hash = "sha256-xe9yccxuIDFZneSlgaK6UyRt5hiayd0GR17Aod848Pg=";
    name = "potato-please-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "potato-please";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Potato Please/" with PotatoPlease.exe +
  # PotatoPlease_Data/ + UnityPlayer.dll + GameAssembly.dll + the
  # RUNE emu under Plugins/x86_64/ + the D3D12 Agility SDK dir) and
  # nothing else at the zip root; the site debris never entered this
  # zip. Members are deflate-compressed (two tiny ones stored); 7zz
  # extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Potato Please/"* "$out"/
  '';

  runtime = "proton";

  executable = "PotatoPlease.exe";

  # Unity 6000.3.11f1 IL2CPP persistentDataPath from app.info
  # (company "GoldenHorn", product "PotatoPlease"); observed created
  # in the prefix on first boot (Player.log) during the headless
  # smoke.
  saveLocations = [ "AppData/LocalLow/GoldenHorn/PotatoPlease" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\5266240) at
  # drive_c/users/Public/Documents/Steam/RUNE/5266240, which
  # saveLocations cannot express: its relocation loop is hardcoded to
  # drive_c/users/steamuser/. Apply the same copy-out-and-symlink
  # mechanism from preRun for the Public path (tape-to-tape
  # precedent). The in-tree steam_emu.ini gets the same treatment
  # (can-em-all precedent): copy it out to the state dir and symlink
  # back, so the emu's runtime writes to its ini land in the
  # persistent state dir directly instead of depending on overlay
  # copy-up next to the read-only store tree.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/5266240"
    __strom_rune_dst="$STROM_GAMEDIR/rune-5266240"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"

    __strom_ini="PotatoPlease_Data/Plugins/x86_64/steam_emu.ini"
    __strom_ini_dst="$STROM_GAMEDIR/rune-5266240-steam-emu.ini"
    if [ ! -e "$__strom_ini_dst" ] && [ -f "$GAMEDIR/$__strom_ini" ]; then
      cp "$GAMEDIR/$__strom_ini" "$__strom_ini_dst"
    fi
    rm -f "$GAMEDIR/$__strom_ini"
    ln -snf "$__strom_ini_dst" "$GAMEDIR/$__strom_ini"
  '';

  # No gamescope overrides: fullscreen and resolution behavior are
  # unverified pending the operator playthrough.

  meta = {
    description = "Potato Please (Golden Horn Studios 2026 first-person potato-peeling game, peel a mountain of potatoes with real physics, cut thin and waste nothing, Unity 6000.3 IL2CPP via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "potato-please";
  };
}
