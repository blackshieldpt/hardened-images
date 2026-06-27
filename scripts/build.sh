#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: build.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
ARCH="${ARCH:-x86_64}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

# Reproducible builds: pin melange/apko file + layer timestamps to the source
# commit so rebuilding the same commit yields byte-identical layers.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT_DIR" log -1 --format=%ct 2>/dev/null || echo 0)}"

APKO_CONFIG="images/${IMAGE}/apko/${IMAGE}.yaml"
MELANGE_CONFIG="images/${IMAGE}/melange.yaml"
[ -f "$APKO_CONFIG" ] || { echo "ERROR: missing apko config $APKO_CONFIG"; exit 1; }

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
LATEST_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:latest${SUF}"
# Immutable per-build tag (source commit). Floating :${VERSION} and :latest move
# on every rebuild/relock; this one always pins to exactly this build.
SHORT_SHA="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
SHA_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}-${SHORT_SHA}"
TARBALL="${IMAGE}${SUF}.tar"

APKO_EXTRA=()
if [ -f "$MELANGE_CONFIG" ]; then
    if [ ! -f melange.rsa ]; then
        echo "==> Generating melange signing key"
        melange keygen
    fi
    echo "==> Building package(s) from source: ${MELANGE_CONFIG}"
    melange build "$MELANGE_CONFIG" \
        --source-dir "images/${IMAGE}" \
        --signing-key melange.rsa \
        --arch "$ARCH" \
        --out-dir ./packages
    APKO_EXTRA=(--repository-append ./packages --keyring-append melange.rsa.pub)
fi

# The dev variant is the prod image plus a shell + toolchain (same source build).
APKO_SRC="$APKO_CONFIG"
DEV_TMP=""
if [ "$VARIANT" = dev ]; then
    DEV_TMP="$(mktemp "${TMPDIR:-/tmp}/${IMAGE}-dev.XXXXXX.yaml")"
    compose_dev_apko "$APKO_CONFIG" "$(dev_packages_for "$IMAGE")" > "$DEV_TMP"
    APKO_SRC="$DEV_TMP"
fi

echo "==> Assembling ${FULL_TAG} with apko"
rm -f "$TARBALL"

# Build from the committed lockfile so the same commit reproduces the same image
# (apko + a fixed lockfile + SOURCE_DATE_EPOCH is byte-reproducible). Update the
# lockfile deliberately with `make lock IMAGE=<name>`. If no committed lockfile
# exists (e.g. a brand-new image), resolve fresh and warn — that build is not
# reproducible until the lockfile is committed.
REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"
mkdir -p "$REPORT_DIR"
COMMITTED_LOCK="images/${IMAGE}/apko/${IMAGE}${SUF}.lock.json"
if [ -f "$COMMITTED_LOCK" ] && [ ! -f "$MELANGE_CONFIG" ]; then
    LOCKFILE="$COMMITTED_LOCK"
    echo "==> Using committed lockfile ${COMMITTED_LOCK}"
else
    LOCKFILE="${REPORT_DIR}/apko${SUF}.lock.json"
    if [ -f "$MELANGE_CONFIG" ]; then
        # The melange-built package isn't reproducible across runners (each build
        # uses an ephemeral signing key), so its control hash won't match a
        # committed lock. Melange images resolve fresh each build by design.
        echo "==> Resolving package set fresh (melange image)"
    else
        echo "WARNING: no committed lockfile for ${IMAGE}${SUF} — resolving fresh (not reproducible)."
        echo "         Run 'make lock IMAGE=${IMAGE}' and commit ${COMMITTED_LOCK}."
    fi
    apko lock "$APKO_SRC" --arch "$ARCH" --output "$LOCKFILE" "${APKO_EXTRA[@]}"
fi

BUILD_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
apko build "$APKO_SRC" "$FULL_TAG" "$TARBALL" --arch "$ARCH" --lockfile "$LOCKFILE" "${APKO_EXTRA[@]}"
[ -n "$DEV_TMP" ] && rm -f "$DEV_TMP"

loaded="$(docker load < "$TARBALL" | sed -n 's/^Loaded image: //p' | head -1)"
[ -n "$loaded" ] || { echo "ERROR: docker load produced no image"; exit 1; }
docker tag "$loaded" "$FULL_TAG"
docker tag "$loaded" "$LATEST_TAG"
docker tag "$loaded" "$SHA_TAG"
[ "$loaded" != "$FULL_TAG" ] && docker rmi "$loaded" >/dev/null 2>&1 || true

rm -f "$TARBALL" sbom-*.json

# SLSA v1.0 provenance predicate (attested by sign.sh).
prov="$(write_provenance "$IMAGE" "$VERSION" "$VARIANT" "$APKO_CONFIG" "$MELANGE_CONFIG" "$ARCH" "$LOCKFILE" "$BUILD_STARTED")"

echo "==> Built: ${FULL_TAG}"
echo "==> Tagged: ${LATEST_TAG}"
echo "==> Provenance: ${prov}"
