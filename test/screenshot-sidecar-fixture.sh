#!/usr/bin/env bash
# Fixture for the screenshot sidecar's gamescope lock discovery (no real
# gamescope, no bwrap). Sources lib/screenshot-sidecar.sh exactly as the
# gamescope wrapper inlines it (readFile in lib/gamescope.nix), against a
# fake private XDG_RUNTIME_DIR, and asserts:
#   A  selection: gamescope-0.lock wins over gamescope-0-ei.lock (which
#      glob order visits FIRST: '-' sorts before '.') and
#      gamescope-limiter-* never matches the glob at all.
#   B  readiness: a lock with no socket yet produces no marker until the
#      socket file appears; the marker then carries the FULL socket path,
#      not the bare name.
#   C  exhaustion: an empty runtime dir burns the whole 900-poll budget,
#      logs "no gamescope lock found within 90s", writes no marker.
#   D  teardown: a session shorter than discovery (wrapper exits ~1 s
#      in, no lock ever created) leaves a start-only log, no marker, and
#      no surviving subshell — the EXIT trap and the parent-liveness
#      abort are both on this path.
# Headless. Runtime is dominated by C's 90 s poll budget.
set -euo pipefail

say() { printf '\n=== %s ===\n' "$*"; }
fail() {
	printf 'FIXTURE FAIL: %s\n' "$*" >&2
	exit 1
}

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

