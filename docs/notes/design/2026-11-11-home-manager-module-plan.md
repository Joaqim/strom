# Home-manager module and gateway variable — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two upstream patches: (A) the mirror module derives `STROM_IPFS_GATEWAYS` system-wide; (B) a home-manager module owning per-user gamescope preferences and state home.

**Architecture:** Patch A is one `mkDefault` session variable in `nixos/mirror-module.nix`, self-consistent with the module's own loopback gateway bind. Patch B is a new `home-manager/strom.nix` module exported as `homeManagerModules.strom`, writing one generated env attrset twice (`environment.d` for seat reach, `home.sessionVariables` for terminals); the NixOS ownership switch already exists (`stateDir` is `nullOr`) and needs only a description pointer.

**Tech Stack:** Nix module system, home-manager module conventions (no flake input needed — the module is consumed by users' HM setups), systemd `environment.d`, bash test fixtures in the `test/` idiom.

**Spec:** `docs/notes/design/2026-11-11-home-manager-module.md`

## Global Constraints

- Every commit unsigned: `git -c commit.gpgsign=false commit` (global `commit.gpgsign=true` signs otherwise; the rad pre-push hook rejects signed commits).
- Lowercase commit prefixes (`mirror:`, `hm:`, `docs:`), one sentence per line in prose/descriptions.
- Option descriptions are API docs: concise, factual, wrapped in `''`.
- No pushes to any remote during implementation; landing is a separately orchestrated phase.
- Implementation happens in two worktrees branched off `develop`: Task 1 in `.worktrees/feat-gateway-session-var` (branch `feat/gateway-session-var`), Tasks 2-3 in `.worktrees/feat-hm-module` (branch `feat/hm-module`). The two task groups touch disjoint files and may run in parallel.
- Scratch output under `/tmp/`, never untracked files in worktrees.

---

### Task 1: mirror module derives STROM_IPFS_GATEWAYS

**Files:**
- Modify: `nixos/mirror-module.nix` (config block ~:63-100; `gatewayPort` description ~:54-58)
- Create: `test/mirror-gateway-env-fixture.sh`

**Interfaces:**
- Consumes: `services.strom-ipfs-mirror.{enable, gatewayPort}` (existing options).
- Produces: `environment.sessionVariables.STROM_IPFS_GATEWAYS` (mkDefault, string `http://127.0.0.1:<gatewayPort>`) when the service is enabled.

- [ ] **Step 1: Write the failing fixture**

Create `test/mirror-gateway-env-fixture.sh` (executable, `# shellcheck shell=bash` header, PASS/FAIL asserts and exit code, matching `test/screenshot-sidecar-fixture.sh` style):

```bash
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
echo "=== ALL ASSERTS PASS ==="
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash test/mirror-gateway-env-fixture.sh`
Expected: `A FAIL` — the module sets no variable yet (B and C may fail too).

- [ ] **Step 3: Implement**

In `nixos/mirror-module.nix`, inside `config = lib.mkIf cfg.enable { ... }` (after the `networking.firewall` lines), add:

```nix
    # The gateway this module just bound is the fastest source for
    # strom content on this machine: export it for fetchIpfs, which
    # prefixes injected gateways ahead of the public defaults
    # (lib/fetch-ipfs.nix). mkDefault so an operator's own list wins.
    environment.sessionVariables.STROM_IPFS_GATEWAYS =
      lib.mkDefault "http://127.0.0.1:${toString cfg.gatewayPort}";
```

In the `gatewayPort` description, replace the sentence starting "Consumers point at the gateway via `STROM_IPFS_GATEWAYS`" and the following "e.g." / "Operators on 8080 migrate" sentences with:

```nix
        When the service is enabled the module exports the gateway
        address as `STROM_IPFS_GATEWAYS` (mkDefault), so `fetchIpfs`
        prefers it over public gateways; set the variable yourself to
        override or extend the list.
```

- [ ] **Step 4: Run the fixture to verify it passes**

Run: `bash test/mirror-gateway-env-fixture.sh`
Expected: `A PASS`, `B PASS`, `C PASS`, `=== ALL ASSERTS PASS ===`.

- [ ] **Step 5: Commit**

```bash
git add nixos/mirror-module.nix test/mirror-gateway-env-fixture.sh
git -c commit.gpgsign=false commit -m "mirror: derive STROM_IPFS_GATEWAYS from the service's own gateway"
```

---

### Task 2: home-manager module, flake export, eval fixture

**Files:**
- Create: `home-manager/strom.nix`
- Modify: `flake.nix` (after the `nixosModules` block, ~:108-113)
- Create: `test/hm-module-fixture.sh`

**Interfaces:**
- Consumes: HM options `xdg.stateHome`, `xdg.configFile`, `home.sessionVariables` (provided by users' home-manager; by a shim in the fixture).
- Produces: flake output `homeManagerModules.{strom, default}`; module options `programs.strom.{enable, gamescope.{outputWidth, outputHeight, nestedWidth, nestedHeight, fullscreen}, stateHome}`; runtime vars `STROM_STATE_HOME`, `STROM_GAMESCOPE_{OUTPUT,NESTED}_{WIDTH,HEIGHT}`, `STROM_GAMESCOPE_FULLSCREEN` (exact names per `lib/gamescope.nix` contract; fullscreen fires only on literal `1`, `lib/gamescope.nix:279`).

- [ ] **Step 1: Write the failing fixture**

Create `test/hm-module-fixture.sh`:

```bash
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

check() { echo "$out" | jq -r "$1"; }

sv=$(check '.defaults.vars')
[ "$sv" = '{"STROM_STATE_HOME":"/home/tester/.local/state/strom"}' ] && echo "A PASS: defaults emit only STROM_STATE_HOME" || { echo "A FAIL: $sv"; exit 1; }

sv=$(check '.full.vars')
echo "$sv" | jq -e 'has("STROM_GAMESCOPE_OUTPUT_WIDTH") and has("STROM_GAMESCOPE_OUTPUT_HEIGHT") and has("STROM_GAMESCOPE_FULLSCREEN") and .STROM_GAMESCOPE_FULLSCREEN == "1" and .STROM_GAMESCOPE_OUTPUT_WIDTH == "3440" and (has("STROM_GAMESCOPE_NESTED_WIDTH") | not)' >/dev/null && echo "B PASS: set options emit, unset stay absent" || { echo "B FAIL: $sv"; exit 1; }

ed=$(check '.defaults.ed')
[ "$ed" = 'STROM_STATE_HOME=/home/tester/.local/state/strom' ] && echo "C PASS: environment.d exact" || { echo "C FAIL: $ed"; exit 1; }

ed=$(check '.full.ed')
echo "$ed" | grep -q '^STROM_GAMESCOPE_FULLSCREEN=1$' && echo "C2 PASS: full environment.d carries fullscreen" || { echo "C2 FAIL: $ed"; exit 1; }

sv=$(check '.stateHomeNull.vars')
[ "$sv" = '{}' ] && echo "D PASS: stateHome null emits nothing" || { echo "D FAIL: $sv"; exit 1; }
echo "=== ALL ASSERTS PASS ==="
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash test/hm-module-fixture.sh`
Expected: eval error — `home-manager/strom.nix` does not exist.

- [ ] **Step 3: Implement the module**

Create `home-manager/strom.nix`:

```nix
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
    // (lib.optionalAttrs (cfg.gamescope.outputWidth != null) { STROM_GAMESCOPE_OUTPUT_WIDTH = toString cfg.gamescope.outputWidth; })
    // (lib.optionalAttrs (cfg.gamescope.outputHeight != null) { STROM_GAMESCOPE_OUTPUT_HEIGHT = toString cfg.gamescope.outputHeight; })
    // (lib.optionalAttrs (cfg.gamescope.nestedWidth != null) { STROM_GAMESCOPE_NESTED_WIDTH = toString cfg.gamescope.nestedWidth; })
    // (lib.optionalAttrs (cfg.gamescope.nestedHeight != null) { STROM_GAMESCOPE_NESTED_HEIGHT = toString cfg.gamescope.nestedHeight; })
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
```

- [ ] **Step 4: Export from the flake**

In `flake.nix`, directly after the `nixosModules = { ... };` block:

```nix
      homeManagerModules = {
        strom = import ./home-manager/strom.nix;
        default = self.homeManagerModules.strom;
      };
```

- [ ] **Step 5: Run the fixture to verify it passes**

Run: `bash test/hm-module-fixture.sh`
Expected: `A PASS` … `D PASS`, `=== ALL ASSERTS PASS ===`.
Also run: `nix flake check --no-build` or `nix eval .#homeManagerModules.strom` to confirm the export evaluates.

- [ ] **Step 6: Commit**

```bash
git add home-manager/strom.nix flake.nix test/hm-module-fixture.sh
git -c commit.gpgsign=false commit -m "hm: programs.strom module for per-user gamescope prefs and state home"
```

---

### Task 3: ownership pointer and consumption docs

**Files:**
- Modify: `nixos/desktop-module.nix` (`stateDir` description only, ~:61-76)
- Modify: `README.md` (consumption section near the overlay docs)

**Interfaces:**
- Consumes: Task 2's `homeManagerModules.strom` export.
- Produces: documentation; no code change.

- [ ] **Step 1: Add the ownership pointer**

In `nixos/desktop-module.nix`'s `stateDir` description, append one sentence after the existing prose (no logic change — the option is already `nullOr` with conditional consumers):

```
For per-user state owned by home-manager instead, leave this null and
set `programs.strom.stateHome` via the flake's `homeManagerModules.strom`;
exactly one side may own STROM_STATE_HOME.
```

- [ ] **Step 2: Add the README section**

After the overlay consumption section, add:

```markdown
## Per-user configuration via home-manager

Import the module and set preferences per user; unset options keep
recipe pins, and changes apply at next login (the values travel through
`environment.d`, the same login boundary the NixOS modules use).

```nix
# in the home configuration, with strom's flake in inputs:
imports = [ inputs.strom.homeManagerModules.strom ];
programs.strom = {
  enable = true;
  gamescope.outputWidth = 3440;
  gamescope.outputHeight = 1440;
  # stateHome defaults to ~/.local/state/strom; leave the NixOS
  # desktop module's stateDir null — exactly one side may own
  # STROM_STATE_HOME.
};
```
```

- [ ] **Step 3: Verify**

Run: `nix eval .#nixosModules.strom-desktop` (description-only change must still evaluate) and `bash test/hm-module-fixture.sh` (still green).
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add nixos/desktop-module.nix README.md
git -c commit.gpgsign=false commit -m "docs: consuming the home-manager module; stateDir ownership pointer"
```

---

## After implementation

Both branches carry to `develop` (fast-forward each; disjoint files), then the live rung runs on the operator machine: wire the HM module in the plan repo, re-login, `systemctl --user show-environment` shows the vars, a seat-launched game resolves them, exactly one of system/HM owns `STROM_STATE_HOME`. Landing then follows the contribution pipeline: two patches on plain `rad/master` bases (trial-cherry-pick evidence rule per `docs/notes/contributing/contribution-workflow.md`), draft-first magic-ref, node-log propagation, ledger rows.
