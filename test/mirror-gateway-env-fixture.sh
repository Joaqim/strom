#!/usr/bin/env bash
# shellcheck shell=bash
# Fixture: the mirror module derives STROM_IPFS_GATEWAYS from its own
# gateway port when enabled, and an operator override wins.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)

eval_gw() { # args: extra nixos config attr string
  nix eval --impure --raw --expr "
    let f = builtins.getFlake \"path:$repo\";
    in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
      configuration = { imports = [ $repo/nixos/mirror-module.nix ]; $1 };
    }).config.environment.sessionVariables.STROM_IPFS_GATEWAYS" 2>&1
}

got=$(eval_gw 'services.strom-ipfs-mirror.enable = true; services.strom-ipfs-mirror.gatewayPort = 8330;')
[ "$got" = "http://127.0.0.1:8330" ] && echo "A PASS: derived $got" || { echo "A FAIL: got '$got'"; exit 1; }

got=$(eval_gw 'services.strom-ipfs-mirror.enable = true; services.strom-ipfs-mirror.gatewayPort = 8331; environment.sessionVariables.STROM_IPFS_GATEWAYS = "https://gw.example";')
[ "$got" = "https://gw.example" ] && echo "B PASS: operator override wins" || { echo "B FAIL: got '$got'"; exit 1; }

got=$(nix eval --impure --json --expr "
  let f = builtins.getFlake \"path:$repo\";
  in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
    configuration = { imports = [ $repo/nixos/mirror-module.nix ]; };
  }).config.environment.sessionVariables ? STROM_IPFS_GATEWAYS" 2>&1)
[ "$got" = "false" ] && echo "C PASS: disabled service sets nothing" || { echo "C FAIL: got '$got'"; exit 1; }

got=$(nix eval --impure --json --expr "
  let f = builtins.getFlake \"path:$repo\";
  in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
    configuration = { imports = [ $repo/nixos/mirror-module.nix ]; services.strom-ipfs-mirror.enable = true; };
  }).config.nix.envVars ? STROM_IPFS_GATEWAYS" 2>&1)
[ "$got" = "true" ] && echo "D PASS: enabled service exports via nix.envVars" || { echo "D FAIL: got '$got'"; exit 1; }
echo "=== ALL ASSERTS PASS ==="
