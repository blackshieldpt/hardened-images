#!/bin/sh
# Called by lego via --deploy-hook, and only when a certificate was actually
# created or renewed. lego writes the certificate and key BEFORE calling this, so
# the pair on disk is always complete by the time nginx is told to re-read it.
set -eu

state="${TLS_ACME_STATE:-/var/lib/acme}"
phase_dir="${TLS_PHASE_DIR:-/etc/nginx/phases}"
output="${NGINX_ENVSUBST_OUTPUT_DIR:-/etc/nginx/conf.d}/default.conf"

# Promote to the full config if we are still serving the bootstrap one. Idempotent:
# on a renewal we are already in phase 2 and this rewrites the same bytes.
if [ -f "$phase_dir/full.conf.template" ]; then
    defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${NGINX_ENVSUBST_FILTER:-}/ ) ? name : \"\" } }" </dev/null))
    envsubst "$defined_envs" < "$phase_dir/full.conf.template" > "$output"
    echo "acme: rendered $phase_dir/full.conf.template -> $output" >&2
fi

# Reload rather than restart: in-flight requests finish on the old workers.
#
# SIGHUP to pid 1, not `nginx -s reload`: this image starts nginx with an explicit
# -c and pid path, and a bare `nginx -s reload` would look for the defaults and
# fail. pid 1 IS the nginx master (the entrypoint execs it), and it runs as the
# same uid as this script, so signalling it is permitted.
if [ -d /proc/1 ] && kill -HUP 1 2>/dev/null; then
    echo "acme: reloaded nginx (SIGHUP to pid 1)" >&2
else
    echo "acme: WARNING could not signal pid 1; the new certificate is on disk" >&2
    echo "acme: but not yet served. Restart the container to pick it up." >&2
fi

# Record the deploy for the operator and for `docker exec ... cat`.
date -u +"%Y-%m-%dT%H:%M:%SZ deployed ${TLS_SERVER_NAME:-?}" >> "$state/deploy.log" 2>/dev/null || true
