#!/usr/bin/env bash
# Smoke test for the hardened manticore image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-manticore${DEV:+-dev}"

start -p 19306:9306 -p 19308:9308 "$IMAGE"
check_running
wait_exec 30 searchd --status --config /etc/manticoresearch/manticore.conf || true
assert_rc0 "searchd --status" docker exec "$CONTAINER" searchd --status --config /etc/manticoresearch/manticore.conf
assert_eq "HTTP API 200" "200" "$(http_code http://localhost:19308/)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
