{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/thank-goodness-you-re-here;
  # verified reachable: plain curl with a browser UA answers 200
  # at the exact URL, zero redirects, canonical/og:url match) of
  # the Windows build of Thank Goodness You're Here! (Coal
  # Supper, publisher Panic, released 2024-08-01, Steam appid
  # 2366980; site version v1.6.1, page title "Thank Goodness
  # You're Here! Free Download (v1.6.1) | AnkerGames", page
  # "Current Build" 15669091 -- the drop's RUNE ini carries no
  # BuildId field, so the page's build id is the only build
  # provenance available -- "Last Steam Update Sep 17, 2024").
  # Unity 2021.3.34f1 IL2CPP, 32-BIT x86 (PE i386 player exe,
  # GameAssembly.dll + il2cpp_data/Metadata/global-metadata.dat,
  # Plugins/x86, UnityCrashHandler32.exe), FMOD (fmodstudio.dll +
  # resonanceaudio.dll), Rewired input, Burst, Addressables-style
  # CompBundles (96 bundles, levels 0-118). EOSSDK-Win32-
  # Shipping.dll is present but unpatched with zero EOS config in
  # the tree: inert. Origin: the site zip
  # Thank-Goodness-You-re-Here-AnkerGames.zip, 683,214,697 bytes
  # (= 651.62 MiB, matching the site's "PC 651.6 MB" listing
  # exactly), sha256
  # a797f6699bfaeaa55a74f512ce94bb93e1877cc531939c395d98fcfcbff76146,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly two exclusions
  # ("AnkerGames - Free Pre-installed PC Games.url", "Read Me.txt";
  # this drop ships no "Run Me!.bat" and no Redist/) is the
  # canonical artifact: 667,587,519 bytes, sha256
  # 959f38447bd8c1228e8ec0de1ab011940c522e6b67224aa67ac5006dc50601d2,
  # 843,443,870 bytes uncompressed, single root folder "Thank
  # Goodness You're Here!" (427 files, 10 dir entries), deflate
  # members. Steam emu: RUNE family per the ini banner + .rne
  # convention, 32-bit (Plugins/x86/
  # steam_api.dll 853,600 bytes + steam_emu.ini replacing the
  # Steamworks API DLL, original kept as steam_api.rne 103,920
  # bytes beside it; the tree's Steamworks.NET.txt documents
  # 266,600 bytes for its binding's original, so the shipped .rne
  # differs -- harmless, the .rne is never loaded; the site
  # labels the release group "Own CSF", recorded alongside the
  # ini evidence). AppId split
  # (fleet precedent: the emu ini is never modified): steam_emu.ini
  # carries AppId=1575940, a FOREIGN appid the repacker reused
  # (Sins of a Solar Empire II's); the real Steam appid is 2366980,
  # which is what metadata.json's appid and the Steam catalog
  # carry. The emu's Steam-Cloud path below therefore keys to the
  # ini's 1575940, the path the emu actually touches at runtime.
  # No steamclient dll anywhere in the tree, so the AGENTS.md
  # lsteamclient-disable rule for steamclient-shipping emu packs
  # does not apply. No non-IPFS mirror of these bytes exists (the
  # paid Steam build is the only official source), so fallbackUrl
  # stays empty.
  src = fetchIpfs {
    cid = "bafybeieo6ycvsbsmypmhdy7fvx2kexvktfl3zh4aepst2obhzocgr5f7oq";
    fallbackUrl = "";
    hash = "sha256-lZ84RHvYwSKOjsDeGrARlAxSLmtnIkqmesUAbcUGAdI=";
    name = "thank-goodness-youre-here-ankergames-repack.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "thank-goodness-youre-here";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Thank Goodness You're Here!/" holding the player
  # exe of the same name + the matching _Data/ dir +
  # GameAssembly.dll + UnityPlayer.dll + the RUNE emu under
  # Plugins/x86/) and nothing else at the zip root; the site debris
  # never entered this zip. Members are deflate-compressed; 7zz
  # extracts cleanly.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Thank Goodness You're Here!/"* "$out"/
  '';

  runtime = "proton";

  executable = "Thank Goodness You're Here!.exe";

  # Unity 2021.3.34f1 IL2CPP persistentDataPath from app.info
  # (company "Coal Supper", product "Thank Goodness You're
  # Here!"); observed created in the prefix on first boot
  # (Player.log + saves/).
  saveLocations = [ "AppData/LocalLow/Coal Supper/Thank Goodness You're Here!" ];

  # The RUNE emu keeps its Steam-Cloud emulation (per steam_emu.ini:
  # %SystemDrive%\Users\Public\Documents\Steam\RUNE\1575940 -- the
  # FOREIGN appid the repacker reused, see the src comment; the emu
  # touches this path at runtime) at
  # drive_c/users/Public/Documents/Steam/RUNE/1575940, which
  # saveLocations cannot express: its relocation loop is hardcoded
  # to drive_c/users/steamuser/. Apply the same copy-out-and-symlink
  # mechanism from preRun for the Public path (tape-to-tape
  # precedent). The in-tree steam_emu.ini gets the same treatment
  # (can-em-all precedent): copy it out to the state dir and symlink
  # back, so the emu's runtime writes to its ini land in the
  # persistent state dir directly instead of depending on overlay
  # copy-up next to the read-only store tree.
  preRun = ''
    __strom_rune="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/RUNE/1575940"
    __strom_rune_dst="$STROM_GAMEDIR/rune-1575940"
    mkdir -p "$__strom_rune_dst"
    if [ -d "$__strom_rune" ] && [ ! -L "$__strom_rune" ]; then
      cp -an "$__strom_rune/." "$__strom_rune_dst/" 2>/dev/null || true
      rm -rf "$__strom_rune"
    fi
    mkdir -p "$(dirname "$__strom_rune")"
    ln -snf "$__strom_rune_dst" "$__strom_rune"

    __strom_ini="Thank Goodness You're Here!_Data/Plugins/x86/steam_emu.ini"
    __strom_ini_dst="$STROM_GAMEDIR/rune-1575940-steam-emu.ini"
    if [ ! -e "$__strom_ini_dst" ] && [ -f "$GAMEDIR/$__strom_ini" ]; then
      cp "$GAMEDIR/$__strom_ini" "$__strom_ini_dst"
    fi
    rm -f "$GAMEDIR/$__strom_ini"
    ln -snf "$__strom_ini_dst" "$GAMEDIR/$__strom_ini"
  '';

  # No renderer override: the fleet's Unity 2021.3 Windows-under-
  # Proton precedent (probably-stolen, 2021.3.45f2) needs none --
  # the player's D3D11 path routes through DXVK. Confirmed by the
  # headless smoke: Player.log initialized Direct3D 11.0 on RADV.
  # The Unity-2021 -force-glcore trap is specific to NATIVE
  # players (darkwood).

  # No gamescope overrides: fullscreen and resolution behavior are
  # unverified pending the operator playthrough.

  meta = {
    description = "Thank Goodness You're Here! (Coal Supper 2024 absurd comedy adventure, wander the oddball northern English town of Barnsworth doing odd jobs, 32-bit Unity 2021.3 IL2CPP via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "thank-goodness-youre-here";
  };
}
