# shellcheck shell=bash
# strom data materializer - sourced into bwrap.preHook when the game's
# dataArchive is set (lib/mk-game.nix). Materializes the out-of-store
# game archive into the state dir before bwrap starts, so the inner
# overlay mount (whose base lower is the .strom-data literal) finds its
# lowest lower present.
#
# Inputs (set in the surrounding scope before this fragment runs):
#   STROM_DATAMAT_NAME        - game name, for log lines
#   STROM_DATAMAT_7ZZ         - store path of the 7zz binary
#   STROM_DATAMAT_CURL        - store path of curl
#   STROM_DATAMAT_CID         - content ID of the curated archive
#   STROM_DATAMAT_SHA256      - expected sha256 (hex) of the archive
#   STROM_DATAMAT_SIZE        - archive size in bytes (advisory)
#   STROM_DATAMAT_FILENAME    - curated archive file name
#   STROM_DATAMAT_ROOTFOLDER  - the archive's single root folder
#   STROM_DATAMAT_DEST        - final materialized dir
#   STROM_GAMEDIR             - per-game state dir (already created)
#
# Environment (operator-tunable, defaulted here):
#   STROM_ARCHIVES       - static archive directory
#                          (default /var/lib/steam/game-archives)
#   STROM_IPFS_GATEWAYS  - local gateway URLs, comma- or space-separated
#                          (default http://127.0.0.1:8330)
#
# Resolution order: $STROM_ARCHIVES/<fileName> first (presence selects
# the source), then $gateway/ipfs/<cid> for each gateway in turn. Public
# gateways are never consulted: fetching these bytes from ipfs.io-class
# endpoints is the redistribution exposure the mode exists to avoid.
# The sha256 recorded in the flake is verified against the source bytes
# BEFORE any extraction; a mismatch is a hard failure naming the source
# and both hashes, and the static archive itself is never modified or
# removed. Extraction goes to .strom-data/.partial-<pid>/ and is
# renamed into place atomically, so the presence of the final dir is
# the completion marker; a deleted or corrupt state copy self-heals on
# the next launch. 7zz x preserves empty directory entries.

