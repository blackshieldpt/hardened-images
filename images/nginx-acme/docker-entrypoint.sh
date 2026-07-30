#!/bin/sh
set -e

# Derived from images/nginx/docker-entrypoint.sh: everything up to the ACME block
# below is that file verbatim. Keep them in step — test.sh fails if the shared
# template-rendering core diverges.

# Render *.template files with envsubst, then exec nginx. Mirrors the official
# nginx image's 20-envsubst-on-templates.sh: substitution is restricted to an
# explicit allowlist of env-var names (the names matching NGINX_ENVSUBST_FILTER,
# all names when it is unset), passed to `envsubst "$vars"`. This is what keeps
# nginx's own $host / $remote_addr / $proxy_add_x_forwarded_for intact — a naive
# `envsubst` would replace any $NAME that happens to be in the environment.
template_dir="${NGINX_ENVSUBST_TEMPLATE_DIR:-/etc/nginx/templates}"
suffix="${NGINX_ENVSUBST_TEMPLATE_SUFFIX:-.template}"
output_dir="${NGINX_ENVSUBST_OUTPUT_DIR:-/etc/nginx/conf.d}"

if [ -d "$template_dir" ]; then
    if [ -w "$output_dir" ]; then
        defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${NGINX_ENVSUBST_FILTER:-}/ ) ? name : \"\" } }" </dev/null))
        find "$template_dir" -follow -type f -name "*$suffix" -print | while read -r template; do
            rel="${template#"$template_dir/"}"
            out="$output_dir/${rel%"$suffix"}"
            mkdir -p "$output_dir/$(dirname "$rel")"
            echo "envsubst: $template -> $out" >&2
            envsubst "$defined_envs" < "$template" > "$out"
        done
    else
        echo "warning: $output_dir not writable; skipping template rendering" >&2
    fi
fi

# --- ACME (TLS_MODE=acme) -----------------------------------------------------
#
# Anything other than TLS_MODE=acme leaves the behaviour above and below exactly
# as it was: no phase rendering, no background process, one exec.
#
# In acme mode the certificate is this container's own responsibility. nginx
# cannot start with an `ssl_certificate` that does not exist yet — that is a fatal
# config error, not a warning — so the config is rendered in two phases:
#
#   phase 1  no certificate in the state volume: port 80 serves the ACME challenge
#            and 503s everything else. 443 is closed. Nothing pretends to be TLS.
#   phase 2  a certificate exists: the full config, with ssl_certificate pointing
#            into the state volume.
#
# acme-loop.sh obtains the certificate and, through lego's --deploy-hook, promotes
# to phase 2 and reloads. A restart with a certificate already in the volume goes
# straight to phase 2, so this only shapes the first boot.
if [ "${TLS_MODE:-}" = acme ]; then
    state="${TLS_ACME_STATE:-/var/lib/acme}"
    webroot="${TLS_ACME_WEBROOT:-/var/lib/acme/webroot}"
    phase_dir="${TLS_PHASE_DIR:-/etc/nginx/phases}"
    name="${TLS_SERVER_NAME:-}"

    export TLS_ACME_STATE="$state" TLS_ACME_WEBROOT="$webroot" TLS_PHASE_DIR="$phase_dir"

    # The webroot has to exist before nginx resolves `root` for the challenge
    # location, and before lego writes into it.
    mkdir -p "$webroot/.well-known/acme-challenge" 2>/dev/null || true

    # Where lego puts things, and therefore what the full template must read.
    # Exported so envsubst substitutes them in either phase template.
    : "${TLS_CERT_PATH:=$state/certificates/${name}.crt}"
    : "${TLS_KEY_PATH:=$state/certificates/${name}.key}"
    export TLS_CERT_PATH TLS_KEY_PATH

    phase="$phase_dir/bootstrap.conf.template"
    if [ -s "$TLS_CERT_PATH" ] && [ -s "$TLS_KEY_PATH" ]; then
        phase="$phase_dir/full.conf.template"
    fi

    if [ -w "$output_dir" ] && [ -f "$phase" ]; then
        # Same substitution rule as the template loop above, so nginx's own
        # $host / $uri survive being rendered.
        defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${NGINX_ENVSUBST_FILTER:-}/ ) ? name : \"\" } }" </dev/null))
        envsubst "$defined_envs" < "$phase" > "$output_dir/default.conf"
        echo "acme: phase $(basename "$phase") -> $output_dir/default.conf" >&2
    else
        echo "acme: cannot render $phase into $output_dir; leaving the config alone" >&2
    fi

    # Backgrounded before the exec, so nginx keeps pid 1 and `kill -s HUP 1`
    # still reloads it. The loop is reparented to nginx, which reaps unknown
    # children through its SIGCHLD handler, so it leaves no zombie behind.
    /usr/local/bin/acme-loop.sh &
fi

# -c our config (nginx-mainline owns the default /etc/nginx/nginx.conf); keep the
# pid under /run/nginx where the non-root user can write.
exec nginx -c /etc/nginx/nginx-hardened.conf -g "daemon off; pid /run/nginx/nginx.pid;" "$@"
