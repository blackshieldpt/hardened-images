#!/usr/bin/env bash
# Smoke test for the hardened openbao image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-openbao${DEV:+-dev}"

start -p 18200:8200 "$IMAGE"
check_running
wait_http http://localhost:18200/v1/sys/seal-status 30 || true
assert_eq "seal-status returns 200" "200" "$(http_code http://localhost:18200/v1/sys/seal-status)"
assert_contains "fresh server is sealed+uninitialized" '"sealed":true' \
    "$(curl -fsS http://localhost:18200/v1/sys/seal-status 2>&1)"
assert_contains "bao CLI present" "OpenBao v2" "$(docker exec "$CONTAINER" /usr/bin/bao version 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
