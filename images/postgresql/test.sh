#!/usr/bin/env bash
# Smoke test for the hardened postgresql image. Expects $IMAGE (full tag).
# postgresql intentionally ships busybox (the POSTGRES_PASSWORD/initdb.d
# entrypoint is a /bin/sh script), so no shell-less assertion here.
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-postgresql${DEV:+-dev}"

start -p 15432:5432 -e POSTGRES_PASSWORD=testpass "$IMAGE"
check_running
wait_exec 40 pg_isready -U postgres || true
assert_eq "SQL query returns 1" "1" "$(docker exec "$CONTAINER" psql -U postgres -tAc 'SELECT 1' 2>&1)"
assert_contains "PostgreSQL 18" "^18\." "$(docker exec "$CONTAINER" psql -U postgres -tAc 'SHOW server_version' 2>&1)"
assert_eq "runs as UID 65532" "65532" "$(docker exec "$CONTAINER" id -u 2>&1)"
check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
