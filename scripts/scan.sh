#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: scan.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE")"

FULL_TAG="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE}:${VERSION}${SUF}"
REPORT_DIR="${ROOT_DIR}/reports/${IMAGE}"

mkdir -p "$REPORT_DIR"

# Collect OpenVEX exception documents. Files under vex/ apply to all images;
# images/<name>/vex.openvex.json applies to this one. A finding marked
# not_affected/fixed (with a justification) is waived from the gate but still
# appears in the full JSON reports below, which are written WITHOUT VEX so they
# remain a complete audit record of everything found.
VEX_ARGS=()
for vexf in "${ROOT_DIR}"/vex/*.openvex.json "${ROOT_DIR}/images/${IMAGE}/vex.openvex.json"; do
    [ -f "$vexf" ] || continue
    VEX_ARGS+=(--vex "$vexf")
    echo "    VEX: ${vexf#${ROOT_DIR}/}"
done

FAILED=0

echo "==> Scanning ${FULL_TAG}"

echo "--- Grype ---"
grype "${FULL_TAG}" -o json > "${REPORT_DIR}/grype${SUF}.json" 2>/dev/null || true
if ! grype "${FULL_TAG}" ${VEX_ARGS[@]+"${VEX_ARGS[@]}"} --fail-on "${SEVERITY_THRESHOLD}" -o table 2>&1 | tee "${REPORT_DIR}/grype${SUF}.txt"; then
    echo "WARNING: Grype found unwaived vulnerabilities at or above ${SEVERITY_THRESHOLD}"
    FAILED=1
fi

echo ""
echo "--- Trivy ---"
trivy image --format json -o "${REPORT_DIR}/trivy${SUF}.json" "${FULL_TAG}" 2>/dev/null || true
if ! trivy image ${VEX_ARGS[@]+"${VEX_ARGS[@]}"} --severity "${SEVERITY_THRESHOLD}" --exit-code 1 "${FULL_TAG}" 2>&1 | tee "${REPORT_DIR}/trivy${SUF}.txt"; then
    echo "WARNING: Trivy found unwaived vulnerabilities at or above ${SEVERITY_THRESHOLD}"
    FAILED=1
fi

echo ""
echo "==> Reports saved to ${REPORT_DIR}/"

# SCAN_GATE=1 (default) blocks the build on unwaived findings; SCAN_GATE=0 makes
# scanning advisory (reports + warn, never fail). Toggle via config.env/.env or
# the environment — never by editing this script.
if [ "$FAILED" -eq 1 ] && [ "${SCAN_GATE:-1}" != "0" ]; then
    echo "==> SCAN FAILED: unwaived vulnerabilities found at ${SEVERITY_THRESHOLD} or above"
    echo "    Fix the package, add a justified OpenVEX waiver (see vex/README.md),"
    echo "    or set SCAN_GATE=0 to make scanning advisory."
    exit 1
fi

if [ "$FAILED" -eq 1 ]; then
    echo "==> SCAN WARNING: unwaived vulnerabilities at ${SEVERITY_THRESHOLD} or above (SCAN_GATE=0, advisory)"
else
    echo "==> Scan passed for ${IMAGE}${SUF}"
fi
