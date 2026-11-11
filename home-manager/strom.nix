{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.strom;
  env =
    { }
    // (lib.optionalAttrs (cfg.stateHome != null) { STROM_STATE_HOME = cfg.stateHome; })
    // (lib.optionalAttrs (cfg.gamescope.outputWidth != null) {
      STROM_GAMESCOPE_OUTPUT_WIDTH = toString cfg.gamescope.outputWidth;
    })
    // (lib.optionalAttrs (cfg.gamescope.outputHeight != null) {
      STROM_GAMESCOPE_OUTPUT_HEIGHT = toString cfg.gamescope.outputHeight;
    })
    // (lib.optionalAttrs (cfg.gamescope.nestedWidth != null) {
      STROM_GAMESCOPE_NESTED_WIDTH = toString cfg.gamescope.nestedWidth;
    })
    // (lib.optionalAttrs (cfg.gamescope.nestedHeight != null) {
      STROM_GAMESCOPE_NESTED_HEIGHT = toString cfg.gamescope.nestedHeight;
    })
    // (lib.optionalAttrs (cfg.gamescope.fullscreen == true) { STROM_GAMESCOPE_FULLSCREEN = "1"; });
  environmentD = lib.concatMapStringsSep "\n" (n: "${n}=${env.${n}}") (lib.attrNames env) + "\n";
in
{
  options.programs.strom = {
    enable = lib.mkEnableOption "the strom per-user environment (gamescope preferences, state home)";

    gamescope = {
      outputWidth = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Session-wide output width; overrides every recipe's pinned width at launch. Null keeps recipe pins.";
      };
      outputHeight = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Session-wide output height; overrides every recipe's pinned height at launch. Null keeps recipe pins.";
      };
      nestedWidth = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Nested-session width override. Null keeps gamescope defaults.";
      };
      nestedHeight = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Nested-session height override. Null keeps gamescope defaults.";
      };
      fullscreen = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "True appends --fullscreen for every game (the wrapper matches the literal value 1). Null emits nothing.";
      };
    };

    stateHome = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.xdg.stateHome + "/strom";
      description = "Per-user root for strom game state and Proton prefixes, exported as STROM_STATE_HOME. Null means this module does not manage it; the NixOS desktop module's stateDir must not also be set — exactly one owner.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = env;
    # The login-boundary carrier: the systemd user manager reads
    # environment.d at start, so seat-launched sessions (D-Bus
    # activation, launcher, gamescope) inherit these alongside the
    # shell-sourced home.sessionVariables.
    xdg.configFile."environment.d/10-strom.conf".text = environmentD;
  };
}
