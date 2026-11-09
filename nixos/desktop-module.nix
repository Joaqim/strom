# NixOS module: install the strom web GUI and register the `strom://` URI
# scheme handler so the catalog's Play button can launch games.
#
# Usage in a flake:
#
#   {
#     imports = [ strom.nixosModules.strom-desktop ];
#     programs.strom-desktop.enable = true;
#   }
#
# This pulls `strom-gui` (run it to open the catalog) and `strom-launch` into
# the system profile and makes strom-launch.desktop the default handler for
# x-scheme-handler/strom.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.strom-desktop;
  scripts = self.legacyPackages.${pkgs.system}.scripts;
in
{
  options.programs.strom-desktop = {
    enable = lib.mkEnableOption "the strom web GUI and strom:// launch handler";

    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:kraftwerk-gaming/strom";
      description = ''
        Flake reference that `strom-launch` runs games from. Override to point
        at a local checkout (e.g. "path:/home/you/strom") for development.
      '';
    };

    noGamescope = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to run games without per-game gamescope, exported as
        STROM_NO_GAMESCOPE=1 for every session. Both strom-launch and the
        couch launcher then pick each game's `.no-gamescope` passthru,
        rendering directly on the session compositor -- for seats where the
        session itself is already a gamescope kiosk, or the host compositor
        is preferred.

        Known cost: strom-screenshot and strom-ip liveness checks rely on
        gamescope's nested Wayland session and report running games as
        not-running, and the Qt-based emulator runtimes (pcsx2, dolphin,
        azahar) refuse to build without gamescope -- those games cannot be
        launched this way.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Relocatable root for strom game state and Proton prefixes, exported
        as STROM_STATE_HOME for every session. When null (the default), game
        wrappers keep using ~/.strom under each launching user's HOME. When
        set (e.g. "/var/lib/steam/strom"), game state and compatdata live
        under that directory instead -- for couch/headless deployments where
        state belongs on persistent system storage rather than a roaming or
        shared HOME.

        The directory is created by a systemd-tmpfiles rule owned by
        `stateDirUser`:`stateDirGroup`. With the default owner (root) the
        directory is NOT writable by regular users: whoever launches games
        must be able to write below it, so either set `stateDirUser` to the
        desktop user or arrange ownership yourself. The directory is NOT
        created when this option is null.
      '';
    };

    stateDirUser = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        User owning the directory created for `stateDir`. Set to the desktop
        user that launches games; with the default "root" (and mode 0750)
        unprivileged launches cannot write state under it.
      '';
    };

    stateDirGroup = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        Group owning the directory created for `stateDir`.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          scripts.gui
          scripts.strom-launch
        ];

        # Make the launch handler the default for the strom:// scheme.
        xdg.mime.enable = true;
        xdg.mime.defaultApplications."x-scheme-handler/strom" = "strom-launch.desktop";

        # Point the handler (and GUI's launch hand-off) at the configured flake.
        environment.sessionVariables.STROM_FLAKE = cfg.flake;
      }

      (lib.mkIf (cfg.stateDir != null) {
        environment.sessionVariables.STROM_STATE_HOME = cfg.stateDir;

        systemd.tmpfiles.rules = [
          "d \"${cfg.stateDir}\" 0750 ${cfg.stateDirUser} ${cfg.stateDirGroup} -"
        ];
      })

      (lib.mkIf cfg.noGamescope {
        environment.sessionVariables.STROM_NO_GAMESCOPE = "1";
      })
    ]
  );
}
