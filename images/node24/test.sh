#!/usr/bin/env bash
# Smoke test for the hardened node24 image. Expects $IMAGE (full tag).
# npm ships as JS launched via node (its #!/usr/bin/env node shebang cannot
# self-exec without a shell), so npm is invoked through the node entrypoint.
source "$(dirname "$0")/../../scripts/test-lib.sh"

assert_eq "node executes JS" "node-ok" "$(docker run --rm "$IMAGE" -e "process.stdout.write('node-ok')" 2>&1)"
assert_contains "node v24" "^v24\." "$(docker run --rm "$IMAGE" --version 2>&1)"
assert_eq "runs as UID 65532" "65532" "$(docker run --rm "$IMAGE" -e "process.stdout.write(String(process.getuid()))" 2>&1)"
assert_contains "npm available via node" "^[0-9]+\." "$(docker run --rm --entrypoint node "$IMAGE" /usr/bin/npm --version 2>&1)"
check_user
if [ -n "${DEV:-}" ]; then check_dev gcc git; else check_no_shell; fi
finish
