#!/usr/bin/env bash
# Smoke test for the hardened nats image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-nats${DEV:+-dev}"

start -p 18222:8222 "$IMAGE"
check_running
wait_http http://localhost:18222/healthz 30 || true
assert_eq "healthz returns 200" "200" "$(http_code http://localhost:18222/healthz)"
assert_contains "monitoring returns server info" "server_id" "$(curl -fsS http://localhost:18222/varz 2>&1)"
assert_contains "JetStream enabled" "config|memory" "$(curl -fsS http://localhost:18222/jsz 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
