#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: upload-sbom.sh <image-name>}"

DTRACK_URL="${DTRACK_URL:?DTRACK_URL must be set (e.g. https://dtrack.example.com)}"
DTRACK_API_KEY="${DTRACK_API_KEY:?DTRACK_API_KEY must be set}"

VERSION="$(resolve_version "$IMAGE")"

PROJECT_NAME="${IMAGE_PREFIX}/${IMAGE}"
SBOM_FILE="${ROOT_DIR}/reports/${IMAGE}/sbom-cyclonedx.json"

if [ ! -f "$SBOM_FILE" ]; then
    echo "ERROR: SBOM not found at ${SBOM_FILE}"
    echo "       Run 'make sbom IMAGE=${IMAGE}' first."
    exit 1
fi

BOM_BASE64=$(base64 -w0 "$SBOM_FILE")

echo "==> Uploading SBOM for ${PROJECT_NAME}:${VERSION} to Dependency-Track"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    "${DTRACK_URL}/api/v1/bom" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: ${DTRACK_API_KEY}" \
    -d @- <<EOF
{
  "projectName": "${PROJECT_NAME}",
  "projectVersion": "${VERSION}",
  "autoCreate": true,
  "bom": "${BOM_BASE64}"
}
EOF
)

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "==> Uploaded successfully (HTTP ${HTTP_CODE})"
else
    echo "ERROR: Upload failed (HTTP ${HTTP_CODE})"
    exit 1
fi

echo "==> Cleaning up old versions of ${PROJECT_NAME}"

PROJECTS=$(curl -s -G \
    "${DTRACK_URL}/api/v1/project" \
    --data-urlencode "name=${PROJECT_NAME}" \
    -H "X-Api-Key: ${DTRACK_API_KEY}")

echo "$PROJECTS" | python3 -c "
import json, sys
projects = json.load(sys.stdin)
for p in projects:
    if p.get('name') == '${PROJECT_NAME}' and p.get('version') != '${VERSION}':
        print(p['uuid'] + ' ' + p.get('version', 'unknown'))
" | while read -r uuid old_version; do
    echo "    Deleting ${PROJECT_NAME}:${old_version} (${uuid})"
    curl -s -o /dev/null -X DELETE \
        "${DTRACK_URL}/api/v1/project/${uuid}" \
        -H "X-Api-Key: ${DTRACK_API_KEY}"
done

echo "==> Cleanup complete"
