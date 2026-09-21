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

# What gets scanned. The build loads the image it just built into the local
# docker daemon, so that is what the gate must look at (default). A bare
# reference lets the scanners pick the source themselves, which locally means a
# months-old daemon copy of the same tag silently shadows the registry — the gate
# then passes or fails on an image nobody is running. Say which one we mean.
#   SCAN_SOURCE=docker    (default) the freshly built local image
#   SCAN_SOURCE=registry  what is actually published, for auditing
case "${SCAN_SOURCE:-docker}" in
    docker)   GRYPE_REF="docker:${FULL_TAG}"; TRIVY_ARGS=(--image-src docker) ;;
    registry) GRYPE_REF="registry:${FULL_TAG}"; TRIVY_ARGS=(--image-src remote) ;;
    *) echo "ERROR: SCAN_SOURCE='${SCAN_SOURCE}' is not docker or registry" >&2; exit 2 ;;
esac
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

echo "==> Scanning ${GRYPE_REF}"

echo "--- Grype ---"
grype "${GRYPE_REF}" -o json > "${REPORT_DIR}/grype${SUF}.json" 2>/dev/null || true
if ! grype "${GRYPE_REF}" ${VEX_ARGS[@]+"${VEX_ARGS[@]}"} --fail-on "${SEVERITY_THRESHOLD}" -o table 2>&1 | tee "${REPORT_DIR}/grype${SUF}.txt"; then
    echo "WARNING: Grype found unwaived vulnerabilities at or above ${SEVERITY_THRESHOLD}"
    FAILED=1
fi

echo ""
echo "--- Trivy ---"
# grype's --fail-on means "this level and above"; trivy's --severity is an exact
# list, so passing the bare threshold makes trivy ignore everything *worse* than
# it. At CRITICAL the two happen to agree, which is why this was invisible — but
# set SEVERITY_THRESHOLD=HIGH (which config.env advertises) and trivy would stop
# reporting CRITICAL altogether, in the gate and in the committed report.
case "${SEVERITY_THRESHOLD}" in
    CRITICAL) TRIVY_SEVERITIES="CRITICAL" ;;
    HIGH)     TRIVY_SEVERITIES="HIGH,CRITICAL" ;;
    MEDIUM)   TRIVY_SEVERITIES="MEDIUM,HIGH,CRITICAL" ;;
    LOW)      TRIVY_SEVERITIES="LOW,MEDIUM,HIGH,CRITICAL" ;;
    *) echo "ERROR: SEVERITY_THRESHOLD='${SEVERITY_THRESHOLD}' is not one of CRITICAL/HIGH/MEDIUM/LOW" >&2; exit 2 ;;
esac
trivy image "${TRIVY_ARGS[@]}" --format json -o "${REPORT_DIR}/trivy${SUF}.json" "${FULL_TAG}" 2>/dev/null || true
if ! trivy image "${TRIVY_ARGS[@]}" ${VEX_ARGS[@]+"${VEX_ARGS[@]}"} --severity "${TRIVY_SEVERITIES}" --exit-code 1 "${FULL_TAG}" 2>&1 | tee "${REPORT_DIR}/trivy${SUF}.txt"; then
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
