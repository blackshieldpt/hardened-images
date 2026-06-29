#!/usr/bin/env bash
# Smoke test for the hardened clickhouse image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-clickhouse${DEV:+-dev}"

start -p 18123:8123 "$IMAGE"
check_running
wait_exec 60 clickhouse-client --query "SELECT 1" || true
assert_eq "SELECT 1 returns 1" "1" "$(docker exec "$CONTAINER" clickhouse-client --query 'SELECT 1' 2>&1)"
docker exec "$CONTAINER" clickhouse-client --query "CREATE TABLE test_tbl (id UInt32) ENGINE = MergeTree() ORDER BY id" >/dev/null 2>&1 || true
docker exec "$CONTAINER" clickhouse-client --query "INSERT INTO test_tbl VALUES (42)" >/dev/null 2>&1 || true
assert_eq "inserted row readable" "42" "$(docker exec "$CONTAINER" clickhouse-client --query 'SELECT id FROM test_tbl' 2>&1)"
assert_contains "version 26.1.12.23" "26\.1\.12\.23" "$(docker exec "$CONTAINER" clickhouse-client --query 'SELECT version()' 2>&1)"
assert_eq "HTTP interface 200" "200" "$(http_code 'http://localhost:18123/?query=SELECT%201')"

# Env-var contract: CLICKHOUSE_PASSWORD must enforce auth on the default user.
AUTH="${CONTAINER}-auth"
docker rm -f "$AUTH" >/dev/null 2>&1 || true
docker run -d --name "$AUTH" -e CLICKHOUSE_PASSWORD=s3cret "$IMAGE" >/dev/null
i=0; while [ "$i" -lt 60 ]; do
    docker exec "$AUTH" clickhouse-client --password s3cret --query 'SELECT 1' >/dev/null 2>&1 && break
    sleep 1; i=$((i + 1))
done
assert_eq "env password: correct password works" "1" \
    "$(docker exec "$AUTH" clickhouse-client --password s3cret --query 'SELECT 1' 2>&1)"
# Explicit empty password (no env fallback — clickhouse-client reads CLICKHOUSE_PASSWORD otherwise).
if docker exec "$AUTH" clickhouse-client --password '' --query 'SELECT 1' >/dev/null 2>&1; then
    fail "env password: wrong/empty password rejected"
else
    pass "env password: wrong/empty password rejected"
fi
docker rm -f "$AUTH" >/dev/null 2>&1 || true

check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
