#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: sign.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"

DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${FULL_TAG}" 2>/dev/null)
if [ -z "$DIGEST" ]; then
    echo "ERROR: No repo digest found. Push the image first."
    exit 1
fi

# Key-based when COSIGN_PRIVATE_KEY is set; otherwise keyless (Fulcio/OIDC).
# With no extra args cosign uses the ambient OIDC identity in CI (GitHub Actions
# with `id-token: write`) and falls back to an interactive browser flow locally.
if [ -n "${COSIGN_PRIVATE_KEY:-}" ] && [ -f "$COSIGN_PRIVATE_KEY" ]; then
    COSIGN_ARGS=(--key "$COSIGN_PRIVATE_KEY")
    echo "==> Key-based signing with ${COSIGN_PRIVATE_KEY}"
else
    COSIGN_ARGS=()
    echo "==> Keyless signing (ambient OIDC)"
fi

echo "==> Signing ${DIGEST}"
cosign sign --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} "${DIGEST}"

if [ -f "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" ]; then
    echo "==> Attaching SBOM attestation"
    cosign attest --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} \
        --predicate "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" \
        --type cyclonedx \
        "${DIGEST}"
fi

if [ -f "${REPORT_DIR}/provenance${SUF}.json" ]; then
    echo "==> Attaching SLSA provenance attestation"
    cosign attest --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} \
        --predicate "${REPORT_DIR}/provenance${SUF}.json" \
        --type slsaprovenance1 \
        "${DIGEST}"
fi

echo "==> Signed: ${DIGEST}"
