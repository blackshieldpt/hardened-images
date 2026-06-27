#!/usr/bin/env bash
# Smoke test for the hardened python image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"

assert_eq "python executes code" "python-ok" "$(docker run --rm "$IMAGE" -c "print('python-ok')" 2>&1)"
assert_contains "python 3.14" "3\.14" "$(docker run --rm "$IMAGE" --version 2>&1)"
assert_eq "runs as UID 65532" "65532" "$(docker run --rm "$IMAGE" -c 'import os; print(os.getuid())' 2>&1)"
assert_rc0 "pip available" docker run --rm --entrypoint pip3.14 "$IMAGE" --version
check_user
if [ -n "${DEV:-}" ]; then check_dev gcc git; else check_no_shell; fi
finish
