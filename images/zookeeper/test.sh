#!/usr/bin/env bash
# Smoke test for the hardened zookeeper image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-zookeeper${DEV:+-dev}"
ZK=/usr/share/java/zookeeper/bin
LIB=/usr/share/java/zookeeper/lib
VER="${IMAGE##*:}"; VER="${VER%-dev}"

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

# The tag now comes from melange package.version, so the server has to agree with
# it — same guard as the build-time assertion, checked against what actually ran.
# assert_contains is grep -qE, so escape the dots — otherwise 3x9y5 would pass the
# one assertion whose whole job is checking the version.
assert_contains "server reports version ${VER}" "version ${VER//./\\.}" \
    "$(docker exec "$CONTAINER" "$ZK/zkServer.sh" version 2>&1)"

# This image exists to carry patched bundled jars. If a rebuild silently reverts to
# upstream's pinned versions, the CVEs come back with no other visible signal.
for jar in netty-codec-4.1.136.Final jackson-databind-2.18.9 logback-core-1.5.37; do
    assert_rc0 "patched jar present: ${jar}" \
        docker exec "$CONTAINER" test -f "${LIB}/${jar}.jar"
done
# Jetty 9.4 has no obtainable fix, so it is removed rather than waived. Counted
# rather than `! ls`, which would also pass if ls itself were missing.
assert_eq "no jetty jars shipped" "0" \
    "$(docker exec "$CONTAINER" sh -c "ls ${LIB} | grep -c jetty || true")"

# Shell posture: zkServer.sh/zkEnv.sh are bash scripts and busybox provides
# /bin/sh, so this image ships both. Asserted rather than assumed, so the README's
# claim cannot rot.
assert_rc0 "bash present (zkServer.sh and zkEnv.sh are bash scripts)" \
    docker run --rm --entrypoint /bin/bash "$IMAGE" -c 'exit 0'
assert_rc0 "sh present (busybox)" \
    docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'exit 0'

check_user
[ -n "${DEV:-}" ] && check_dev curl jq
finish
