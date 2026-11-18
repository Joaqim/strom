{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

# Operator-curated zip of an AnkerGames pre-installed repack
# (https://ankergames.net/game/bodycam) of the Windows build, Steam
# appid 2406770 (Bodycam, Reissad Studio, released 2024-06-03 early
# access; the appid comes from the fix's OnlineFix.ini RealAppId and
# Steam appdetails, which resolve 2406770 to this exact name and
# developer). UE 5.5 (SteamCorePro_5.5 plugin, D3D12 Agility SDK,
# DirectML, boost python311 DLL set, SDL2; D3D12 renderer with DLSS
# 8.9.0 / FSR 4.1.1 / XeSS 3.0.5 / Streamline plugin trees). The drop
# carries an EasyAntiCheat (EOS flavour) tree at the game root.
# Origin: the site zip Bodycam-AnkerGames.zip, 67,631,001,916 bytes,
# sha256
# b7e5fbadcb9c57c605f846540099c7e72a1fa94906711eb3026a55ae100920a2,
# a genuine zip64 with zstd-compressed members (7zz 26.02 decodes;
# _7zz extracts it in the dataArchive materializer), 570 files, 111
# folders, 74,778,936,813 bytes uncompressed, holding the game root
# folder beside root-level site debris. The game root Bodycam/ holds
# the nested project dir Bodycam/Bodycam/ (Binaries/Win64/
# Bodycam-Win64-Shipping.exe, 180,773,376 bytes) plus Engine/, the
# 3.9 MB Easy Anti-Cheat Bootstrapper v1.9.0 (EOS flavour)
# Bodycam.exe and _CommonRedist/. The curated
# zip of the drop minus exactly three exclusions ("AnkerGames - Free
# Pre-installed PC Games.url", "Read Me.txt", "Run Me!.bat") is the
# canonical artifact: 67,632,978,155 bytes, sha256
# 5606be9234497f30ad84acd51b502caac16ae9a29c4e4422cc3da2028fcf6a79,
# deflate members (on this mostly-incompressible pak data, 0.003
# percent larger than the zstd origin), single root folder "Bodycam"
# (567 files); per-file
# sha256 manifests of the untouched drop
# (/var/lib/steam/game-archives/Bodycam-AnkerGames-origin-drop.sha256,
# 570 files) and of the curated zip's member contents
# (Bodycam-AnkerGames-zip-contents.sha256, 567 files, streamed
# per-member sha256 -- byte-identical to a hash of the extracted
# tree) are byte-identical modulo those exclusions.
#
# Steam emu, two layers: the repack itself ships a Goldberg-family
# emu applied in-tree at Bodycam/Bodycam/Plugins/SteamCorePro_5.5/
# Source/ThirdParty/SteamLibrary/redistributable_bin/win64/
# (steam_api64.dll 11,235,240 B + steam_settings/, original kept as
# steam_api64.dll.bak), and the operator's separate online-fix drop
# (Bodycam_Fix_Repair_Steam_V9_Generic.zip, 28,485,339 bytes, sha256
# 36e48ac5e9d4f076a882d49e2927985840b7cbc689a74793431cb87ac04f5301,
# pinned as the fetchIpfs FOD below) replaces it with the OnlineFix
# stack: its zip root maps onto the game root (the fix's Bodycam/
# member dir lands on the project dir -- the fix's own launch_data.of
# reads "Bodycam\Binaries\Win64\Bodycam-Win64-Shipping.exe", a path
# from that root; the fix's steam_api64.dll, 319,584 B, is
# byte-identical to the repack's .bak original it restores, and its
# Bodycam.of, 3,946,736 B, is byte-identical to the base's EAC
# bootstrapper it displaces; the fix's
# EOSSDK-Win64-Shipping.of, 18,266,584 B, is the same size as the
# base's EOSSDK .bak but not byte-identical -- two different EOSSDK
# builds of equal size). The fix's 327,680 B 32-bit Bodycam.exe
# launcher therefore becomes the launch entrypoint. OnlineFix.ini
# pins RealAppId=2406770, FakeAppId=480, full interface emulation
# plus an EOSAuthWrapper DeviceIdAuth mode carried by its 8,600,576 B
# EOSSDK-Win64-Shipping.dll replacement. Neither archive ships a
# steamclient64.dll, so the AGENTS.md lsteamclient-disable rule for
# steamclient-shipping emu packs does not apply.
#
# Consumed out-of-store (dataArchive): the curated zip never enters a
# derivation; the wrapper materializes it into the state dir at
# launch from the operator's static archive directory or the local
# kubo gateway (see lib/data-materializer.sh). The online-fix overlay
# rides above it as the `onlineFix` mod layer (a 28 MiB store tree,
# the one game-byte exception inside an otherwise free-software
# closure). This consumption form is fork-develop-local and is never
# cherry-picked upstream. Operator playthrough 2026-11-17/18:
# single-player confirmed with the fix overlay active; online
# lobbies join but freeze at server connect (open issue). First
# plain-variant launch 2026-11-18: the base root Bodycam.exe is the
# EAC Bootstrapper, which showed its splash, downloaded the linux64
# EAC module, and the shipping exe crashed at t=0 (UECC
# CrashContext, AV read 0x8 on GameThread). EAC is bypassed by
# entrypoint choice on both paths: the fix launcher shadows the
# bootstrapper in the overlay, and the plain path execs the shipping
# exe directly. The fix is opt-in, default off.
let
  fix = fetchIpfs {
    cid = "bafybeigldtgjgzu263k2enqz46kzyy4sxtnna3z74j2scdgb5m5tmw6aeq";
    fallbackUrl = "";
    hash = "sha256-NuSKxenU8HaogtSeKSeYWEC3y8aJp0eTQxy4esBPUwE=";
    name = "bodycam-onlinefix-v9.zip";
  };

  # The fix zip extracted 1:1 into overlay layout: its root IS the
  # game root (Bodycam/ project fragments, Bodycam.exe launcher,
  # Bodycam.of preserved original, Engine/ EOSSDK pair,
  # launch_data.of), merged over the materialized base by overlay
  # lowerdir priority (this tree first = highest, shadowing the
  # repack's emu dll, its bootstrapper and its EOSSDK).
  fixTree = pkgs.runCommandLocal "bodycam-onlinefix" { nativeBuildInputs = [ _7zz ]; } ''
    mkdir -p "$out"
    7zz x -y -bso0 -bsp0 -o"$out" "${fix}"
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  imports = [
    (
      { config, lib, ... }:
      let
        inherit (lib) mkOption types;
      in
      {
        options.onlineFix = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Experimental online-multiplayer path: replaces the repack's
            Goldberg single-player emu with the online-fix stack and bridges
            the host Steam client for its activation. Requires the host
            Steam client running with Spacewar (appid 480) installed; a
            join freeze at server connect is a known open issue. The row
            also surfaces on Android, where the fix is untested.

            Everything the fix needs switches on together: the overlay
            lower above the materialized base, the steamclient bridge,
            the SteamAppId/SteamGameId/WINEDLLOVERRIDES env, and the
            entrypoint (the fix's Bodycam.exe launcher). Without it the
            wrapper execs the shipping exe directly, bypassing the EAC
            bootstrapper the base tree keeps at Bodycam.exe.
          '';
        };

        config = {
          # The fix overlay above the materialized base (see the
          # provenance comment: replaces the repack's Goldberg dll with
          # the original, adds the OnlineFix winmm proxy next to the
          # shipping exe, swaps EOSSDK, installs the fix launcher).
          modLayers = lib.optional config.onlineFix {
            key = "onlineFix";
            value = "true";
            tree = fixTree;
          };

          # The fix's "Steamworks Fix Activation" gate demands a live
          # Steam entitlement for FakeAppId 480 (Spacewar) over
          # steamclient IPC; the bridge lets the game's chain reach the
          # operator's running host Steam instead of the ABI stub.
          steamBridge = config.onlineFix;

          # RealAppId from OnlineFix.ini; the emu spoofs the interface,
          # the env keeps proton's own app-id view coherent with it.
          # winmm=n,b forces wine to load the fix's native winmm.dll
          # proxy ahead of its builtin (the ROUNDS winhttp=n,b precedent
          # for proxy dlls).
          env = lib.mkIf config.onlineFix {
            SteamAppId = "2406770";
            SteamGameId = "2406770";
            WINEDLLOVERRIDES = "winmm=n,b";
          };

          # EAC bypass by entrypoint choice (see the provenance
          # comment): the base root Bodycam.exe is the EAC Bootstrapper,
          # so the plain path goes straight to the shipping exe -- also
          # the target the fix's own launch_data.of names -- and the fix
          # path runs Bodycam.exe, which the overlay has replaced with
          # the fix's launcher. Not the repack's "Run Me!.bat" recipe,
          # which starts the shipping exe bare, bypassing the fix.
          executable =
            if config.onlineFix then "Bodycam.exe" else "Bodycam/Binaries/Win64/Bodycam-Win64-Shipping.exe";
        };
      }
    )
  ];

  name = "bodycam";

  dataArchive = {
    cid = "bafybeih2fltvaazjpfz4ux3fdo2jss7gkvp5uprbdwd5pwcp5hf4tcqc3a";
    sha256 = "5606be9234497f30ad84acd51b502caac16ae9a29c4e4422cc3da2028fcf6a79";
    size = 67632978155;
    fileName = "Bodycam-AnkerGames-Repack.zip";
    rootFolder = "Bodycam";
  };

  runtime = "proton";

  # UE5 writes saves and settings under %LOCALAPPDATA%\Bodycam\Saved
  # (drive_c/users/steamuser/AppData/Local/Bodycam/Saved); relocate
  # the standard UE tree so settings survive a prefix wipe. Any
  # further engine paths (EOS/EAC user state) get discovered by the
  # runtime ladder's find -newer sweep and appended here.
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
    description = "Bodycam (Reissad Studio 2024 UE5 ultra-realistic multiplayer shooter built around bodycam footage, via Proton; single-player on the repack's Goldberg emu, experimental online fix opt-in)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bodycam";
  };
}
