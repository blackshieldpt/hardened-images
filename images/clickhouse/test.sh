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
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
