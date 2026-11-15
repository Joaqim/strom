{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Operator-curated zip of an AnkerGames pre-installed repack
  # (https://ankergames.net/game/infamous-second-son, page
  # "Infamous Second Son Free Download (v1.07)"). Not a PC port in
  # the usual sense: the drop is issn_pc test build 0.3.7, a GPL
  # v2+ community Windows port (launcher UI plus run.py, whose game
  # process is bin/issn-probe.exe), graphics core axylpup's shadPS4
  # build for Second Son on the gow3_pc (Felipe Prado) /
  # bloodborne_pc lineage with HayatoG's iss_pc work merged, Vulkan
  # 1.3 native - bundled with a PS4 dump of the game (eboot.bin at
  # game/eboot.bin; EU CUSA00004 line: "++ retail 0212.1422 i3_eu
  # ship ++" build folder and a seed autosave under
  # user/savedata/1/CUSA00004; update 01.07, one of the two versions
  # the port supports). The project's own READMEs state it has no
  # relation to Sony Interactive Entertainment or Sucker Punch
  # Productions; inFAMOUS is a Sony trademark. Origin: the site zip
  # Infamous-Second-Son-AnkerGames.zip, 22,999,779,341 bytes, sha256
  # f6484c2499647c0fac88de8571fa4ceb8725ce5e018bf1c512446e67386cb9ea,
  # holding the game folder beside root-level site debris. The
  # curated zip of the drop minus exactly four exclusions
  # ("AnkerGames - Free Pre-installed PC Games.url", "Read Me.txt",
  # "HOW TO RUN THE GAME.txt", "Run Me!.bat") is the canonical
  # artifact: 23,580,013,270 bytes, sha256
  # 77efec36e966d0d1afd09edbd91d329b214c4dab14f5d20a9bddbf7d95f60a02,
  # deflate members, single root folder "Infamous Second Son";
  # per-file sha256 manifests of the untouched drop
  # (/var/lib/steam/game-archives/Infamous-Second-Son-AnkerGames-
  # origin-drop.sha256, 44991 files) and of the curated zip's
  # extracted contents (Infamous-Second-Son-AnkerGames-zip-contents
  # .sha256, 44987 files) are byte-identical modulo those exclusions,
  # and the 18 empty emulator user-state dirs under user/ survive.
  # Not a Steam game (PS4 exclusive, no official PC distribution):
  # the tree carries no steam_api*.dll and no steamclient64.dll, so
  # no steam emu is involved and the AGENTS.md lsteamclient-disable
  # rule for steamclient-shipping emu packs does not apply. No
  # non-IPFS mirror of these bytes exists, so fallbackUrl stays
  # empty.
  src = fetchIpfs {
    cid = "bafybeia3l4evuu6ltvtmgvzknn22ad23f4fhxstr5fhnxc5emppp644kue";
    fallbackUrl = "";
    hash = "sha256-d+/sNulm0NGv0J7b2R0ymyFMTasU9dIKm92/fZX2CgI=";
    name = "infamous-second-son-ankergames-repack.zip";
  };
  # The launcher's options file for the first-boot seed below. Only
  # game_dir is load-bearing: every other field carries the value
  # the launcher itself wrote after the operator completed its
  # folder chooser (its defaults, empty patches and controls maps),
  # so a fresh install parses a schema-complete file instead of
  # betting on partial-JSON tolerance. game_patches is emptied: the
  # operator's two picks are a player choice, not install config.
  # The pick is the overlay mountpoint mk-game fixes at
  # /tmp/.strom-overlay in both src and dataArchive modes, with the
  # archive's root folder stripped, so the PS4 dump sits at game/
  # on the tree top -- the same layout the root-relative
  # `executable` already depends on. builtins.toJSON re-escapes the
  # backslashes exactly as the launcher wrote them (doubled in the
  # JSON text).
  issnSettings = builtins.toJSON {
    ui_language = "";
    game_dir = "Z:\\tmp\\.strom-overlay\\game";
    update_dir = "";
    experimental_upscaler = false;
    video_backend = "auto";
    gamemode = false;
    mangohud = false;
    desktop_integration = true;
    user_dir = "";
    mods_dir = "";
    mods_enabled = true;
    patches_dir = "";
    language = "1";
    game_language = "";
    pad_emulation = "";
    spray_stick = "";
    stick_deadzone = "";
    skip_intro = false;
    save_backups = true;
    vram_limit = "";
    frame_pacing = "";
    frame_gen = false;
    seed_any_profile = false;
    player_name = "";
    hdr = false;
    draw_pipe = "";
    readbacks = "";
    no_msaa = "";
    stream_memory = "cached";
    gpu_id = "";
    background_warmup = true;
    parallel_warmup = true;
    pipeline_binaries = false;
    perf_diag = false;
    frame_capture_key = false;
    frame_stats = false;
    gpu_profile = false;
    vk_validation = false;
    close_on_play = false;
    check_updates = false;
    game_patches = { };
    controls = {
      key = { };
      pad = { };
    };
    pad_style = "xbox";
    glyph_style = "off";
    compute_priority = true;
    ordered_readback = false;
    draw_distance = "";
    perf_mode = "";
    render_height = "";
    upscale_quality = "";
    aniso = "";
    shader_compile = "";
    screen_shape = "";
    anti_aliasing = "game";
    optiscaler_output = "fsr22";
  };

  issnSettingsFile = pkgs.writeText "issn-settings.json" issnSettings;
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "infamous-second-son";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # Curated-zip layout follows the AnkerGames precedent: one root
  # game folder ("Infamous Second Son/" with the launcher exe,
  # run.py, _internal/, bin/, game/, user/, launcher/, out/,
  # patches/, scripts/, fsr4_shaders/, issn.ini) and nothing else at
  # the zip root; the site debris never entered this zip. Members
  # are deflate-compressed; 7zz extracts cleanly. The /. form of the
  # copy also picks up the root dotfile .iss-launcher.lock, which a
  # * glob would skip.
  buildScript = ''
    mkdir -p "$out"
    7zz x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Infamous Second Son/." "$out"/
  '';

  runtime = "proton";

  # "inFAMOUS Second Son.exe" is the launcher UI; the game process
  # it spawns is bin/issn-probe.exe. The repacker's "Play inFAMOUS
  # Second Son.exe" convenience wrapper is not the entry point. The
  # launcher has no game-folder default that matches this drop
  # (launcher/ ships only assets, and run.py defaults ISSN_GAME_DIR
  # to a sibling CUSA00004 folder), so the preRun seed below writes
  # the operator-verified pick into the relocated issn-launcher
  # options dir on first boot and the folder chooser never opens.
  executable = "inFAMOUS Second Son.exe";

  # Per README-Windows.txt ("Data"): game saves (user/savedata),
  # settings (issn.ini), shader cache, trophies and the log all live
  # next to inFAMOUS Second Son.exe, inside the install dir, so they
  # persist via the per-game fuse-overlayfs upper (the drop itself
  # ships a seed autosave at user/savedata/1/CUSA00004/). The one
  # wineprefix path is the launcher's options dir
  # %APPDATA%\issn-launcher, which holds the game-folder selection
  # and the graphics picks: relocate it so a prefix wipe does not
  # lose them. run.py's Documents\inFAMOUS-PC is only "the
  # launcher's choice" for a user dir outside the port; the
  # verification ladder should confirm no other drive_c path appears
  # on first boot.
  saveLocations = [ "AppData/Roaming/issn-launcher" ];

  # Idempotent first-boot seed of the options file: write it only
  # when the relocated issn-launcher dir holds none, never touch one
  # the launcher already owns.
  preRun = ''
    __strom_issn_settings="$STROM_GAMEDIR/issn-launcher/settings.json"
    if [ ! -e "$__strom_issn_settings" ]; then
      mkdir -p "$(dirname "$__strom_issn_settings")"
      cp "${issnSettingsFile}" "$__strom_issn_settings"
      chmod 644 "$__strom_issn_settings"
    fi
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
    description = "inFAMOUS Second Son (Sucker Punch Productions 2014 PS4 open-world superhero action in a locked-down Seattle, via the issn_pc 0.3.7 GPL community port: shadPS4-derived Vulkan 1.3 core running a PS4 1.07 dump through Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "infamous-second-son";
  };
}
