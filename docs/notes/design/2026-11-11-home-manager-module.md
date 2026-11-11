# Home-manager module and system-wide gateway design

Working note recording the approved design for per-user strom preferences (gamescope, state home) and the system-wide IPFS gateway variable.
Date: 2026-11-11.
Status: approved in session; pending implementation.

## Motivation

Gamescope preferences and state location are currently hand-exported environment variables: `STROM_GAMESCOPE_*` has no module wiring at all (the runtime contract in `lib/gamescope.nix` reads them with `:-` defaults), and `STROM_STATE_HOME` is set machine-wide by the desktop module at the login boundary.
On a multi-user seat, preferences are per-user, not per-machine.
Separately, `fetchIpfs` cannot see the local kubo gateway unless `STROM_IPFS_GATEWAYS` is exported manually; on 2026-11-11 this produced a failed game build from a worktree whose shell carried no `.env`, despite the content being pinned and served locally.
Both changes are intended for upstream as optional, non-breaking additions.

## Patch A: system-wide gateway variable (bounded)

`nixos/mirror-module.nix`: when the service is enabled, set

```nix
environment.sessionVariables.STROM_IPFS_GATEWAYS = mkDefault "http://127.0.0.1:${toString cfg.gatewayPort}";
```

The module already binds kubo's gateway to loopback on `cfg.gatewayPort`, so the value is self-consistent by construction.
`mkDefault` keeps operators free to override or extend the list; `fetchIpfs` prefixes injected gateways ahead of the public defaults (`lib/fetch-ipfs.nix:178-186`), so a local-only value never breaks upstream-distributed content.
The `gatewayPort` option documentation changes from instructing operators to export the variable to stating the module sets it.
Machines running kubo without this module are out of scope; the module wires only its own service.

## Patch B: home-manager module and ownership switch

New file `home-manager/strom.nix` (new top-level directory, mirroring `nixos/`), exported as `homeManagerModules.strom` with a `default` alias.

Options:

```nix
programs.strom = {
  enable
  gamescope = { outputWidth, outputHeight, nestedWidth, nestedHeight, fullscreen }  # nullOr, default null
  stateHome   # default config.xdg.stateHome + "/strom"
}
```

Semantics: a `null` gamescope option emits no variable, so recipe pins keep winning — exactly the existing `:-` contract in `lib/gamescope.nix`.
`stateHome = null` means the module does not manage the variable.
`fullscreen` emits `1`; the wrapper appends `--fullscreen` only on the exact value `1` (`lib/gamescope.nix:279`).

Carrier: one generated attribute set, written twice:

- `xdg.configFile."environment.d/10-strom.conf".text` — the login-boundary carrier; the systemd user manager reads `environment.d` at start, so D-Bus activation, the desktop launcher, and seat-launched gamescope sessions inherit it;
- `home.sessionVariables` — terminal parity, same values, single source of truth.

Ownership switch on the NixOS side: `nixos/desktop-module.nix`'s `stateDir` is already `nullOr` with conditional consumers (the session variable and tmpfiles rule are both guarded by `stateDir != null`), so no logic change is needed — only its description gains a pointer to the home-manager module.
When `null`, the module sets no `STROM_STATE_HOME` session variable.
Exactly one owner at a time; the contract is documented rather than asserted, because NixOS modules cannot see home-manager configuration.

## Packaging

Two independent patches, both based on plain upstream master, reviewable separately: the gateway variable (mirror module only) and the home-manager module (new file, desktop-module ownership pointer in its `stateDir` description, README consumption docs).

## Verification ladder

1. Module-eval fixtures in the `test/` idiom: the home-manager module evaluated via `lib.evalModules` with defaults and fully set, asserting unset options emit nothing and set options emit the exact variables.
2. `environment.d` content assertions from the same fixture.
3. `mirror-module` eval with and without an operator override of the variable.
4. Live rung (operator machine, after plan-repo wiring): re-login, `systemctl --user show-environment` contains the variables, a seat-launched game resolves them, and exactly one of system/HM owns `STROM_STATE_HOME`.

## Out of scope

Machines running kubo without the mirror module; launcher preferences and other per-user surfaces beyond gamescope and state home; migration of the existing `/var/lib/steam/strom` tree (an operator-local, deliberate act when per-user state is first adopted).
