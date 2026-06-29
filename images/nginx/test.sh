#!/usr/bin/env bash
# Smoke test for the hardened nginx image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-nginx${DEV:+-dev}"

start -p 18080:80 "$IMAGE"
check_running
wait_http http://localhost:18080/ 30 || true
assert_eq "serves HTTP 200" "200" "$(http_code http://localhost:18080/)"

# Runtime env-templating: a mounted *.template + env var renders into conf.d,
# substituting only the filtered var while nginx's own $vars survive.
TPL="$(mktemp -d)"
cat > "$TPL/site.conf.template" <<'CONF'
server {
  listen 8081;
  location /api/ { set $u ${API_UPSTREAM}; proxy_pass http://$u; }
}
CONF
chmod 755 "$TPL"; chmod 644 "$TPL/site.conf.template"  # readable by non-root container user
TMPL="${CONTAINER}-tmpl"
docker rm -f "$TMPL" >/dev/null 2>&1 || true
docker run -d --name "$TMPL" -e API_UPSTREAM=backend:5000 -e NGINX_ENVSUBST_FILTER='^API_' \
    -v "$TPL:/etc/nginx/templates:ro" "$IMAGE" >/dev/null
sleep 3
rendered="$(docker exec "$TMPL" cat /etc/nginx/conf.d/site.conf 2>&1)"
assert_contains "template: API_UPSTREAM substituted" "backend:5000" "$rendered"
assert_contains "template: nginx \$u preserved" 'proxy_pass http://\$u' "$rendered"
docker rm -f "$TMPL" >/dev/null 2>&1 || true
rm -rf "$TPL"

check_user
[ -n "${DEV:-}" ] && check_dev curl openssl
finish
