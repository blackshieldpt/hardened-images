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

row() { printf '%-12s %-16s %-16s %s\n' "$1" "$2" "$3" "$4"; }

row IMAGE PINNED LATEST STATUS
row ------ ------ ------ ------

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

echo
echo "Checked ${FOUND} from-source image(s); ${BEHIND} behind upstream; ${ERRORS} could not be checked."

[ "$ERRORS" -eq 0 ] || exit 1
[ "$BEHIND" -eq 0 ] || exit 10
exit 0