SIDECAR="$here/lib/screenshot-sidecar.sh"
[ -f "$SIDECAR" ] || fail "missing lib/screenshot-sidecar.sh"
PYTHON=$(nix build nixpkgs#python3 --no-link --print-out-paths)/bin/python3

WORK=$(mktemp -d -t strom-sidecar-fixture.XXXXXX)
cleanup() {
	jobs -p | xargs -r kill -TERM 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

mksock() {
	"$PYTHON" -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"
}

# write_inner <name> <xdg> <gamedir> <tail...>: a stand-in for the gamescope
# wrapper — sources the sidecar fragment with the same env contract
# (XDG_RUNTIME_DIR + STROM_GAMEDIR exported before sourcing).
write_inner() {
	local name=$1 xdg=$2 gamedir=$3 tail=$4
	cat >"$WORK/inner-$name.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export XDG_RUNTIME_DIR="$xdg"
export STROM_GAMEDIR="$gamedir"
source "$SIDECAR"
$tail
EOF
	chmod +x "$WORK/inner-$name.sh"
}

wait_for_content() { # wait_for_content <file> <pattern> <seconds>
	local _i
	for _i in $(seq 1 "$((10 * $3))"); do
		grep -q "$2" "$1" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

wait_nonempty() { # wait_nonempty <file> <seconds>
	local _i
	for _i in $(seq 1 "$((10 * $2))"); do
		[ -s "$1" ] && return 0
		sleep 0.1
	done
	return 1
}

# --- A: lock selection -------------------------------------------------------
say "A: gamescope-0.lock selected; -ei excluded; limiter ignored"
XDG="$WORK/xdg-a"
GAMEDIR="$WORK/game-a"
mkdir -p "$XDG" "$GAMEDIR"
touch "$XDG/gamescope-0.lock" "$XDG/gamescope-0-ei.lock" "$XDG/gamescope-limiter-x"
mksock "$XDG/gamescope-0"
write_inner a "$XDG" "$GAMEDIR" 'wait; echo INNER_DONE'
"$WORK/inner-a.sh" >"$WORK/a.out" 2>"$WORK/a.err" &
wait_for_content "$WORK/a.out" INNER_DONE 15 || { cat "$WORK/a.err" >&2; fail "A: inner did not finish"; }
[ "$(head -n1 "$GAMEDIR/.strom-wayland-display")" = "$XDG/gamescope-0" ] \
	|| fail "A: marker is '$(head -n1 "$GAMEDIR/.strom-wayland-display")', want $XDG/gamescope-0"
grep -q 'detected socket=gamescope-0 after [0-9]* polls' "$GAMEDIR/screenshots/.sidecar.log" \
	|| fail "A: detected log line missing"
echo "A PASS: marker=$XDG/gamescope-0 ($(grep -o 'detected socket=[^ ]* after [0-9]* polls' "$GAMEDIR/screenshots/.sidecar.log"))"

# --- B: lock before socket -> readiness wait ---------------------------------
say "B: marker withheld until the socket exists, then full path"
XDG="$WORK/xdg-b"
GAMEDIR="$WORK/game-b"
mkdir -p "$XDG" "$GAMEDIR"
touch "$XDG/gamescope-0.lock"
write_inner b "$XDG" "$GAMEDIR" 'wait; echo INNER_DONE'
"$WORK/inner-b.sh" >"$WORK/b.out" 2>"$WORK/b.err" &
sleep 1
[ ! -e "$GAMEDIR/.strom-wayland-display" ] || fail "B: marker written before socket existed"
mksock "$XDG/gamescope-0"
wait_nonempty "$GAMEDIR/.strom-wayland-display" 10 || fail "B: no marker after socket appeared"
wait_for_content "$WORK/b.out" INNER_DONE 10 || { cat "$WORK/b.err" >&2; fail "B: inner did not finish"; }
[ "$(head -n1 "$GAMEDIR/.strom-wayland-display")" = "$XDG/gamescope-0" ] \
	|| fail "B: marker is not the full socket path"
echo "B PASS: marker withheld pre-socket, then $(head -n1 "$GAMEDIR/.strom-wayland-display")"

# --- C: exhaustion -----------------------------------------------------------
say "C: empty runtime dir exhausts the poll budget (takes ~90 s)"
XDG="$WORK/xdg-c"
GAMEDIR="$WORK/game-c"
mkdir -p "$XDG" "$GAMEDIR"
write_inner c "$XDG" "$GAMEDIR" 'wait; echo INNER_DONE'
"$WORK/inner-c.sh" >"$WORK/c.out" 2>"$WORK/c.err" &
wait_for_content "$WORK/c.out" INNER_DONE 150 || { cat "$WORK/c.err" >&2; fail "C: inner did not finish"; }
grep -qx '\[sidecar\] no gamescope lock found within 90s' "$GAMEDIR/screenshots/.sidecar.log" \
	|| fail "C: exhaustion log line missing"
grep -q 'strom-screenshot: no gamescope socket found within 90s' "$WORK/c.err" \
	|| fail "C: exhaustion stderr line missing"
[ ! -e "$GAMEDIR/.strom-wayland-display" ] || fail "C: marker written despite no lock"
echo "C PASS: exhausted after 900 polls, no marker ($(grep -o 'after .*' "$GAMEDIR/screenshots/.sidecar.log" || echo budget))"

# --- D: short session -> wrapper exits, trap kills the discovery subshell ----
say "D: wrapper exits mid-discovery; start-only shape, no survivor"
# The wrapper's foreground command (gamescope) ends, the script exits, and
# the sidecar's EXIT trap TERMs the still-discovering subshell. (TERM to a
# wrapper BLOCKED in its foreground child would defer the trap until the
# child ends — not a production path: teardown SIGKILLs the namespace.)
XDG="$WORK/xdg-d"
GAMEDIR="$WORK/game-d"
mkdir -p "$XDG" "$GAMEDIR"
write_inner d "$XDG" "$GAMEDIR" 'sleep 1'
"$WORK/inner-d.sh" >"$WORK/d.out" 2>"$WORK/d.err" &
DPID=$!
wait "$DPID" 2>/dev/null || true
sleep 1
if pgrep -f "$WORK/inner-d.sh" >/dev/null; then
	fail "D: sidecar subshell survived wrapper exit"
fi
grep -q '\[sidecar\] start ' "$GAMEDIR/screenshots/.sidecar.log" \
	|| fail "D: start log line missing"
grep -q 'detected socket=' "$GAMEDIR/screenshots/.sidecar.log" \
	&& fail "D: detected line present despite teardown"
[ ! -e "$GAMEDIR/.strom-wayland-display" ] || fail "D: marker written despite teardown"
echo "D PASS: start-only log shape, no survivor, no marker"

say "ALL ASSERTS PASS (A, B, C, D)"
