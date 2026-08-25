#!/usr/bin/env bash
# Smoke test for the hardened versitygw image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-versitygw${DEV:+-dev}"

start -p 17070:7070 \
    -e ROOT_ACCESS_KEY=test -e ROOT_SECRET_KEY=testsecret "$IMAGE"
check_running
wait_http http://localhost:17070/_health 30 || true
assert_eq "health endpoint returns 200" "200" "$(http_code http://localhost:17070/_health)"
# Unsigned request to the S3 root is rejected (auth required), proving the
# gateway is serving the S3 API rather than an open endpoint. Probed with a raw
# curl (not http_code) since -f would mangle the non-2xx status.
assert_eq "unauthenticated S3 request is forbidden" "403" \
    "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:17070/)"
# From the tag rather than a literal, so a bump does not have to edit this line —
# the tag comes from melange package.version, so this still catches a build whose
# binary does not match the pin.
ver="${IMAGE##*:}"; ver="${ver%-dev}"
assert_contains "versitygw reports its version" "v${ver}" \
    "$(docker exec "$CONTAINER" /usr/bin/versitygw --version 2>&1)"
# Authenticated (SigV4) round-trip from the host: create bucket, PUT + GET an
# object, verify the body — proves the POSIX backend actually stores objects.
assert_rc0 "authenticated S3 round-trip (create/put/get)" \
    python3 "$(dirname "$0")/../../scripts/s3-roundtrip.py" \
    http://localhost:17070 test testsecret
check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi
finish
