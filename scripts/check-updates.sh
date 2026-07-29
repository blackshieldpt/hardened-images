#!/usr/bin/env bash
# Report from-source images whose pinned version has fallen behind upstream.
#
# The daily relock keeps apk-based images current automatically, but images built
# from source (or repackaged from an upstream artifact) carry a hardcoded
# package.version in their melange.yaml that nothing checks. Every one of them had
# drifted — manticore by three major lines — before this existed.
#
# This only *detects* drift. It deliberately does not open bump PRs: each image
# pins a different artifact (a deb filename plus sha256, a tgz sha256, a git
# expected-commit, sometimes a build-id in the filename), so an automated bump
# would have to fetch and hash per-image and would be far more fragile than the
# thing it is protecting. A human bumps; this makes sure they know to.
#
# Exit codes are distinct on purpose: "something is behind" and "this script
# broke" must not look alike to CI. Filing a half-finished table as an
# authoritative drift report is worse than filing nothing.
#   0   every image current
#   10  at least one image behind
#   1   a per-image check failed (query error, or nothing matched the filter)
#   2   usage/tooling error
#
# Note there is no `-e`: a per-image failure is reported and the loop continues,
# rather than aborting the run partway through and leaving the rest unchecked.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

command -v gh >/dev/null || { echo "ERROR: gh not found (needed to query upstream tags)" >&2; exit 2; }

BEHIND=0
FOUND=0
ERRORS=0

# --porcelain emits tab-separated rows for the workflow to consume, so it never
# has to parse the aligned table (whose column widths are cosmetic).
PORCELAIN=0
[ "${1:-}" = "--porcelain" ] && PORCELAIN=1

row() {
    if [ "$PORCELAIN" = 1 ]; then
        printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
    else
        printf '%-12s %-16s %-16s %s\n' "$1" "$2" "$3" "$4"
    fi
}

[ "$PORCELAIN" = 1 ] || { row IMAGE PINNED LATEST STATUS; row ------ ------ ------ ------; }

