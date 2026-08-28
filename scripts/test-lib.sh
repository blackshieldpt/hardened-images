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

# Matched from a here-string, not through a pipe: this file sets `pipefail`, and
# `grep -q` exits at the first match, SIGPIPEing its writer -- so `printf | grep -q`
# returns non-zero *because the pattern matched*, and a passing assertion reports
# as a failure. It only shows up once the haystack is long enough that the writer
# is still going when grep exits, so it hides on short output and fires on long.
assert_contains() {
    if grep -qE "$2" <<< "$3"; then pass "$1"; else fail "$1 (pattern='$2' not found)"; fi
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

# _has_shell <path> — true when the image can execute <path>.
_has_shell() { docker run --rm --entrypoint "$1" "$IMAGE" -c 'exit 0' >/dev/null 2>&1; }

# check_no_shell — assert the image ships no shell at all.
# Checks bash as well as sh: this used to test /bin/sh alone, which passed happily
# on an image carrying /bin/bash and reported it as "shell-less". An attacker with
# code execution does not care which shell it is.
check_no_shell() {
    local found=""
    _has_shell /bin/sh   && found="/bin/sh"
    _has_shell /bin/bash && found="${found:+$found }/bin/bash"
    if [ -n "$found" ]; then
        fail "image is shell-less (found: ${found})"
    else
        pass "image is shell-less (no /bin/sh, no /bin/bash)"
    fi
}

# check_no_sh_but_bash <why> — for images where a Wolfi package hard-depends on
# bash and it therefore cannot be removed. Asserts the weaker property that is
# actually true, and states the reason, rather than letting check_no_shell pass on
# the technicality that /bin/sh happens to be absent.
check_no_sh_but_bash() {
    if _has_shell /bin/sh; then
        fail "no /bin/sh (bash is expected here: $1)"
    else
        pass "no /bin/sh (bash present and unavoidable: $1)"
    fi
    if _has_shell /bin/bash; then
        pass "bash present as documented ($1)"
    else
        # Upstream dropped the dependency — tighten this image back to check_no_shell.
        fail "bash unexpectedly absent — switch this image to check_no_shell"
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
