#!/usr/bin/env bash
# Apply the version bump for one image, so CI can prove or disprove it in a PR.
#
# check-updates.sh only reports. This applies the mechanical part of acting on
# that report: it edits the pin, re-resolves whatever the image derives from it
# (lockfile, expected-commit, artifact sha256), and leaves the tree dirty for the
# caller to commit. It does NOT build, test or push — the PR's CI run is what
# decides whether the bump is good, and that is deliberate: a bump that compiles
# and passes the scan gate is the only kind worth merging.
#
# Exit 0 = a complete, buildable change was applied.
# Exit 3 = this image's bump cannot be fully automated (says why; caller reports).
# Exit 2 = usage/tooling error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

IMAGE="${1:?Usage: propose-update.sh <image> <new-version>}"
NEW="${2:?Usage: propose-update.sh <image> <new-version>}"

MEL="images/${IMAGE}/melange.yaml"
APKO="images/${IMAGE}/apko/${IMAGE}.yaml"
LOCK="images/${IMAGE}/apko/${IMAGE}.lock.json"
VAR="VERSION_$(printf '%s' "$IMAGE" | tr '-' '_')"

note() { echo "==> $*"; }
skip() { echo "SKIP(${IMAGE}): $*" >&2; exit 3; }

# --- from-source images: the pin lives in melange package.version -------------
if [ -f "$MEL" ] && grep -qE '^    identifier:' "$MEL"; then
    OLD="$(sed -nE 's/^  version:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' "$MEL" | head -1)"
    [ -n "$OLD" ] || skip "could not read package.version"
    note "${IMAGE}: ${OLD} -> ${NEW} (from source)"

    # Every from-source image derives something else from the version. Refuse to
    # emit a half-applied bump: an image whose version moved but whose artifact
    # hash did not is exactly the "tag lies about contents" failure the build
    # assertions were added to catch.
    if grep -q 'expected-commit:' "$MEL"; then
        repo="$(sed -nE 's#^      repository:[[:space:]]*https://github.com/([^[:space:]]+).*#\1#p' "$MEL" | head -1)"
        [ -n "$repo" ] || skip "git-checkout without a resolvable github repository"
        command -v gh >/dev/null || skip "gh needed to resolve the tag's commit"
        # Take the tag shape from the git-checkout step rather than assuming a `v`
        # prefix: etcd/mailpit/openbao/versitygw tag v<version>, zookeeper tags
        # release-<version>. Assuming `v` made every Apache-style bump fail the lookup
        # and fall through to the tracking issue instead of opening a PR. (Kafka will
        # need this too once it moves from source — its tags are a bare <version>.)
        tagtmpl="$(sed -nE 's/^      tag:[[:space:]]*([^[:space:]]+).*/\1/p' "$MEL" | head -1)"
        [ -n "$tagtmpl" ] || skip "git-checkout without a tag template"
        tag="$(printf '%s' "$tagtmpl" | sed "s|\${{package\.version}}|${NEW}|g")"
        # Annotated tags must be dereferenced: the tag object's SHA is not the
        # commit, and expected-commit wants the commit.
        obj="$(gh api "repos/${repo}/git/ref/tags/${tag}" --jq '.object.sha' 2>/dev/null)"
        typ="$(gh api "repos/${repo}/git/ref/tags/${tag}" --jq '.object.type' 2>/dev/null)"
        [ -n "$obj" ] || skip "tag ${tag} not found in ${repo}"
        if [ "$typ" = "tag" ]; then
            obj="$(gh api "repos/${repo}/git/tags/${obj}" --jq '.object.sha' 2>/dev/null)"
            [ -n "$obj" ] || skip "could not dereference annotated tag ${tag}"
        fi
        sed -i -E "s/^  version: .*/  version: ${NEW}/" "$MEL"
        sed -i -E "s/^      expected-commit: .*/      expected-commit: ${obj}/" "$MEL"
        note "expected-commit -> ${obj}"
    elif grep -qE '^  sha256:|^  deb_sha256:' "$MEL"; then
        # Artifact-hash images. The URL has to be reconstructed per image, and
        # manticore's filename embeds an opaque upstream build id that only its
        # apt index knows — so those are reported rather than half-applied.
        skip "pins an artifact sha256; re-fetch and re-hash by hand (see melange.yaml)"
    else
        sed -i -E "s/^  version: .*/  version: ${NEW}/" "$MEL"
    fi
    # Reset epoch: it counts rebuilds of one version, so it restarts on a bump.
    sed -i -E "s/^  epoch: .*/  epoch: 0/" "$MEL"
    note "done — build/test/scan will run in CI"
    exit 0
fi

# --- apk-native and config-only images: the pin names a Wolfi version line -----
[ -f "$APKO" ] || skip "no apko config"
OLD="$(sed -nE "s/^${VAR}=([^#[:space:]]+).*/\1/p" config.env | head -1)"
[ -n "$OLD" ] || skip "no ${VAR} in config.env"
note "${IMAGE}: ${OLD} -> ${NEW} (Wolfi version line)"

# Rewrite every package that carries the old line in its name — families ship
# siblings (valkey-8.1-cli, postgresql-18-client/-contrib) that must move together
# or apko resolves a mismatched set.
moved="$(grep -cE "^[[:space:]]+- [a-z0-9._+-]*-${OLD}(-[a-z0-9._+-]+)?$" "$APKO" || true)"
[ "${moved:-0}" -gt 0 ] || skip "no package in ${APKO} carries the line ${OLD}"
# Derive the family base from the first matching package, then rewrite that
# family everywhere in the file — including the header comment, which otherwise
# keeps naming the old line and makes the generated PR misdescribe itself.
fambase="$(grep -oE "^[[:space:]]+- [a-z0-9._+-]*-${OLD}$" "$APKO" | head -1 | sed -E "s/^[[:space:]]+- //; s/-${OLD}$//")"
sed -i -E "s/^([[:space:]]+- [a-z0-9._+-]*)-${OLD}(-[a-z0-9._+-]+)?$/\1-${NEW}\2/" "$APKO"
[ -n "$fambase" ] && sed -i "s/${fambase}-${OLD}/${fambase}-${NEW}/g" "$APKO"
sed -i -E "s/^${VAR}=[^#[:space:]]+/${VAR}=${NEW}/" config.env
note "rewrote ${moved} package reference(s) in ${APKO}"

# Committed-lock images must be re-resolved or the build would install the old
# line regardless of what the yaml now says. lock.sh returns early for melange
# images, so this is a no-op where there is no committed lock.
if [ -f "$LOCK" ]; then
    command -v apko >/dev/null || skip "apko needed to re-resolve ${LOCK}"
    note "re-resolving ${LOCK}"
    ./scripts/lock.sh "$IMAGE" >/dev/null || skip "lock failed for ${NEW} — is the line published for this arch?"
fi
note "done — build/test/scan will run in CI"
exit 0
