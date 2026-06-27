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

# Pin the exact package set (versions + checksums) into a lockfile, then build
# from it. Makes the build reproducible and the resolved inputs auditable; the
# lockfile also feeds the provenance attestation (resolvedDependencies).
REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"
mkdir -p "$REPORT_DIR"
LOCKFILE="${REPORT_DIR}/apko${SUF}.lock.json"
apko lock "$APKO_SRC" --arch "$ARCH" --output "$LOCKFILE" "${APKO_EXTRA[@]}"

BUILD_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
apko build "$APKO_SRC" "$FULL_TAG" "$TARBALL" --arch "$ARCH" --lockfile "$LOCKFILE" "${APKO_EXTRA[@]}"
[ -n "$DEV_TMP" ] && rm -f "$DEV_TMP"

loaded="$(docker load < "$TARBALL" | sed -n 's/^Loaded image: //p' | head -1)"
[ -n "$loaded" ] || { echo "ERROR: docker load produced no image"; exit 1; }
docker tag "$loaded" "$FULL_TAG"
docker tag "$loaded" "$LATEST_TAG"
[ "$loaded" != "$FULL_TAG" ] && docker rmi "$loaded" >/dev/null 2>&1 || true

rm -f "$TARBALL" sbom-*.json

# SLSA v1.0 provenance predicate (attested by sign.sh).
prov="$(write_provenance "$IMAGE" "$VERSION" "$VARIANT" "$APKO_CONFIG" "$MELANGE_CONFIG" "$ARCH" "$LOCKFILE" "$BUILD_STARTED")"

echo "==> Built: ${FULL_TAG}"
echo "==> Tagged: ${LATEST_TAG}"
echo "==> Provenance: ${prov}"
