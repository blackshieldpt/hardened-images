#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: verify.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"

# Verify by immutable digest, not the mutable tag (avoids a tag-repoint TOCTOU).
# Prefer the digest push.sh recorded; else resolve the tag from the registry.
DIGEST_FILE="${ROOT_DIR}/reports/${IMAGE}/digest${SUF}.txt"
REF="$FULL_TAG"
if [ -f "$DIGEST_FILE" ] && [ -s "$DIGEST_FILE" ]; then
    REF="$(tr -d '[:space:]' < "$DIGEST_FILE")"
elif d="$(docker buildx imagetools inspect "$FULL_TAG" --format '{{.Manifest.Digest}}' 2>/dev/null)" && [ -n "$d" ]; then
    REF="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}@${d}"
else
    echo "WARNING: could not resolve a digest; verifying by mutable tag ${FULL_TAG}"
fi

# Key-based when COSIGN_PUBLIC_KEY is set; otherwise OIDC certificate identity.
if [ -n "${COSIGN_PUBLIC_KEY:-}" ] && [ -f "$COSIGN_PUBLIC_KEY" ]; then
    VERIFY_ARGS=(--key "$COSIGN_PUBLIC_KEY")
    echo "==> Verifying with key: ${COSIGN_PUBLIC_KEY}"
else
    VERIFY_ARGS=(--certificate-identity-regexp "${COSIGN_IDENTITY}" --certificate-oidc-issuer-regexp "${COSIGN_OIDC_ISSUER}")
    echo "==> Verifying with OIDC identity"
fi

# Full verification (default) checks the Rekor transparency log, which time-binds
# the short-lived keyless cert. VERIFY_IGNORE_TLOG=1 skips that query — used only
# for the in-pipeline self-check right after signing (no Rekor dependency, no
# stalls); consumers should always verify with the tlog (see README).
if [ "${VERIFY_IGNORE_TLOG:-}" = "1" ]; then
    VERIFY_ARGS+=(--insecure-ignore-tlog)
    echo "==> (skipping transparency-log check — self-check mode)"
fi

echo "==> Verifying signature for ${REF}"
cosign verify "${VERIFY_ARGS[@]}" "${REF}"

echo ""
echo "==> Verifying SBOM attestation"
cosign verify-attestation "${VERIFY_ARGS[@]}" --type cyclonedx "${REF}"

echo ""
echo "==> Verifying SLSA provenance attestation"
cosign verify-attestation "${VERIFY_ARGS[@]}" --type slsaprovenance1 "${REF}"

echo "==> Verification passed for ${IMAGE}${SUF}"
