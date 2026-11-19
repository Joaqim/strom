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
if [ "$got" = "http://127.0.0.1:8330" ]; then echo "A PASS: derived $got"; else echo "A FAIL: got '$got'"; exit 1; fi

got=$(eval_gw 'services.strom-ipfs-mirror.enable = true; services.strom-ipfs-mirror.gatewayPort = 8331; environment.sessionVariables.STROM_IPFS_GATEWAYS = "https://gw.example";')
if [ "$got" = "https://gw.example" ]; then echo "B PASS: operator override wins"; else echo "B FAIL: got '$got'"; exit 1; fi

got=$(nix eval --impure --json --expr "
  let f = builtins.getFlake \"path:$repo\";
  in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
    configuration = { imports = [ $repo/nixos/mirror-module.nix ]; };
  }).config.environment.sessionVariables ? STROM_IPFS_GATEWAYS" 2>&1)
if [ "$got" = "false" ]; then echo "C PASS: disabled service sets nothing"; else echo "C FAIL: got '$got'"; exit 1; fi

got=$(nix eval --impure --json --expr "
  let f = builtins.getFlake \"path:$repo\";
  in (import (f.inputs.nixpkgs.outPath + \"/nixos\") {
    configuration = { imports = [ $repo/nixos/mirror-module.nix ]; services.strom-ipfs-mirror.enable = true; };
  }).config.nix.envVars ? STROM_IPFS_GATEWAYS" 2>&1)
if [ "$got" = "true" ]; then echo "D PASS: enabled service exports via nix.envVars"; else echo "D FAIL: got '$got'"; exit 1; fi
echo "=== ALL ASSERTS PASS ==="
