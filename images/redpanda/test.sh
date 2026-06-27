#!/usr/bin/env bash
# Smoke test for the hardened redpanda image. Expects $IMAGE (full tag).
# redpanda intentionally ships bash+busybox (the SASL superuser bootstrap is a
# /bin/sh entrypoint and the broker launcher is a bash wrapper). Resource flags
# are passed through the entrypoint's "$@" so they don't change image behavior.
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-redpanda${DEV:+-dev}"

start -p 19092:9092 -p 19644:9644 -e REDPANDA_SUPERUSER_PASSWORD=testpass123 \
    "$IMAGE" --smp 1 --memory 1G --reserve-memory 0M --overprovisioned
check_running

i=0
while [ "$i" -lt 90 ]; do
    docker exec "$CONTAINER" rpk cluster health 2>/dev/null | grep -q 'Healthy:.*true' && break
    sleep 2; i=$((i + 1))
done

assert_contains "cluster is healthy" "Healthy:.*true" "$(docker exec "$CONTAINER" rpk cluster health 2>&1)"
assert_contains "superuser created" "admin" "$(docker exec "$CONTAINER" rpk acl user list 2>&1)"
assert_rc0 "rpk topic create" docker exec "$CONTAINER" rpk topic create test-topic \
    --user admin --password testpass123 --sasl-mechanism SCRAM-SHA-256
assert_contains "topic created" "test-topic" "$(docker exec "$CONTAINER" rpk topic list \
    --user admin --password testpass123 --sasl-mechanism SCRAM-SHA-256 2>&1)"
check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
