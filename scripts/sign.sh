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

# Keyless signing depends on two services that are not ours: GitHub's OIDC token
# endpoint and Fulcio. Both flake, and a single failure used to fail the job
# *after* the push had already succeeded, leaving an image published but
# unsigned -- exactly the state the signature exists to rule out. Five of 42 jobs
# died this way on v0.6.0 with "fetching ambient OIDC credentials: invalid
# character 'u' looking for beginning of value": the token endpoint answered with
# something that was not JSON. A plain re-run signed all five.
#
# So retry, the way curl and apt are already retried elsewhere here. Deliberately
# NOT idempotent-blind: cosign is happy to attach a second signature, so a retry
# after a *partial* success costs an extra signature layer, not a broken image.
retry_cosign() {
    local attempt
    for attempt in 1 2 3; do
        "$@" && return 0
        echo "WARNING: ${1} ${2} failed (attempt ${attempt}/3)" >&2
        # An `[ ... ] && sleep` here would be the loop body's last command, so on
        # the final attempt its false test trips set -e and the script exits
        # before the ERROR line below is ever printed.
        if [ "$attempt" -lt 3 ]; then sleep $((attempt * 5)); fi
    done
    echo "ERROR: ${1} ${2} failed after 3 attempts" >&2
    return 1
}

echo "==> Signing ${DIGEST}"
retry_cosign cosign sign --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} "${DIGEST}"

if [ -f "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" ]; then
    echo "==> Attaching SBOM attestation"
    retry_cosign cosign attest --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} \
        --predicate "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" \
        --type cyclonedx \
        "${DIGEST}"
fi

if [ -f "${REPORT_DIR}/provenance${SUF}.json" ]; then
    echo "==> Attaching SLSA provenance attestation"
    retry_cosign cosign attest --yes ${COSIGN_ARGS[@]+"${COSIGN_ARGS[@]}"} \
        --predicate "${REPORT_DIR}/provenance${SUF}.json" \
        --type slsaprovenance1 \
        "${DIGEST}"
fi

echo "==> Signed: ${DIGEST}"
