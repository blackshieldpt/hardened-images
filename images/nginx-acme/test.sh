#!/usr/bin/env bash
# Smoke test for the hardened nginx image. Expects $IMAGE (full tag).
source "$(dirname "$0")/../../scripts/test-lib.sh"
CONTAINER="hardened-test-nginx-acme${DEV:+-dev}"

# --- drift against images/nginx ------------------------------------------------
# This image is images/nginx plus a certificate client, which means copies, which
# means drift. These run first because they are the cheapest failure to fix and
# the easiest to cause: a fix to nginx's config or entrypoint that nobody carried
# across would otherwise be invisible until someone compared the two by hand.
SRC="$(dirname "$0")"
NGX="$SRC/../nginx"

for f in nginx-hardened.conf templates/default.conf.template; do
    if [ -f "$NGX/$f" ] && [ -f "$SRC/$f" ] && cmp -s "$NGX/$f" "$SRC/$f"; then
        pass "drift: $f matches images/nginx"
    else
        fail "drift: $f differs from images/nginx (copy it across, or explain why not)"
    fi
done

# The entrypoints cannot be identical — this one has the ACME block — but the
# rendering core they share must be. That awk line is the whole envsubst
# allowlist mechanism; if nginx's changes and this one does not, templates render
# differently in the two images for no visible reason.
core='defined_envs=$(printf'
if grep -qF "$core" "$NGX/docker-entrypoint.sh" && grep -qF "$core" "$SRC/docker-entrypoint.sh"; then
    pass "drift: entrypoints share the envsubst core"
else
    fail "drift: the envsubst core differs between images/nginx and images/nginx-acme"
fi

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

# --- ACME (TLS_MODE=acme) -----------------------------------------------------
# No CA is contacted here: issuance needs a publicly reachable name, which a smoke
# test does not have. What is asserted is everything up to the CA — the phase-1
# config, the challenge path, the tooling the loop depends on, and that nginx is
# still pid 1 — because those are what break silently.
ACME="${CONTAINER}-acme"
docker rm -f "$ACME" >/dev/null 2>&1 || true
docker run -d --name "$ACME" -p 18081:8080 \
    -e TLS_MODE=acme \
    -e TLS_SERVER_NAME=acme-test.invalid \
    -e TLS_ACME_EMAIL=test@example.invalid \
    -e NGINX_ENVSUBST_FILTER='^(TLS_|NGINX_)' \
    "$IMAGE" >/dev/null
sleep 5

# Phase 1: it starts at all. nginx treats a missing ssl_certificate as fatal, so
# a container that renders the full config with no certificate never comes up.
assert_eq "acme: container is running in phase 1" "true" \
    "$(docker inspect -f '{{.State.Running}}' "$ACME" 2>/dev/null)"

# The challenge path is served rather than redirected. If this ever regresses,
# the FIRST issuance still succeeds and renewal fails ~60 days later, quietly.
docker exec "$ACME" sh -c 'mkdir -p /var/lib/acme/webroot/.well-known/acme-challenge &&
    echo smoke-token > /var/lib/acme/webroot/.well-known/acme-challenge/probe' 2>/dev/null
assert_eq "acme: challenge file is served on :80" "smoke-token" \
    "$(curl -fsS http://localhost:18081/.well-known/acme-challenge/probe 2>/dev/null)"
# Not http_code(): that helper uses `curl -f`, which exits non-zero on a 503 and
# appends its own "000" fallback, so an expected error code reads as "503000".
assert_eq "acme: everything else is 503, not a redirect" "503" \
    "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18081/ 2>/dev/null)"

# Phase 1 must not pretend to be TLS: no ssl_* directives at all, and no
# listener on 8443. Either would mean nginx failed to start, or worse, started
# serving something it should not have.
# Anchored to the start of a line so the template's own comment — which explains
# why there is no ssl_certificate here — is not mistaken for a directive.
assert_eq "acme: phase 1 renders no ssl_certificate directive" "0" \
    "$(docker exec "$ACME" sh -c 'grep -cE "^[[:space:]]*ssl_certificate" /etc/nginx/conf.d/default.conf 2>/dev/null || true')"
