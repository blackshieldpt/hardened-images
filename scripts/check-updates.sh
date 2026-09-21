#!/usr/bin/env bash
# Report from-source images whose pinned version has fallen behind upstream.
#
# The daily relock keeps apk-based images current automatically, but images built
# from source (or repackaged from an upstream artifact) carry a hardcoded
# package.version in their melange.yaml that nothing checks. Every one of them had
# drifted — manticore by three major lines — before this existed.
#
# This script only *detects* drift. Opening the bump PR is the workflow's job
# (.github/workflows/check-updates.yml), and it only bumps what it can derive
# mechanically — the version pin, the lockfile, a git expected-commit. It cannot
# bump an image that pins a deb filename plus sha256 or a tgz sha256, because
# that needs a fetch-and-hash per image; those are listed for a human instead.
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
FROZEN=0

# A pinned package that is the newest of its family but has stopped being rebuilt
# does not look like drift, so nothing above catches it. Flag anything not rebuilt
# in this many days. Override in config.env or the environment.
STALE_AFTER_DAYS="${STALE_AFTER_DAYS:-45}"

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

fetch_secdb() {
    curl -sSfL --retry 5 --retry-all-errors --retry-delay 3 --max-time 180 \
        -o "${APKINDEX_CACHE}/security.json" https://packages.wolfi.dev/os/security.json
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

## ---------------------------------------------------------------------------
## Freeze detection. Everything above answers "is there a newer version?", which
## a frozen package passes: it IS the newest. That is how etcd-3.6, openbao,
## nginx-stable, kafka, zookeeper and the valkey-8.1 line all rotted while every
## check reported them current. Two signals catch it, both from data already
## fetched:
##
##   FROZEN        the pinned package has not been rebuilt in STALE_AFTER_DAYS.
##                 Rebuilds are how a Wolfi package picks up patched libraries, so
##                 a stale build is a stale dependency tree even at a current version.
##   UNOBTAINABLE  Wolfi's advisory data names a fixed version that does not exist
##                 in the index. That is worse than staleness: it means a fix for a
##                 known CVE has been identified and you cannot get it.
##
## Neither is drift, so neither produces a bump PR — there is nothing to bump to.
## They are reported so the decision (accept, VEX, or move off the package) is a
## choice rather than an oversight.

if [ -d "$APKINDEX_CACHE" ] && [ -f "${APKINDEX_CACHE}/APKINDEX" ]; then
    [ "$PORCELAIN" = 1 ] || { echo; row PACKAGE VERSION AGE STATUS; row ------- ------- --- ------; }

    # newest build per package: name, version, build timestamp
    awk -F: '/^P:/{p=$2} /^V:/{v=$2} /^t:/{if (p!="" && (!(p in t) || $2+0>t[p])) {t[p]=$2+0; ver[p]=v}}
             END{for (k in t) printf "%s\t%s\t%d\n", k, ver[k], t[k]}' \
        "${APKINDEX_CACHE}/APKINDEX" > "${APKINDEX_CACHE}/newest.tsv"
    awk -F: '/^P:/{p=$2} /^V:/{print p "\t" $2}' "${APKINDEX_CACHE}/APKINDEX" \
        | sort -u > "${APKINDEX_CACHE}/allvers.tsv"

    # Two different package sets, because the two signals have different
    # noise profiles.
    #
    # Age is only meaningful for the package carrying an image's *software*. The
    # base layer — bash, zlib, ca-certificates-bundle, su-exec — is low-churn by
    # nature and routinely months old without anything being wrong, so ageing it
    # weekly would be noise that teaches you to skim past the report.
    : > "${APKINDEX_CACHE}/primary"
    for apko in images/*/apko/*.yaml; do
        img="$(basename "$(dirname "$(dirname "$apko")")")"
        stem="${img%%-*}"                       # python-sodium -> python
        base="${img%%[0-9]*}"                   # node24        -> node
        # [a-z]* so an image name can be a prefix of its package: node -> nodejs-22.
        sed -nE 's/^[[:space:]]+- ([a-z0-9]([a-z0-9._+-]*[a-z0-9])?)$/\1/p' "$apko" \
            | grep -E "^(${img}|${stem}|${base:-$img})[a-z]*([-.]|$)" >> "${APKINDEX_CACHE}/primary" || true
    done
    sort -u -o "${APKINDEX_CACHE}/primary" "${APKINDEX_CACHE}/primary"

    # An unobtainable fix is precise regardless of which package it is in — it
    # means a CVE has a named fix that was never published — so that runs over
    # everything the images declare. Locally-built melange packages
    # (etcd-hardened, nginx-entrypoint, ...) are absent from the index and drop out.
    sed -nE 's/^[[:space:]]+- ([a-z0-9]([a-z0-9._+-]*[a-z0-9])?)$/\1/p' images/*/apko/*.yaml \
        | sort -u > "${APKINDEX_CACHE}/declared"

    have_secdb=0
    if fetch_secdb; then have_secdb=1; else
        echo "::warning::could not fetch security.json — unobtainable-fix check skipped" >&2
    fi

    now="$(date +%s)"
    while IFS= read -r pkg; do
        line="$(grep -P "^\Q${pkg}\E\t" "${APKINDEX_CACHE}/newest.tsv" 2>/dev/null | head -1)" || true
        [ -n "$line" ] || continue          # not a Wolfi package (built locally)
        ver="$(printf '%s' "$line" | cut -f2)"
        ts="$(printf '%s' "$line" | cut -f3)"
        age=$(( (now - ts) / 86400 ))

        if [ "$age" -gt "$STALE_AFTER_DAYS" ] && grep -qxF "$pkg" "${APKINDEX_CACHE}/primary"; then
            row "$pkg" "$ver" "${age}d" "FROZEN (no rebuild in ${age} days)"
            FROZEN=$((FROZEN + 1))
        fi

        [ "$have_secdb" = 1 ] || continue
        fixed="$(jq -r --arg p "$pkg" \
            '[.packages[] | select(.pkg.name == $p) | .pkg.secfixes | keys[] | select(. != "0")] | .[]' \
            "${APKINDEX_CACHE}/security.json" 2>/dev/null | sort -V | tail -1)"
        [ -n "$fixed" ] || continue
        if ! grep -qxF "${pkg}	${fixed}" "${APKINDEX_CACHE}/allvers.tsv"; then
            # Only report when the named fix is genuinely ahead of everything shipped.
            if [ "$(printf '%s\n%s\n' "$ver" "$fixed" | sort -V | tail -1)" = "$fixed" ]; then
                row "$pkg" "$ver" "-" "UNOBTAINABLE FIX (advisory names ${fixed}, not published)"
                FROZEN=$((FROZEN + 1))
            fi
        fi
    done < "${APKINDEX_CACHE}/declared"
fi

## ---------------------------------------------------------------------------
## Go dependency floor pins. Several images carry `go get mod@vX.Y.Z` lines that
## override what upstream's go.mod resolves, because that version fixed a CVE.
## Nothing checked them, and they rot exactly the way the version pins above do:
## a pin that was clean when written stops being clean without the file changing.
## grpc v1.82.1 was pinned as the fix for one advisory and by the time anyone
## looked it carried two more, in four images at once.
##
## Reported as INFO, never as drift: these are floors, not targets. "Newer exists"
## is not by itself a reason to move — the scan is. So this never opens a bump PR
## and never changes the exit code; it tells you which pin to look at when a
## finding names one.

if command -v curl >/dev/null; then
    gopins="$(mktemp)"
    # Only real `go get` invocations and their backslash continuations. Prose in
    # the surrounding comments mentions module@version too, and matching that
    # would report a pin nothing actually applies.
    for mel in images/*/melange.yaml; do
        image="$(basename "$(dirname "$mel")")"
        awk -v img="$image" '
            /^[[:space:]]*#/            { next }
            /go get/                    { cap = 1 }
            cap {
                line = $0
                while (match(line, /[a-z0-9.-]+\.[a-z]+\/[A-Za-z0-9._\/-]+@v[0-9][A-Za-z0-9.+-]*/)) {
                    print img "\t" substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
                if ($0 !~ /\\[[:space:]]*$/) { cap = 0 }
            }
        ' "$mel" >> "$gopins"
    done

    if [ -s "$gopins" ]; then
        [ "$PORCELAIN" = 1 ] || { echo; row IMAGE MODULE PINNED STATUS; row ------ ------ ------ ------; }
        while IFS="$(printf '\t')" read -r image spec; do
            mod="${spec%@*}"; pin="${spec##*@}"
            # The module proxy lowercases uppercase path elements as !x, so
            # github.com/Azure/... is github.com/!azure/... — querying the literal
            # path 404s and the pin would silently never be checked.
            esc="$(printf '%s' "$mod" | sed 's/\([A-Z]\)/!\L\1/g')"
            latest="$(curl -sSfL --retry 3 --retry-all-errors --max-time 30 \
                "https://proxy.golang.org/${esc}/@latest" 2>/dev/null \
                | sed -n 's/.*"Version":"\([^"]*\)".*/\1/p')" || true
            if [ -z "$latest" ]; then
                row "$image" "$mod" "$pin" "could not query proxy.golang.org"
                continue
            fi
            if [ "$pin" != "$latest" ] && \
               [ "$(printf '%s\n%s\n' "$pin" "$latest" | sort -V | tail -1)" = "$latest" ]; then
                row "$image" "$mod" "$pin" "INFO: ${latest} available (floor pin — move it only if the scan asks)"
            fi
        done < "$gopins"
    fi
    rm -f "$gopins"
fi

if [ "$PORCELAIN" = 0 ]; then
    echo
    echo "Checked ${FOUND} image(s); ${BEHIND} behind upstream; ${FROZEN} frozen or unobtainable; ${ERRORS} could not be checked."
fi

[ "$ERRORS" -eq 0 ] || exit 1
# 10 means "there is something to report". The workflow decides what to do with
# each row: BEHIND gets a bump PR, FROZEN and UNOBTAINABLE go to the issue, since
# there is nothing to bump to.
{ [ "$BEHIND" -eq 0 ] && [ "$FROZEN" -eq 0 ]; } || exit 10
exit 0
