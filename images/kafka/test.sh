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

# Round-trip a record. Creating a topic is metadata only; this is what actually
# exercises the broker's record path (lz4-java and jackson); a break there would
# otherwise show up as a green build and a broken image.
docker exec -i "$CONTAINER" "$K/kafka-console-producer.sh" \
    --bootstrap-server localhost:9092 --topic test-topic \
    --producer-property compression.type=lz4 <<<'hardened-images-probe' >/dev/null 2>&1
assert_contains "record round-trips (lz4)" "hardened-images-probe" \
    "$(docker exec "$CONTAINER" "$K/kafka-console-consumer.sh" \
        --bootstrap-server localhost:9092 --topic test-topic \
        --from-beginning --max-messages 1 --timeout-ms 30000 2>&1)"

# Connect is removed, not merely unused: its jars are what drag Jetty in.
assert_rc0 "no Jetty/Jersey/Connect jars" \
    docker exec "$CONTAINER" sh -c '! ls /usr/lib/kafka/libs | grep -qE "^(connect-|jetty-|jersey-|swagger-)"'

check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
