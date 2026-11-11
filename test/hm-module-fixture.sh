#!/usr/bin/env bash
# shellcheck shell=bash
# Fixture: programs.strom emits exactly the configured variables into
# home.sessionVariables and the environment.d carrier; null options
# emit nothing.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)

out=$(nix eval --impure --json --expr "
  let
    f = builtins.getFlake \"path:$repo\";
    lib = f.inputs.nixpkgs.lib;
    shim = {
      options = {
        xdg.stateHome = lib.mkOption { type = lib.types.str; default = \"/home/tester/.local/state\"; };
        xdg.configFile = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
        home.sessionVariables = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
      };
    };
    ev = extra: (lib.evalModules { modules = [ shim (import $repo/home-manager/strom.nix) { programs.strom.enable = true; } extra ]; }).config;
    fullCfg = { programs.strom.gamescope.outputWidth = 3440; programs.strom.gamescope.outputHeight = 1440; programs.strom.gamescope.fullscreen = true; programs.strom.stateHome = \"/custom/state\"; };
  in {
    defaults = { vars = (ev {}).home.sessionVariables; ed = (ev {}).xdg.configFile.\"environment.d/10-strom.conf\".text; };
    full = { vars = (ev fullCfg).home.sessionVariables; ed = (ev fullCfg).xdg.configFile.\"environment.d/10-strom.conf\".text; };
    stateHomeNull = { vars = (ev { programs.strom.stateHome = null; }).home.sessionVariables; };
  }")

check() { echo "$out" | jq -rc "$1"; }

sv=$(check '.defaults.vars')
[ "$sv" = '{"STROM_STATE_HOME":"/home/tester/.local/state/strom"}' ] || { echo "A FAIL: $sv"; exit 1; }
echo "A PASS: defaults emit only STROM_STATE_HOME"

sv=$(check '.full.vars')
echo "$sv" | jq -e 'has("STROM_GAMESCOPE_OUTPUT_WIDTH") and has("STROM_GAMESCOPE_OUTPUT_HEIGHT") and has("STROM_GAMESCOPE_FULLSCREEN") and .STROM_GAMESCOPE_FULLSCREEN == "1" and .STROM_GAMESCOPE_OUTPUT_WIDTH == "3440" and (has("STROM_GAMESCOPE_NESTED_WIDTH") | not)' >/dev/null || { echo "B FAIL: $sv"; exit 1; }
echo "B PASS: set options emit, unset stay absent"

ed=$(check '.defaults.ed')
[ "$ed" = 'STROM_STATE_HOME=/home/tester/.local/state/strom' ] || { echo "C FAIL: $ed"; exit 1; }
echo "C PASS: environment.d exact"

ed=$(check '.full.ed')
echo "$ed" | grep -q '^STROM_GAMESCOPE_FULLSCREEN=1$' || { echo "C2 FAIL: $ed"; exit 1; }
echo "C2 PASS: full environment.d carries fullscreen"

sv=$(check '.stateHomeNull.vars')
[ "$sv" = '{}' ] || { echo "D FAIL: $sv"; exit 1; }
echo "D PASS: stateHome null emits nothing"
echo "=== ALL ASSERTS PASS ==="
