# Closure assertion for the out-of-store dataArchive mode
# (docs/notes/design/2026-11-15-out-of-store-game-data.md).
#
# Instantiates a minimal synthetic dataArchive game through the real
# mkGame lib, builds its wrapper, and proves the two properties the
# mode exists for:
#
#   1. No path in the wrapper's closure carries game bytes: nothing
#      named like the curated archive (what a fetchIpfs FOD of it would
#      be called) and no `<name>-data` extraction tree (what mkGame's
#      store-mode _gameData derivation would be called). The closure is
#      taken via exportReferencesGraph, so the assertion holds inside
#      the sandbox with no store-database access.
#
#   2. The wrapper actually runs in the mode: the host-side materializer
#      fragment (lib/data-materializer.sh) with its .strom-data/<sha256
#      prefix> destination is in the wrapper script text, and the
#      overlay's base lower is the state-dir literal (asserted at
#      evaluation time on the module config -- the inner mount script
#      interpolates that exact list into its lowerdir=).
#
# The fixture declares no fetchIpfs source at all, so building it can
# never realize game bytes -- if a future regression reintroduces a
# store-path dependency, assertion 1 names the offending path.
{
  lib,
  pkgs,
  mkGame,
}:
let
  # Synthetic but valid: 64 hex chars, first 12 name the state dir.
  sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  dataDir = lib.substring 0 12 sha256;
  game = mkGame {
    name = "data-archive-fixture";
    dataArchive = {
      cid = "bafybeifixturesyntheticoutofstorearchivecid";
      inherit sha256;
      size = 1234567890;
      fileName = "fixture-repack.zip";
      rootFolder = "Fixture Game";
    };
    runtime = "custom";
    executable = "game.exe";
    meta = {
      description = "closure-assertion fixture for the dataArchive mode";
      platforms = [ "x86_64-linux" ];
    };
  };
  expectedLower = "$STROM_GAMEDIR/.strom-data/${dataDir}";
  lowerOk = builtins.elem expectedLower game.bwrap.overlay.lowers;
  fixture = game.outputs.wrapper;
in
lib.throwIfNot lowerOk
  "data-archive-closure: overlay.lowers does not carry the base lower ${expectedLower}"
  (
    pkgs.runCommand "data-archive-closure-check"
      {
        exportReferencesGraph = [
          "closure"
          fixture
        ];
      }
      ''
        fail() {
          echo "data-archive-closure: FAIL: $*" >&2
          exit 1
        }

        # exportReferencesGraph drops the file at ./closure in the build dir.
        [ -s ./closure ] || fail "empty closure graph"

        # 1. No game bytes in the closure.
        if grep -nE 'fixture-repack|data-archive-fixture-data' ./closure; then
          fail "wrapper closure contains game-byte paths (archive FOD or extraction tree)"
        fi

        # 2. Host side: the materializer fragment and its .strom-data
        # destination are in the wrapper script text.
        grep -qF 'STROM_DATAMAT_FILENAME=' ${fixture}/bin/data-archive-fixture \
          || fail "wrapper script lacks the materializer fragment"
        grep -qF '.strom-data/${dataDir}' ${fixture}/bin/data-archive-fixture \
          || fail "wrapper script lacks the .strom-data destination"

        echo "data-archive-closure: no game bytes in the wrapper closure; .strom-data/${dataDir} lower wired" >&2
        touch "$out"
      ''
  )
