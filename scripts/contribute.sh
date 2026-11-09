#!/usr/bin/env bash
# Local-only maintenance helper for this machine's radicle contribution flow.
# It lives on develop (the consumption branch) and must never be cherry-picked
# into a rad patch or stage branch: upstream does not use it.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RAD_HOME=${RAD_HOME:-$REPO_ROOT/.radicle}
export RAD_HOME

# rad 1.9.1 has no `rad patch list --json`, so open patches map to their
# branches in this table. Keep it current when a patch is opened, merged,
# or archived. Format: "<patch-id> <branch>".
PATCH_BRANCHES=(
    "435defb feat-gamescope-size-env"
    "99a8f6c docs-lsteamclient-emu-rule"
    "f5e13f7 feat/mirror-gateway-port"
    "3f2c2fa feat/state-dir"
    "8bf6056 docs-upstream-findings"
    "120e63d fix/mk-game-vulkan-icd"
    "e203536 no-gamescope-launch"
    "a068478 overlay-expose"
    "735c360 system-deprecation"
)

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  contribute.sh preflight
  contribute.sh sync [--dry-run] <patch-id> <base>..<tip>

preflight  Fetch rad, fast-forward local master, and report which stage/*
           branches and rad-patch branches are stale against master.
sync       Cherry-pick the commits of <base>..<tip> that the patch branch
           does not already carry (patch-id comparison) onto that branch
           inside its worktree, then force-push to rad, update the patch,
           and sync. --dry-run stops after showing the cherry-pick plan.
EOF
}

cmd_preflight() {
    git fetch rad
    git fetch rad master:master

    local branches=()
    mapfile -t branches < <(git for-each-ref --format='%(refname:short)' 'refs/heads/stage/')
    local entry
    for entry in "${PATCH_BRANCHES[@]}"; do
        branches+=("${entry#* }")
    done

    local b count stale=0
    for b in ${branches[@]+"${branches[@]}"}; do
        count=$(git rev-list --count "${b}..master")
        if [ "$count" -gt 0 ]; then
            stale=$((stale + 1))
            printf 'STALE  %-28s %s commit(s) on master missing from branch\n' "$b" "$count"
            git log --format='       %h %s' "${b}..master"
        else
            printf 'ok     %s\n' "$b"
        fi
    done

    local id rad_head
    for entry in "${PATCH_BRANCHES[@]}"; do
        id=${entry%% *}
        b=${entry#* }
        rad_head=$(rad patch show "$id" | sed -n 's/.*Head *\([0-9a-f]\{40\}\).*/\1/p' | head -n1)
        if [ -n "$rad_head" ] && ! git merge-base --is-ancestor "$rad_head" "$b" 2>/dev/null; then
            printf 'WARN   %-28s rad patch %s head %s is not an ancestor of the local tip\n' \
                "$b" "$id" "${rad_head:0:7}"
        fi
    done

    echo
    echo "stale branches: $stale"
}

cmd_sync() {
    local dry_run=false
    local args=()
    local a
    for a in "$@"; do
        case "$a" in
            --dry-run) dry_run=true ;;
            -*) die "unknown option: $a" ;;
            *) args+=("$a") ;;
        esac
    done
    [ "${#args[@]}" -eq 2 ] || {
        usage >&2
        exit 2
    }
    local patch_id=${args[0]} range=${args[1]}

    local branch='' entry
    for entry in "${PATCH_BRANCHES[@]}"; do
        if [ "${entry%% *}" = "$patch_id" ]; then
            branch=${entry#* }
        fi
    done
    [ -n "$branch" ] || die "patch ${patch_id} is not in the PATCH_BRANCHES table"

    local worktree
    worktree=$(git worktree list --porcelain | awk -v b="refs/heads/${branch}" '
        /^worktree / { wt = substr($0, 10) }
        /^branch / { if ($2 == b) print wt }')
    [ -n "$worktree" ] || die "no worktree found with ${branch} checked out"

    [ -z "$(git -C "$worktree" status --short)" ] || die "${worktree} has uncommitted changes"

    local tip=$range
    case "$range" in
        *..*) tip=${range##*..} ;;
    esac
    git rev-parse --verify --quiet "${tip}^{commit}" >/dev/null ||
        die "cannot resolve range ${range}"

    local -A carried=()
    local c
    while read -r c; do
        carried[$c]=1
    done < <(git cherry "$branch" "$tip" | awk '$1 == "-" { print $2 }')

    local missing=()
    while read -r c; do
        [ -n "${carried[$c]:-}" ] || missing+=("$c")
    done < <(git rev-list --reverse "$range")

    echo "patch   ${patch_id} (${branch})"
    echo "target  ${worktree}"
    if [ "${#missing[@]}" -eq 0 ]; then
        echo "nothing to sync: ${branch} already carries every commit in ${range} (patch-id match)"
        exit 0
    fi
    echo "commits to cherry-pick:"
    git log --no-walk=unsorted --oneline "${missing[@]}"

    if [ "$dry_run" = true ]; then
        echo "dry run: stopping before cherry-pick"
        exit 0
    fi

    local old_tip
    old_tip=$(git rev-parse "${branch}")

    if ! git -C "$worktree" -c commit.gpgsign=false cherry-pick "${missing[@]}"; then
        die "cherry-pick failed: resolve in ${worktree} (or 'git cherry-pick --abort' there), then rerun sync with the remaining range"
    fi

    local new_tip
    new_tip=$(git rev-parse "${branch}")

    if ! (cd "$worktree" &&
        PRE_COMMIT_FROM_REF="$old_tip" PRE_COMMIT_TO_REF="$new_tip" \
            bash "$REPO_ROOT/scripts/check-no-signed-commits.sh"); then
        die "signed commits landed in ${old_tip:0:7}..${new_tip:0:7}; redo them unsigned"
    fi

    # rad's transport rejects a plain --force while push.useForceIfIncludes is
    # enabled (it is, globally, on this machine), so the check is disabled
    # per-invocation. This is the known-good force-push path for rad.
    git -c push.useForceIfIncludes=false push --force rad "$branch"

    # rad 1.9.1 `patch update` derives the new head from the working copy, so
    # it must run where the patch branch is checked out.
    (cd "$worktree" && rad patch update "$patch_id" -m "sync from develop: ${range}")

    local sync_status=ok
    if ! rad sync; then
        sync_status='failed (often announce-accounting noise; check the node log for "fetched ... from us")'
    fi

    echo
    echo "summary"
    echo "  branch    ${branch} ${old_tip:0:7} -> ${new_tip:0:7}"
    rad patch show "$patch_id" | grep 'Revision' | tail -n1 || true
    echo "  rad sync  ${sync_status}"
}

case "${1:-}" in
    preflight) shift && cmd_preflight "$@" ;;
    sync) shift && cmd_sync "$@" ;;
    -h | --help | help) usage ;;
    *)
        usage >&2
        exit 2
        ;;
esac
