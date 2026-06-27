#!/usr/bin/env bash
# Smoke test for the hardened go image. Expects $IMAGE (full tag).
# go-1.26 depends on bash, so no shell-less assertion.
source "$(dirname "$0")/../../scripts/test-lib.sh"

assert_contains "go 1.26" "1\.26" "$(docker run --rm "$IMAGE" version 2>&1)"

# The image runs as UID 65532, so the bind-mounted dir must be world-writable.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp" 2>/dev/null; docker run --rm -v "$tmp:/app" --entrypoint /bin/sh "$IMAGE" -c "rm -rf /app/*" >/dev/null 2>&1 || true' EXIT
chmod 777 "$tmp"

cat > "$tmp/main.go" <<'EOF'
package main

func main() {}
EOF
chmod 644 "$tmp/main.go"

cat > "$tmp/go.mod" <<'EOF'
module test

go 1.26
EOF
chmod 644 "$tmp/go.mod"

assert_rc0 "go build" docker run --rm -v "$tmp:/app" -w /app "$IMAGE" build -o /tmp/out .

cat > "$tmp/uid.go" <<'EOF'
package main

import (
	"fmt"
	"os"
)

func main() { fmt.Print(os.Getuid()) }
EOF
chmod 644 "$tmp/uid.go"

assert_eq "runs as UID 65532" "65532" "$(docker run --rm -v "$tmp:/app" -w /app "$IMAGE" run uid.go 2>&1 | tr -d '\r\n')"
check_user
[ -n "${DEV:-}" ] && check_dev gcc git
finish
