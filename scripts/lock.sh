#!/usr/bin/env bash
# Regenerate the committed apko lockfile for an image, pinning the exact package
# set (versions + digests). Commit the result: `build.sh` then reproduces the
# image exactly from it. Run this to deliberately update dependencies — e.g. to
# pick up Wolfi CVE patches — so the change is visible in the diff and provenance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

source "$ROOT_DIR/config.env"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
source "$ROOT_DIR/scripts/common.sh"

IMAGE="${1:?Usage: lock.sh <image-name> [prod|dev]}"
VARIANT="${2:-prod}"
ARCH="${ARCH:-x86_64}"
SUF="$(variant_suffix "$VARIANT")"

APKO_CONFIG="images/${IMAGE}/apko/${IMAGE}.yaml"
MELANGE_CONFIG="images/${IMAGE}/melange.yaml"
[ -f "$APKO_CONFIG" ] || { echo "ERROR: missing apko config $APKO_CONFIG"; exit 1; }

# Melange-repackaged images aren't committed-lock pinned: the melange package is
# signed with an ephemeral per-build key, so its control hash differs between
# runners and a committed lock would never match. They resolve fresh at build.
if [ -f "$MELANGE_CONFIG" ]; then
    echo "==> ${IMAGE}: melange image — not committed-lock pinned (resolves fresh at build). Skipping."
    exit 0
fi

# No melange handling below: the guard above already returned for every image that
# has a melange.yaml, so anything reaching here is apk-native by definition.
APKO_EXTRA=()

APKO_SRC="$APKO_CONFIG"
DEV_TMP=""
if [ "$VARIANT" = dev ]; then
    DEV_TMP="$(mktemp "${TMPDIR:-/tmp}/${IMAGE}-dev.XXXXXX.yaml")"
    compose_dev_apko "$APKO_CONFIG" "$(dev_packages_for "$IMAGE")" > "$DEV_TMP"
    APKO_SRC="$DEV_TMP"
fi

OUT="images/${IMAGE}/apko/${IMAGE}${SUF}.lock.json"
echo "==> Locking ${IMAGE}${SUF} -> ${OUT}"
apko lock "$APKO_SRC" --arch "$ARCH" --output "$OUT" "${APKO_EXTRA[@]}"
[ -n "$DEV_TMP" ] && rm -f "$DEV_TMP"
echo "==> Locked. Review and commit ${OUT}."
