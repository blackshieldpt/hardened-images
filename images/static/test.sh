#!/usr/bin/env bash
# Smoke test for the hardened static base. Expects $IMAGE (full tag).
#
# This image has no entrypoint and no shell, so nothing here can `docker run` it
# or `docker exec` into it. Filesystem claims are checked by exporting the
# container's rootfs and reading the tar listing from the host, which needs
# nothing whatsoever inside the image.
source "$(dirname "$0")/../../scripts/test-lib.sh"

# Rootfs listing: "<mode> <uid>/<gid> <size> <date> <path>", one line per entry.
# A dummy argv is required: the image declares no CMD and no entrypoint, and
# `docker create` refuses with "no command specified" without one. It is never
# executed -- the container is created, exported and removed, never started.
rootfs="$(docker create "$IMAGE" /nonexistent 2>/dev/null)"
[ -n "$rootfs" ] || { echo "  [FAIL] could not create a container from $IMAGE"; exit 1; }
trap 'docker rm -f "$rootfs" >/dev/null 2>&1 || true; docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT
LISTING="$(docker export "$rootfs" | tar -tvf - 2>/dev/null)"
# Last field of each entry, resolved once. For a symlink `tar -tv` prints
# "link -> target", so $NF is the target there; the checks below only ever look
# up regular files and directories, where $NF is the path.
PATHS="$(printf '%s\n' "$LISTING" | awk '{print $NF}')"

# Matching is done against a here-string rather than through a pipe on purpose.
# test-lib.sh sets `pipefail`, and `grep -q` exits at the first match, which
# SIGPIPEs whatever feeds it -- so `... | grep -q` returns non-zero *because it
# succeeded*, and a path that is present reports as absent. It is invisible on a
# short listing (the writer finishes before grep exits) and fires on a long one:
# the prod image's ~30 entries passed while the dev variant's ~990 reported its
# own CA bundle, /etc/passwd and busybox missing.

# has_path <path-without-leading-slash> -> 0 when present in the rootfs
has_path() { grep -qxF "$1" <<< "$PATHS"; }

# has_exe <name> -> 0 when an executable of that name exists anywhere on the
# standard binary paths. Matched by basename rather than one fixed path on
# purpose: /bin and /sbin are symlinks into /usr on Wolfi, so a check for
# "bin/busybox" would miss a real /usr/bin/busybox and report a clean image.
has_exe() { grep -qE "^(usr/)?s?bin/$1\$" <<< "$PATHS"; }

check_user
if [ -n "${DEV:-}" ]; then check_dev curl jq; else check_no_shell; fi

# The whole point of the image: a CA trust store and nothing to execute.
if has_path "etc/ssl/certs/ca-certificates.crt"; then
    size="$(printf '%s\n' "$LISTING" | awk '$NF=="etc/ssl/certs/ca-certificates.crt"{print $3}')"
    if [ "${size:-0}" -gt 10000 ]; then
        pass "CA bundle present and populated (${size} bytes)"
    else
        fail "CA bundle present but implausibly small (${size} bytes)"
    fi
else
    fail "CA bundle present at /etc/ssl/certs/ca-certificates.crt"
fi

# Nothing executable beyond the baselayout. Each of these would be a way to turn
# code execution in a consumer's app into something more useful.
if [ -z "${DEV:-}" ]; then
    for bin in busybox apk apk-tools go python python3 node perl wget curl ssh; do
        if has_exe "$bin"; then fail "no ${bin} binary"; else pass "no ${bin} binary"; fi
    done
fi

# The runtime account the image declares it runs as must actually exist, or
# anything resolving the UID (Go's os/user, TLS clients reading $HOME) misbehaves.
if has_path "etc/passwd"; then
    pass "/etc/passwd present"
else
    fail "/etc/passwd present"
fi

# /app pre-created and owned by the runtime user: the reason a consumer's
# `COPY --chown=65532:65532` into WORKDIR does not land root-owned.
owner="$(printf '%s\n' "$LISTING" | awk '$NF=="app/"{print $2}')"
assert_eq "/app owned by 65532:65532" "65532/65532" "${owner:-missing}"

# A floor, not a runtime. If this grows past a megabyte something was added that
# does not belong -- which is the failure this image exists to prevent.
if [ -z "${DEV:-}" ]; then
    bytes="$(docker image inspect --format '{{.Size}}' "$IMAGE")"
    if [ "$bytes" -lt 1048576 ]; then
        pass "image under 1 MiB (${bytes} bytes)"
    else
        fail "image under 1 MiB (${bytes} bytes) -- something was added to the package set"
    fi
fi

# End to end: the image's actual job is hosting a self-contained binary that can
# still verify TLS. Needs a Go toolchain on the host (GitHub runners ship one);
# skipped rather than failed where there is none, since the assertions above
# already cover the image's contents.
if command -v go >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"; docker rmi -f static-selftest:$$ >/dev/null 2>&1 || true; docker rm -f "$rootfs" >/dev/null 2>&1 || true; docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT
    cat > "$tmp/main.go" <<'EOF'
package main

import (
	"crypto/x509"
	"fmt"
	"os"
)

func main() {
	p, err := x509.SystemCertPool()
	if err != nil {
		fmt.Println("certpool error:", err)
		os.Exit(1)
	}
	fmt.Printf("uid=%d certs=%d\n", os.Getuid(), len(p.Subjects()))
}
EOF
    cat > "$tmp/go.mod" <<'EOF'
module selftest

go 1.21
EOF
    cat > "$tmp/Dockerfile" <<EOF
FROM ${IMAGE}
COPY --chown=65532:65532 selftest /app/selftest
ENTRYPOINT ["/app/selftest"]
EOF
    if (cd "$tmp" && CGO_ENABLED=0 go build -trimpath -o selftest . >/dev/null 2>&1) \
       && docker build -q -t "static-selftest:$$" "$tmp" >/dev/null 2>&1; then
        out="$(docker run --rm "static-selftest:$$" 2>&1)"
        assert_contains "static binary runs as UID 65532" "uid=65532" "$out"
        # Zero would mean the trust store is present but unreadable or unparsed --
        # the binary would then fail every outbound TLS handshake at runtime.
        if grep -qE 'certs=[1-9][0-9]*' <<< "$out"; then
            pass "system cert pool loads inside the image (${out#*certs=} certs)"
        else
            fail "system cert pool loads inside the image (got: ${out})"
        fi
    else
        fail "could not build the static self-test binary/image"
    fi
else
    log "[SKIP] end-to-end static-binary test (no go toolchain on host)"
fi

finish
