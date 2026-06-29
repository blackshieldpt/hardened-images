#!/usr/bin/env bash
# Smoke test for the hardened python-sodium image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"

PY=(docker run --rm --entrypoint /usr/bin/python3.14 "$IMAGE")

assert_eq "python executes code" "python-ok" "$("${PY[@]}" -c "print('python-ok')" 2>&1)"
assert_contains "python 3.14" "3\.14" "$("${PY[@]}" --version 2>&1)"
assert_eq "runs as UID 65532" "65532" "$("${PY[@]}" -c 'import os; print(os.getuid())' 2>&1)"
assert_eq "HOME is writable /tmp" "/tmp" "$("${PY[@]}" -c 'import os; print(os.environ["HOME"])' 2>&1)"
assert_rc0 "pip available" docker run --rm --entrypoint pip3.14 "$IMAGE" --version

# No default entrypoint: the downstream image / run command supplies the CMD.
assert_eq "no default entrypoint" "[]" \
    "$(docker inspect --format '{{.Config.Entrypoint}}' "$IMAGE")"

# ctypes.util.find_library must resolve the bundled system libs (needs the
# ld.so.cache apko generates + the ldconfig fallback binary).
assert_contains "find_library(sodium)" "libsodium\.so" \
    "$("${PY[@]}" -c 'import ctypes.util as u; print(u.find_library("sodium"))' 2>&1)"
assert_contains "find_library(magic)" "libmagic\.so" \
    "$("${PY[@]}" -c 'import ctypes.util as u; print(u.find_library("magic"))' 2>&1)"
assert_eq "ld.so.cache present" "True" \
    "$("${PY[@]}" -c 'import os; print(os.path.exists("/etc/ld.so.cache"))' 2>&1)"
assert_eq "ldconfig binary present" "True" \
    "$("${PY[@]}" -c 'import os; print(os.path.exists("/sbin/ldconfig"))' 2>&1)"

check_user
if [ -n "${DEV:-}" ]; then check_dev gcc git; else check_no_shell; fi
finish