for mel in images/*/melange.yaml; do
    image="$(basename "$(dirname "$mel")")"
    # The same test common.sh uses to decide a version comes from melange rather
    # than config.env — one definition of "is this a from-source image".
    grep -qE '^    identifier:' "$mel" || continue

    # package.version is the first `  version:` because package: is the first
    # block; the update block's keys sit deeper, so anchor each to its own indent
    # instead of taking the first match at any depth.
    pinned="$(sed -nE 's/^  version:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p'   "$mel" | head -1)"
    ident="$(sed -nE  's/^    identifier:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' "$mel" | head -1)"
    filter="$(sed -nE 's/^    tag-filter:[[:space:]]*"?([^"]*)"?.*/\1/p'      "$mel" | head -1)"
    sprefix="$(sed -nE 's/^    strip-prefix:[[:space:]]*"?([^"]*)"?.*/\1/p'   "$mel" | head -1)"
    ssuffix="$(sed -nE 's/^    strip-suffix:[[:space:]]*"?([^"]*)"?.*/\1/p'   "$mel" | head -1)"
    FOUND=$((FOUND + 1))

    if [ -z "$pinned" ] || [ -z "$ident" ]; then
        row "$image" "${pinned:-?}" "?" "UNPARSEABLE ($mel)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Tags rather than releases: several of these projects tag without publishing
    # a GitHub release. A partially-fetched page set would look like a short tag
    # list and could silently report "current", so a failed query is an error,
    # never a result.
    if ! tags="$(gh api "repos/${ident}/tags" --paginate -q '.[].name' 2>/dev/null)"; then
        row "$image" "$pinned" "?" "QUERY FAILED (${ident})"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Filter, strip, then keep only bare numeric versions. That last step rejects
    # every decorated tag — -rc1, -lts, -testing, -preview, -M1, -new — without
    # maintaining a blocklist of suffixes to guess at. It matters because `sort -V`
    # ranks `X-lts` ABOVE bare `X`, so a single leaked suffix silently becomes
    # "latest" while naming something the melange strip-suffix cannot produce.
    # Each grep is `|| true`: finding nothing is an outcome to report, not a crash.
    candidates="$(printf '%s\n' "$tags" \
        | { if [ -n "$filter" ]; then grep -F -- "$filter" || true; else cat; fi } \
        | sed -E "s/^${sprefix}//; s/${ssuffix}\$//" \
        | grep -E '^[0-9][0-9.]*$' || true)"

    latest="$(printf '%s\n' "$candidates" | grep -v '^$' | sort -V | tail -1)"

    if [ -z "$latest" ]; then
        # Nearly always a tag-filter or strip-suffix that no longer matches reality
        # — e.g. a quarterly clickhouse line bump that left tag-filter behind.
        row "$image" "$pinned" "?" "NO MATCHING TAG (check tag-filter/strip-suffix)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if [ "$pinned" = "$latest" ]; then
        row "$image" "$pinned" "$latest" "current"
    elif [ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)" = "$pinned" ]; then
        row "$image" "$pinned" "$latest" "ahead (check tag-filter)"
    else
        row "$image" "$pinned" "$latest" "BEHIND"
        BEHIND=$((BEHIND + 1))
    fi
done

## ---------------------------------------------------------------------------
## apk-native and config-only images: the VERSION_<name> pin in config.env names
## a Wolfi *version line* (valkey-8.1, kafka-4.2, python-3.14 ...). The daily
## relock moves patches within a line but never moves the line itself, so nothing
## noticed valkey sitting on a line Wolfi had not rebuilt in 298 days while
## valkey-9.1 was a week old. That is the same rot as the from-source pins, one
## level up.
##
## A line pin is often deliberate — `node` exists to track 22 and `node24` to
## track 24, so "newer line available" is not drift for them. Mark those in
## config.env with a trailing `# pinned-line` and they are reported as pinned
## rather than behind.

APKINDEX_CACHE="${TMPDIR:-/tmp}/wolfi-apkindex-$$"
cleanup() { rm -rf "$APKINDEX_CACHE"; }
trap cleanup EXIT

fetch_apkindex() {
    mkdir -p "$APKINDEX_CACHE" || return 1
    curl -sSfL --retry 5 --retry-all-errors --retry-delay 3 --max-time 180 \
        -o "${APKINDEX_CACHE}/APKINDEX.tar.gz" \
        https://packages.wolfi.dev/os/x86_64/APKINDEX.tar.gz || return 1
    tar xzf "${APKINDEX_CACHE}/APKINDEX.tar.gz" -C "$APKINDEX_CACHE" APKINDEX || return 1
}

[ "$PORCELAIN" = 1 ] || { echo; row IMAGE PINNED LATEST STATUS; row ------ ------ ------ ------; }

if ! fetch_apkindex; then
    echo "ERROR: could not fetch the Wolfi package index — apk-native images unchecked" >&2
    ERRORS=$((ERRORS + 1))
else
    # Every package name in the index, once.
    sed -n 's/^P://p' "${APKINDEX_CACHE}/APKINDEX" | sort -u > "${APKINDEX_CACHE}/names"

    while IFS= read -r line; do
        case "$line" in VERSION_*) ;; *) continue ;; esac
        var="${line%%=*}"
        rest="${line#*=}"
        pinned="${rest%%#*}"; pinned="$(printf '%s' "$pinned" | tr -d '[:space:]')"
        image="$(printf '%s' "${var#VERSION_}" | tr '_' '-')"
        [ -d "images/${image}" ] || continue
        FOUND=$((FOUND + 1))

        case "$rest" in *"# pinned-line"*) row "$image" "$pinned" "-" "pinned line (deliberate)"; continue ;; esac

        # Find the Wolfi package families this image installs that carry the pin
        # in their name, then look for a higher line of the same family.
        apko="images/${image}/apko/${image}.yaml"
        [ -f "$apko" ] || { row "$image" "$pinned" "-" "no apko config"; continue; }
        fam="$(sed -nE 's/^[[:space:]]+- ([a-z0-9]([a-z0-9._+-]*[a-z0-9])?)$/\1/p' "$apko" \
               | grep -F -- "-${pinned}" | head -1)"
        if [ -z "$fam" ]; then
            # Exact-version pins (minio) and unversioned packages (nats-server):
            # the relock already tracks these, there is no separate line to move.
            row "$image" "$pinned" "-" "no versioned family (relock covers it)"
            continue
        fi
        base="${fam%-"$pinned"}"
        newest="$(grep -E "^${base}-[0-9][0-9.]*$" "${APKINDEX_CACHE}/names" \
                  | sed -E "s/^${base}-//" | sort -V | tail -1)"
        if [ -z "$newest" ]; then
            row "$image" "$pinned" "?" "NO MATCHING FAMILY (${base}-*)"
            ERRORS=$((ERRORS + 1))
        elif [ "$newest" = "$pinned" ]; then
            row "$image" "$pinned" "$newest" "current (${base})"
        elif [ "$(printf '%s\n%s\n' "$pinned" "$newest" | sort -V | tail -1)" = "$pinned" ]; then
            row "$image" "$pinned" "$newest" "ahead (${base})"
        else
            row "$image" "$pinned" "$newest" "BEHIND (${base}-${newest} available)"
            BEHIND=$((BEHIND + 1))
        fi
    done < config.env
fi

if [ "$PORCELAIN" = 0 ]; then
    echo
    echo "Checked ${FOUND} image(s); ${BEHIND} behind upstream; ${ERRORS} could not be checked."
fi

[ "$ERRORS" -eq 0 ] || exit 1
[ "$BEHIND" -eq 0 ] || exit 10
exit 0
