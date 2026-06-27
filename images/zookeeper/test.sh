#!/usr/bin/env bash
# Smoke test for the hardened zookeeper image. Expects $IMAGE (full tag).
# zookeeper ships bash (zkServer.sh etc.), so no shell-less assertion.
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-zookeeper${DEV:+-dev}"
ZK=/usr/share/java/zookeeper/bin

start -p 12181:2181 "$IMAGE"
check_running

i=0
while [ "$i" -lt 40 ]; do
    docker exec "$CONTAINER" "$ZK/zkCli.sh" -server localhost:2181 ls / >/dev/null 2>&1 && break
    sleep 2; i=$((i + 1))
done

docker exec "$CONTAINER" "$ZK/zkCli.sh" -server localhost:2181 create /smoke hello >/dev/null 2>&1 || true
assert_contains "znode value readable" "hello" \
    "$(docker exec "$CONTAINER" "$ZK/zkCli.sh" -server localhost:2181 get /smoke 2>&1)"
check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
