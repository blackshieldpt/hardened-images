# Hardened nginx

Wolfi-based hardened nginx image, assembled with apko from the Wolfi
`nginx-mainline` package, with a small entrypoint shipped via a melange package for
runtime config templating.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi nginx-mainline) + melange (entrypoint) |
| Version    | 1.31 |
| User       | nginx (UID 65532) |
| Shell      | busybox (env-var entrypoint) |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 80   | HTTP     | HTTP |

## Usage

By default the image serves the nginx welcome page on `:80`. To configure it per
environment without rebuilding, mount `*.template` files and supply values via
environment variables — the entrypoint renders them into `conf.d` on start.

```bash
# one immutable image, upstream supplied at deploy time
mkdir -p t && cat > t/default.conf.template <<'CONF'
server {
  listen 8080;
  location /api/ { set $u ${API_UPSTREAM}; proxy_pass http://$u; }
}
CONF
docker run -d -p 8080:8080 \
  -e API_UPSTREAM=backend:5000 -e NGINX_ENVSUBST_FILTER='^API_' \
  -v "$PWD/t:/etc/nginx/templates:ro" \
  hub.blackshield.pt/test_images/nginx:1.31
```

### Environment variables

Mirrors the official `nginx` image's `envsubst` template contract. With **no**
templates present, behavior is unchanged (serves the default welcome page).

| Variable | Default | Meaning |
|----------|---------|---------|
| `NGINX_ENVSUBST_TEMPLATE_DIR` | `/etc/nginx/templates` | Directory scanned for templates. |
| `NGINX_ENVSUBST_TEMPLATE_SUFFIX` | `.template` | Files matching `*<suffix>` are rendered. |
| `NGINX_ENVSUBST_OUTPUT_DIR` | `/etc/nginx/conf.d` | Rendered output dir (suffix stripped). |
| `NGINX_ENVSUBST_FILTER` | _(unset = all)_ | ERE matched against env-var **names**; only matching names are substituted. |

**Use `NGINX_ENVSUBST_FILTER`.** Substitution uses an explicit allowlist so
nginx's own `$host` / `$remote_addr` / `$proxy_add_x_forwarded_for` are never
touched, but setting a filter (e.g. `^API_`) and naming your placeholders
`${API_...}` avoids any collision with unrelated environment variables.

Notes:
- The bind-mounted template dir must be readable by UID 65532 (world-readable, e.g. `chmod 755`).
- Templates render into `conf.d`, which the hardened config (`/etc/nginx/nginx-hardened.conf`, run via `nginx -c`) includes. `nginx-mainline`'s default `/etc/nginx/nginx.conf` is left untouched.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and
curl + openssl. For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/nginx:latest-dev
```

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `curl -fsS http://HOST/`.
