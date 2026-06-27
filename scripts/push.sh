#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: push.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
LATEST_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:latest${SUF}"

echo "==> Pushing ${FULL_TAG}"
docker push "${FULL_TAG}"
docker push "${LATEST_TAG}"
echo "==> Pushed: ${FULL_TAG}"

# Mirror to a secondary registry when configured. Skipped silently if
# MIRROR_REGISTRY is unset or login is unavailable.
if [ -n "${MIRROR_REGISTRY:-}" ]; then
    MIRROR_TAG="${MIRROR_REGISTRY}/${MIRROR_PREFIX:-$IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
    MIRROR_LATEST="${MIRROR_REGISTRY}/${MIRROR_PREFIX:-$IMAGE_PREFIX}/${IMAGE}:latest${SUF}"
    echo "==> Mirroring to ${MIRROR_TAG}"
    docker tag "${FULL_TAG}" "${MIRROR_TAG}"
    docker tag "${LATEST_TAG}" "${MIRROR_LATEST}"
    if docker push "${MIRROR_TAG}" && docker push "${MIRROR_LATEST}"; then
        echo "==> Mirrored: ${MIRROR_TAG}"
    else
        echo "WARNING: mirror push failed (not logged in to ${MIRROR_REGISTRY}?) — continuing"
    fi
fi

# Record the immutable digest. Tags here are mutable (re-pushed each build), so
# consumers should pin by digest; verify.sh and downstream pulls read this.
DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${FULL_TAG}" 2>/dev/null || true)"
if [ -n "$DIGEST" ]; then
    REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"
    mkdir -p "$REPORT_DIR"
    printf '%s\n' "$DIGEST" > "${REPORT_DIR}/digest${SUF}.txt"
    echo "==> Digest: ${DIGEST}"
fi