assert_eq "acme: phase 1 does not listen on 8443" "0" \
    "$(docker exec "$ACME" sh -c 'netstat -lnt 2>/dev/null | grep -c ":8443[[:space:]]" || true')"

# The tooling the loop actually uses. busybox here has no nc and no wget, so the
# readiness probe uses netstat; assert the applet exists so that cannot rot.
assert_rc0 "acme: lego runs" docker exec "$ACME" lego --version
assert_rc0 "acme: netstat exists for the readiness probe" \
    docker exec "$ACME" sh -c 'netstat -lnt >/dev/null 2>&1'
assert_contains "acme: lego is on the expected version" "5\.3\.1" \
    "$(docker exec "$ACME" lego --version 2>&1)"

# lego 5.x scopes these flags to the `run` command. The loop used to invoke
# `lego --accept-tos ... run`, which left nginx healthy and the loop alive but
# made every issuance/renewal fail in the CLI parser before contacting the CA.
# Assert both that the complete option set parses and that the actual background
# attempt did not take that path.
assert_rc0 "acme: issuance flags are valid after the run command" \
    docker exec "$ACME" lego run \
        --accept-tos \
        --email test@example.invalid \
        --domains acme-test.invalid \
        --path /var/lib/acme \
        --http --http.webroot /var/lib/acme/webroot \
        --no-random-sleep \
        --deploy-hook /usr/local/bin/acme-deploy.sh \
        --help
assert_eq "acme: renewal loop reaches lego without a flag-scope error" "0" \
    "$(docker logs "$ACME" 2>&1 | grep -c 'flag provided but not defined' || true)"

# nginx must remain pid 1: SIGHUP to pid 1 is how the deploy hook reloads after a
# renewal, and `docker kill -s HUP` is the documented operator command.
assert_contains "acme: nginx is pid 1" "nginx" \
    "$(docker exec "$ACME" sh -c 'cat /proc/1/comm 2>/dev/null')"
assert_contains "acme: the renewal loop is running" "acme-loop" \
    "$(docker exec "$ACME" sh -c 'ps -o args 2>/dev/null | tr "\n" " "')"

# A reload must not kill the container — this is what a renewal does.
docker kill -s HUP "$ACME" >/dev/null 2>&1; sleep 2
assert_eq "acme: survives SIGHUP (what a renewal triggers)" "true" \
    "$(docker inspect -f '{{.State.Running}}' "$ACME" 2>/dev/null)"

# The state directory must be writable by the run-as user, or lego cannot store
# an account key. This is the failure a root-owned named volume produces.
assert_rc0 "acme: state directory is writable by uid 65532" \
    docker exec "$ACME" sh -c 'touch /var/lib/acme/.writable && rm /var/lib/acme/.writable'

# Rate-limit guard: a restart must not mean another CA attempt.
assert_rc0 "acme: an attempt is recorded for the retry guard" \
    docker exec "$ACME" sh -c 'test -f /var/lib/acme/.last-attempt'

docker rm -f "$ACME" >/dev/null 2>&1 || true

# Without TLS_MODE=acme nothing above happens: no loop, no phase rendering.
PLAIN="${CONTAINER}-plain"
docker rm -f "$PLAIN" >/dev/null 2>&1 || true
docker run -d --name "$PLAIN" "$IMAGE" >/dev/null; sleep 3
assert_eq "no acme loop when TLS_MODE is unset" "0" \
    "$(docker exec "$PLAIN" sh -c 'ps -o args 2>/dev/null | grep -c "[a]cme-loop" || true')"
docker rm -f "$PLAIN" >/dev/null 2>&1 || true

[ -n "${DEV:-}" ] && check_dev curl openssl
finish
