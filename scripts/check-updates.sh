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
# Exit 1 when any image is behind, so CI can act on it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

command -v gh >/dev/null || { echo "ERROR: gh not found" >&2; exit 2; }

_scalar() {  # <file> <indent-2 key under update.github or package> -> value
    sed -nE "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -1 | tr -d '"'"'"''
}

BEHIND=0
FOUND=0

printf '%-12s %-16s %-16s %s\n' IMAGE PINNED LATEST STATUS
printf '%-12s %-16s %-16s %s\n' ------ ------ ------ ------

for mel in images/*/melange.yaml; do
    image="$(basename "$(dirname "$mel")")"
    grep -qE '^[[:space:]]+identifier:' "$mel" || continue   # config-only images

    pinned="$(grep -m1 -E '^  version:' "$mel" | sed -E 's/^  version:[[:space:]]*//; s/"//g')"
    ident="$(_scalar "$mel" identifier)"
    filter="$(_scalar "$mel" 'tag-filter')"
    sprefix="$(_scalar "$mel" 'strip-prefix')"
    ssuffix="$(_scalar "$mel" 'strip-suffix')"
    FOUND=$((FOUND + 1))

    # Tags rather than releases: several of these projects tag without publishing
    # a GitHub release, and melange's use-tag reflects that.
    tags="$(gh api "repos/${ident}/tags" --paginate --jq '.[].name' 2>/dev/null || true)"
    if [ -z "$tags" ]; then
        printf '%-12s %-16s %-16s %s\n' "$image" "$pinned" "?" "QUERY FAILED"
        continue
    fi

    latest="$(printf '%s\n' "$tags" \
        | { [ -n "$filter" ] && grep -F -- "$filter" || cat; } \
        | grep -viE '(rc|alpha|beta|dev|new|nightly|pre)[0-9.]*$' \
        | sed -E "s/^${sprefix}//; s/${ssuffix}\$//" \
        | grep -E '^[0-9]' \
        | sort -V | tail -1)"

    if [ -z "$latest" ]; then
        printf '%-12s %-16s %-16s %s\n' "$image" "$pinned" "?" "NO MATCHING TAG"
        continue
    fi

    if [ "$pinned" = "$latest" ]; then
        printf '%-12s %-16s %-16s %s\n' "$image" "$pinned" "$latest" "current"
    elif [ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)" = "$pinned" ]; then
        # Pinned is ahead of anything upstream matches — usually a stale tag-filter.
        printf '%-12s %-16s %-16s %s\n' "$image" "$pinned" "$latest" "ahead (check tag-filter)"
    else
        printf '%-12s %-16s %-16s %s\n' "$image" "$pinned" "$latest" "BEHIND"
        BEHIND=$((BEHIND + 1))
    fi
done

echo
echo "Checked ${FOUND} from-source image(s); ${BEHIND} behind upstream."
[ "$BEHIND" -eq 0 ]
