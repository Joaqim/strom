#!/usr/bin/env bash
# shellcheck shell=bash
# Fixture: the desktop module exports STROM_ARCHIVES at the
# data-materializer default, an archivesDir assignment relocates it, an
# operator sessionVariables override wins, and a disabled module sets
# nothing.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)

eval_archives() { # args: extra nixos config attr string
  nix eval --impure --raw --expr "
    let f = builtins.getFlake \"path:$repo\";
    in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
      configuration = { imports = [ f.nixosModules.strom-desktop ]; $1 };
    }).config.environment.sessionVariables.STROM_ARCHIVES" 2>&1
}

got=$(eval_archives 'programs.strom-desktop.enable = true;')
[ "$got" = "/var/lib/steam/game-archives" ] && echo "A PASS: default $got" || { echo "A FAIL: got '$got'"; exit 1; }

got=$(eval_archives 'programs.strom-desktop.enable = true; programs.strom-desktop.archivesDir = "/srv/strom/game-archives";')
[ "$got" = "/srv/strom/game-archives" ] && echo "B PASS: option assignment relocates" || { echo "B FAIL: got '$got'"; exit 1; }

got=$(eval_archives 'programs.strom-desktop.enable = true; environment.sessionVariables.STROM_ARCHIVES = "/srv/strom/game-archives";')
[ "$got" = "/srv/strom/game-archives" ] && echo "C PASS: operator sessionVariables override wins" || { echo "C FAIL: got '$got'"; exit 1; }

got=$(nix eval --impure --json --expr "
  let f = builtins.getFlake \"path:$repo\";
  in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
    configuration = { imports = [ f.nixosModules.strom-desktop ]; };
  }).config.environment.sessionVariables ? STROM_ARCHIVES" 2>&1)
[ "$got" = "false" ] && echo "D PASS: disabled module sets nothing" || { echo "D FAIL: got '$got'"; exit 1; }
echo "=== ALL ASSERTS PASS ==="
