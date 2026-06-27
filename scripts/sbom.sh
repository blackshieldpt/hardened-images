#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: sbom.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"
ARCHIVE_DIR="${ROOT_DIR}/reports/${IMAGE}/archive"

mkdir -p "$REPORT_DIR" "$ARCHIVE_DIR"

if [ -f "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" ]; then
    PREV_DATE=$(date -r "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" +%Y%m%d-%H%M%S)
    mv "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" "${ARCHIVE_DIR}/sbom-cyclonedx${SUF}-${PREV_DATE}.json"
    mv "${REPORT_DIR}/sbom-spdx${SUF}.json" "${ARCHIVE_DIR}/sbom-spdx${SUF}-${PREV_DATE}.json"
    echo "==> Archived previous SBOMs to ${ARCHIVE_DIR}/ (${PREV_DATE})"
fi

echo "==> Generating SBOM for ${FULL_TAG}"

syft "${FULL_TAG}" -o cyclonedx-json > "${REPORT_DIR}/sbom-cyclonedx${SUF}.json"
echo "    CycloneDX: ${REPORT_DIR}/sbom-cyclonedx${SUF}.json"

syft "${FULL_TAG}" -o spdx-json > "${REPORT_DIR}/sbom-spdx${SUF}.json"
echo "    SPDX:      ${REPORT_DIR}/sbom-spdx${SUF}.json"

if ls "${ARCHIVE_DIR}"/sbom-cyclonedx${SUF}-*.json >/dev/null 2>&1; then
    PREV=$(ls -t "${ARCHIVE_DIR}"/sbom-cyclonedx${SUF}-*.json | head -1)
    echo ""
    echo "==> SBOM diff (packages changed since $(basename "$PREV" .json | sed "s/sbom-cyclonedx${SUF}-//"))"

    PREV_PKGS=$(jq -r '.components[]? | "\(.name) \(.version)"' "$PREV" 2>/dev/null | sort -u)
    CURR_PKGS=$(jq -r '.components[]? | "\(.name) \(.version)"' "${REPORT_DIR}/sbom-cyclonedx${SUF}.json" 2>/dev/null | sort -u)

    ADDED=$(comm -13 <(echo "$PREV_PKGS") <(echo "$CURR_PKGS") 2>/dev/null || true)
    REMOVED=$(comm -23 <(echo "$PREV_PKGS") <(echo "$CURR_PKGS") 2>/dev/null || true)

    if [ -n "$ADDED" ]; then
        echo "    Added/Updated:"
        echo "$ADDED" | sed 's/^/      + /'
    fi
    if [ -n "$REMOVED" ]; then
        echo "    Removed/Replaced:"
        echo "$REMOVED" | sed 's/^/      - /'
    fi
    if [ -z "$ADDED" ] && [ -z "$REMOVED" ]; then
        echo "    No package changes detected."
    fi
fi

echo ""
echo "==> SBOM complete for ${IMAGE}${SUF}"