__strom_dm_materialize() {
    __strom_dm_src=""
    __strom_dm_downloaded=""
    __strom_dm_tried=""

    if [ -f "$STROM_ARCHIVES/$STROM_DATAMAT_FILENAME" ]; then
        __strom_dm_src="$STROM_ARCHIVES/$STROM_DATAMAT_FILENAME"
        __strom_dm_tried="$STROM_ARCHIVES/$STROM_DATAMAT_FILENAME (present, sha256 mismatch), "
        echo "strom-data[$STROM_DATAMAT_NAME]: source: static archive $__strom_dm_src" >&2
    else
        __strom_dm_tried="$STROM_ARCHIVES/$STROM_DATAMAT_FILENAME (absent), "
        mkdir -p "$STROM_GAMEDIR/.strom-data/.downloads"
        # shellcheck disable=SC2086 # the gateway list is deliberately word-split (comma- or space-separated)
        for __strom_dm_gw in $(printf '%s ' "$STROM_IPFS_GATEWAYS" | tr ',' ' '); do
            [ -n "$__strom_dm_gw" ] || continue
            __strom_dm_dl="$STROM_GAMEDIR/.strom-data/.downloads/$STROM_DATAMAT_FILENAME.$$"
            rm -f "$__strom_dm_dl"
            echo "strom-data[$STROM_DATAMAT_NAME]: source: gateway $__strom_dm_gw/ipfs/$STROM_DATAMAT_CID" >&2
            if ! "$STROM_DATAMAT_CURL" -fsSL --connect-timeout 10 --retry 3 -o "$__strom_dm_dl" "$__strom_dm_gw/ipfs/$STROM_DATAMAT_CID"; then
                echo "strom-data[$STROM_DATAMAT_NAME]: fetch from $__strom_dm_gw failed" >&2
                __strom_dm_tried="$__strom_dm_tried$__strom_dm_gw (fetch failed), "
                rm -f "$__strom_dm_dl"
                continue
            fi
            __strom_dm_actual=$(sha256sum "$__strom_dm_dl")
            __strom_dm_actual=${__strom_dm_actual%% *}
            if [ "$__strom_dm_actual" != "$STROM_DATAMAT_SHA256" ]; then
                echo "strom-data[$STROM_DATAMAT_NAME]: sha256 mismatch for gateway $__strom_dm_gw: expected $STROM_DATAMAT_SHA256, got $__strom_dm_actual; removed the partial download" >&2
                __strom_dm_tried="$__strom_dm_tried$__strom_dm_gw (sha256 mismatch), "
                rm -f "$__strom_dm_dl"
                continue
            fi
            __strom_dm_src="$__strom_dm_dl"
            __strom_dm_downloaded=1
            __strom_dm_tried="$__strom_dm_tried$__strom_dm_gw (sha256 verified), "
            break
        done
    fi

    if [ -z "$__strom_dm_src" ]; then
        echo "strom-data[$STROM_DATAMAT_NAME]: no source satisfied the fetch; tried: $__strom_dm_tried" >&2
        echo "strom-data[$STROM_DATAMAT_NAME]: wanted $STROM_DATAMAT_FILENAME (cid $STROM_DATAMAT_CID, sha256 $STROM_DATAMAT_SHA256)" >&2
        return 1
    fi

    # The static-archive source is verified here (gateway downloads were
    # verified per-gateway above so a corrupt one could be abandoned for
    # the next source). The static archive is never deleted on mismatch.
    if [ -z "$__strom_dm_downloaded" ]; then
        __strom_dm_actual=$(sha256sum "$__strom_dm_src")
        __strom_dm_actual=${__strom_dm_actual%% *}
        if [ "$__strom_dm_actual" != "$STROM_DATAMAT_SHA256" ]; then
            echo "strom-data[$STROM_DATAMAT_NAME]: sha256 mismatch for the static archive $__strom_dm_src: expected $STROM_DATAMAT_SHA256, got $__strom_dm_actual; refusing to extract (the static archive is never modified)" >&2
            return 1
        fi
    fi

    __strom_dm_partial="$STROM_GAMEDIR/.strom-data/.partial-$$"
    rm -rf "$__strom_dm_partial"
    mkdir -p "$__strom_dm_partial"
    echo "strom-data[$STROM_DATAMAT_NAME]: extracting $__strom_dm_src into $__strom_dm_partial (root folder '$STROM_DATAMAT_ROOTFOLDER' stripped on extract)" >&2
    if ! "$STROM_DATAMAT_7ZZ" x -y -o"$__strom_dm_partial" "$__strom_dm_src"; then
        echo "strom-data[$STROM_DATAMAT_NAME]: extraction failed" >&2
        rm -rf "$__strom_dm_partial"
        return 1
    fi
    if [ ! -d "$__strom_dm_partial/$STROM_DATAMAT_ROOTFOLDER" ]; then
        echo "strom-data[$STROM_DATAMAT_NAME]: archive layout drift: no root folder '$STROM_DATAMAT_ROOTFOLDER' at the archive root" >&2
        rm -rf "$__strom_dm_partial"
        return 1
    fi
    # rename(2) within .strom-data is atomic; the final dir's presence
    # is the completion marker.
    mv "$__strom_dm_partial/$STROM_DATAMAT_ROOTFOLDER" "$STROM_DATAMAT_DEST"
    rm -rf "$__strom_dm_partial"
    if [ -n "$__strom_dm_downloaded" ]; then
        rm -f "$__strom_dm_src"
        echo "strom-data[$STROM_DATAMAT_NAME]: deleted the downloaded archive copy (the static archive in $STROM_ARCHIVES is never modified)" >&2
    fi
    echo "strom-data[$STROM_DATAMAT_NAME]: materialized $STROM_DATAMAT_DEST" >&2
}

: "${STROM_ARCHIVES:=/var/lib/steam/game-archives}"
: "${STROM_IPFS_GATEWAYS:=http://127.0.0.1:8330}"

if [ -d "$STROM_DATAMAT_DEST" ]; then
    echo "strom-data[$STROM_DATAMAT_NAME]: $STROM_DATAMAT_DEST already materialized; fetch skipped" >&2
else
    # Advisory preflight: peak usage is the archive plus the extracted
    # tree, so warn when the state filesystem holds less than size +
    # 20 percent. size is an attestation convenience, not a promise, so
    # this never refuses the launch.
    __strom_dm_avail=$(df -B1 --output=avail "$STROM_GAMEDIR" | tail -n1)
    __strom_dm_need=$((STROM_DATAMAT_SIZE + STROM_DATAMAT_SIZE / 5))
    if [ "$__strom_dm_avail" -lt "$__strom_dm_need" ]; then
        echo "strom-data[$STROM_DATAMAT_NAME]: WARNING: only $__strom_dm_avail bytes free on the state filesystem, below the advisory need of $__strom_dm_need (archive $STROM_DATAMAT_SIZE bytes + 20 percent); extraction may fill the disk. Continuing (advisory check)." >&2
    fi

    mkdir -p "$STROM_GAMEDIR/.strom-data"
    # Blocking flock: a second launch during first-time extraction waits
    # here instead of erroring; the proton instance lock further down
    # preHook reserves failure for genuinely concurrent instances. The
    # fd is closed as soon as materialization is done, so the lock never
    # outlives this fragment.
    exec 8>"$STROM_GAMEDIR/.strom-data/.lock"
    flock 8
    if [ -d "$STROM_DATAMAT_DEST" ]; then
        echo "strom-data[$STROM_DATAMAT_NAME]: $STROM_DATAMAT_DEST materialized by a concurrent launch while this one waited" >&2
    else
        __strom_dm_materialize
    fi
    exec 8>&-
fi
