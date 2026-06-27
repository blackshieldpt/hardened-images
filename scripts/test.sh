#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE_NAME="${1:?Usage: test.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
SUF="$(variant_suffix "$VARIANT")"

VERSION="$(resolve_version "$IMAGE_NAME")"

[ "$VARIANT" = dev ] && export DEV=1
export IMAGE="${REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${VERSION}${SUF}"
TEST_SCRIPT="$ROOT_DIR/images/${IMAGE_NAME}/test.sh"
[ -f "$TEST_SCRIPT" ] || { echo "ERROR: no test script at $TEST_SCRIPT"; exit 1; }

echo "==> Testing ${IMAGE}"
exec bash "$TEST_SCRIPT"
