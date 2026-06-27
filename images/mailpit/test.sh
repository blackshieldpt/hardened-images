#!/usr/bin/env bash
# Smoke test for the hardened mailpit image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-mailpit${DEV:+-dev}"

start -p 11025:1025 -p 18025:8025 "$IMAGE"
check_running
wait_http http://localhost:18025/livez 30 || true
assert_eq "livez returns 200" "200" "$(http_code http://localhost:18025/livez)"
assert_eq "readyz returns 200" "200" "$(http_code http://localhost:18025/readyz)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl openssl; else check_no_shell; fi
finish
