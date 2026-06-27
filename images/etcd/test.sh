#!/usr/bin/env bash
# Smoke test for the hardened etcd image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-etcd${DEV:+-dev}"

start -p 12379:2379 "$IMAGE"
check_running
wait_exec 20 etcdctl endpoint health || true
assert_rc0 "endpoint health" docker exec "$CONTAINER" etcdctl endpoint health
docker exec "$CONTAINER" etcdctl put k v >/dev/null 2>&1 || true
assert_eq "etcdctl get returns value" "v" "$(docker exec "$CONTAINER" etcdctl get k --print-value-only 2>&1 | tr -d '\r\n')"
assert_contains "etcd 3.6" "3\.6" "$(docker run --rm --entrypoint etcd "$IMAGE" --version 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
