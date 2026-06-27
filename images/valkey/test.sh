#!/usr/bin/env bash
# Smoke test for the hardened valkey image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-valkey${DEV:+-dev}"

start -p 16379:6379 "$IMAGE"
check_running
wait_exec 30 valkey-cli ping || true
assert_eq "PING returns PONG" "PONG" "$(docker exec "$CONTAINER" valkey-cli ping 2>&1)"
docker exec "$CONTAINER" valkey-cli SET testkey testval >/dev/null 2>&1 || true
assert_eq "GET returns value" "testval" "$(docker exec "$CONTAINER" valkey-cli GET testkey 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
