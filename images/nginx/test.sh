#!/usr/bin/env bash
# Smoke test for the hardened nginx image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-nginx${DEV:+-dev}"

start -p 18080:80 "$IMAGE"
check_running
wait_http http://localhost:18080/ 30 || true
assert_eq "serves HTTP 200" "200" "$(http_code http://localhost:18080/)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl openssl; else check_no_shell; fi
finish
