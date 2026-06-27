# Shared smoke-test helpers for apko/melange images.
# Sourced by images/<name>/test.sh, which must export IMAGE (full tag).
# Shell-less aware: readiness is probed from the host (curl) or via client
# binaries that actually ship in the image; HEALTHCHECK is not used (apko
# images carry none) and `id`/`wget` are not assumed inside the container.
set -uo pipefail

: "${IMAGE:?IMAGE must be set (full image tag)}"
PASSED=0
FAILED=0
CONTAINER="${CONTAINER:-hardened-test-$$}"

_cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap _cleanup EXIT

log()  { echo "  $*"; }
pass() { PASSED=$((PASSED + 1)); log "[PASS] $1"; }
fail() { FAILED=$((FAILED + 1)); log "[FAIL] $1"; }

assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected='$2' actual='$3')"; fi
}

assert_contains() {
    if printf '%s' "$3" | grep -qE "$2"; then pass "$1"; else fail "$1 (pattern='$2' not found)"; fi
}

assert_rc0() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc (rc=$?)"; fi
}

# start <docker run args...> <IMAGE> [cmd...]  — launch detached as $CONTAINER
start() {
    docker run -d --name "$CONTAINER" "$@" >/dev/null
}

http_code() { curl -fsS -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }

# wait_http <url> [timeout-seconds]
wait_http() {
    local url="$1" t="${2:-60}" i=0
    while [ "$i" -lt "$t" ]; do
        curl -fsS "$url" >/dev/null 2>&1 && return 0
        sleep 1; i=$((i + 1))
    done
    return 1
}

# wait_exec <timeout-seconds> <cmd...>  — poll `docker exec $CONTAINER cmd`
wait_exec() {
    local t="$1"; shift; local i=0
    while [ "$i" -lt "$t" ]; do
        docker exec "$CONTAINER" "$@" >/dev/null 2>&1 && return 0
        sleep 1; i=$((i + 1))
    done
    return 1
}

check_running() {
    assert_eq "container is running" "running" \
        "$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"
}

check_user() {
    assert_eq "image configured to run as UID 65532" "65532" \
        "$(docker inspect --format '{{.Config.User}}' "$IMAGE")"
}

# check_no_shell — assert the image has no /bin/sh (true distroless).
check_no_shell() {
    if docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'exit 0' >/dev/null 2>&1; then
        fail "image is shell-less (no /bin/sh)"
    else
        pass "image is shell-less (no /bin/sh)"
    fi
}

# check_dev <tools...> — assert the dev variant ships a shell + base tooling + given tools.
check_dev() {
    assert_rc0 "dev: /bin/sh present" docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'exit 0'
    local t
    for t in bash apk wget "$@"; do
        assert_rc0 "dev: ${t} on PATH" \
            docker run --rm --entrypoint /bin/sh "$IMAGE" -c "export PATH=\$PATH:/usr/sbin:/sbin; command -v ${t} >/dev/null"
    done
}

finish() {
    echo ""
    if [ "$FAILED" -gt 0 ]; then
        echo "==> FAILED: $FAILED, PASSED: $PASSED"
        exit 1
    fi
    echo "==> ALL PASSED ($PASSED assertions)"
}
