#!/usr/bin/env bash
# Smoke test for the hardened kafka image (KRaft). Expects $IMAGE (full tag).
# kafka ships bash (start/storage scripts), so no shell-less assertion.
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-kafka${DEV:+-dev}"
K=/usr/lib/kafka/bin

start -p 19092:9092 "$IMAGE"
check_running

i=0
while [ "$i" -lt 60 ]; do
    docker exec "$CONTAINER" "$K/kafka-topics.sh" --bootstrap-server localhost:9092 --list >/dev/null 2>&1 && break
    sleep 2; i=$((i + 1))
done

assert_rc0 "create topic" docker exec "$CONTAINER" "$K/kafka-topics.sh" \
    --bootstrap-server localhost:9092 --create --topic test-topic --partitions 1 --replication-factor 1
assert_contains "topic listed" "test-topic" \
    "$(docker exec "$CONTAINER" "$K/kafka-topics.sh" --bootstrap-server localhost:9092 --list 2>&1)"
check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
