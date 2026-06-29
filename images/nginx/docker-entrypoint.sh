#!/bin/sh
set -e

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

# -c our config (nginx-stable owns the default /etc/nginx/nginx.conf); keep the
# pid under /run/nginx where the non-root user can write.
exec nginx -c /etc/nginx/nginx-hardened.conf -g "daemon off; pid /run/nginx/nginx.pid;" "$@"
