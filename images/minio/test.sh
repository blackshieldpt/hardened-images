#!/usr/bin/env bash
# Smoke test for the hardened minio image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-minio${DEV:+-dev}"

start -p 19000:9000 -p 19001:9001 \
    -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin "$IMAGE"
check_running
wait_http http://localhost:19000/minio/health/live 30 || true
assert_eq "liveness returns 200" "200" "$(http_code http://localhost:19000/minio/health/live)"
assert_eq "cluster health returns 200" "200" "$(http_code http://localhost:19000/minio/health/cluster)"
assert_contains "mc client present" "version" "$(docker exec "$CONTAINER" mc --version 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
