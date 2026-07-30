# Hardened nginx with ACME

The [`nginx`](../nginx/README.md) image plus [lego](https://github.com/go-acme/lego):
it obtains its own TLS certificate from an ACME CA and keeps it renewed. Same Wolfi
base, same `nginx-mainline`, same non-root uid, same envsubst templating.

**Use [`nginx`](../nginx/README.md) instead if you terminate TLS elsewhere.** lego
is ~40 MB and brings 206 Go modules into the SBOM and the vulnerability scan; this
image exists so that cost falls only on the deployments that want it. Everything
the plain image does, this one does identically — with `TLS_MODE` unset it *is* the
plain image, and its own smoke test asserts the shared config files have not
drifted apart.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi nginx-mainline) + melange (entrypoint, lego) |
| Image      | `ghcr.io/blackshieldpt/nginx-acme` |
| Version    | 1.31 |
| User       | nginx (UID 65532) |
| Shell      | busybox (env-var entrypoint) |
| ACME       | lego 5.3.1, built from source — opt in with `TLS_MODE=acme` |
| Scanning   | lego contributes 206 Go modules; grype reads them from the binary and gates on them. trivy's language scanners do not see inside a static Go binary, so grype is the only cover there |

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
  ghcr.io/blackshieldpt/nginx-acme:1.31
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

## Automatic TLS certificates (`TLS_MODE=acme`)

Set `TLS_MODE=acme` and the image obtains its own certificate from an ACME CA and
keeps it renewed. Nothing else is involved: no certbot on the host, no companion
container, no hook scripts, no cron, and no downtime for a renewal.

It works because this container already owns port 80, which is the hard part of
HTTP-01. Every external ACME setup has to either take that port away from nginx or
coordinate with it.

```bash
docker volume create acme-state
docker run -d --name edge -p 80:8080 -p 443:8443 \
  -e TLS_MODE=acme \
  -e TLS_SERVER_NAME=edge.example.com \
  -e TLS_ACME_EMAIL=admin@example.com \
  -e NGINX_ENVSUBST_FILTER='^(TLS_|NGINX_)' \
  -v acme-state:/var/lib/acme \
  ghcr.io/blackshieldpt/nginx-acme:1.31
```

`TLS_SERVER_NAME` must be a public name that resolves to this host, and port 80
must be reachable from the internet. **Mount a volume at `/var/lib/acme`** — it
holds the account key and the certificate, and without it every restart is a fresh
issuance against a CA that allows five duplicates a week.

### How it starts: two phases

nginx treats an `ssl_certificate` pointing at a missing file as a **fatal**
configuration error, so it cannot start in order to answer the challenge that
produces its first certificate. Rather than ship a self-signed placeholder — a
known private key in a public image, briefly served to real clients — the config
is rendered in two phases:

| | Config | `:80` | `:443` |
|---|---|---|---|
| **Phase 1**, no certificate yet | `phases/bootstrap.conf.template` | serves the ACME challenge, `503` otherwise | closed |
| **Phase 2**, certificate present | `phases/full.conf.template` | challenge, then `301` to HTTPS | serves TLS |

Promotion happens the moment the certificate arrives, via `SIGHUP` — no restart,
no dropped connections. A restart with a certificate already in the volume goes
straight to phase 2, so this only shapes the first boot. A client arriving
mid-issuance gets a `503` rather than a certificate warning it learns to click
through.

### Renewal

`lego run` decides for itself whether anything is due: it renews when a third of
the certificate's lifetime remains, or earlier if the CA's RFC 9773 `renewalInfo`
endpoint says so — which is how a mass-revocation event reaches an install with
nobody touching it. The loop wakes hourly and asks; ~1400 of those a year are
no-ops, which is what makes polling cheap and means there is no renewal date of
our own to get wrong.

Each renewal writes a **new private key** (`--reuse-key` is deliberately not
passed) and reloads nginx through lego's `--deploy-hook`. Renewal failures are not
urgent by design: with renewal starting 30 days out and hourly retries, roughly
720 attempts happen before anything is user-visible — so watch the logs, or watch
the served certificate's expiry, rather than trusting silence.

### Overriding the config

Mount your own over either phase template — `/etc/nginx/phases/full.conf.template`
is the one that matters. Two things must survive any override:

- **`ssl_certificate ${TLS_CERT_PATH}`.** In acme mode that points into the state
  volume where lego writes. Hardcoding a path breaks acme mode, and copying lego's
  output onto a bind-mounted *file* breaks renewals: replacing a bind-mounted file
  changes its inode, and the container keeps serving the old certificate even
  after a reload.
- **The `acme-challenge` location, ahead of any redirect.** Phase 1 answers the
  *first* challenge, so issuance succeeds without it and the failure appears ~60
  days later when a renewal challenge gets redirected and 404s — with every
  container healthy and every log quiet. It costs nothing when unused.

### ACME environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `TLS_MODE` | _(unset)_ | `acme` turns all of this on. Any other value leaves the image exactly as it was. |
| `TLS_SERVER_NAME` | _(required)_ | The public hostname. `_` is refused — no CA issues for it. |
| `TLS_ACME_EMAIL` | _(required)_ | CA account contact, for expiry warnings. |
| `TLS_ACME_SERVER` | Let's Encrypt production | Directory URL. Point it at `letsencrypt-staging` while testing, or at your own `step-ca` for internal names. |
| `TLS_ACME_STATE` | `/var/lib/acme` | Account key, certificates, archive. Mount a volume here. |
| `TLS_ACME_WEBROOT` | `/var/lib/acme/webroot` | Where the challenge file is written and served from. |
| `TLS_ACME_POLL_INTERVAL` | `3600` | Seconds between "is anything due?" checks. |
| `TLS_ACME_MIN_RETRY` | `300` | Minimum seconds between CA attempts, across restarts. Stops a crash-looping container from burning the failed-validation limit. |
| `TLS_CERT_PATH` / `TLS_KEY_PATH` | under `TLS_ACME_STATE` | Where the templates read the pair from. Set them for a non-acme mode. |

Requires a name a CA will issue for. `.local`, `.internal` and `.home.arpa` are
not those — use `TLS_ACME_SERVER` with an internal ACME CA such as
[`step-ca`](https://smallstep.com/docs/step-ca/), or supply a certificate
yourself and leave `TLS_MODE` unset.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and
curl + openssl. For interactive use:

```bash
docker run -it --entrypoint /bin/sh ghcr.io/blackshieldpt/nginx-acme:latest-dev
```

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `curl -fsS http://HOST/`.

In `TLS_MODE=acme`, a phase-1 edge answers `:80` with `503` — deliberately, since
it has no certificate yet. Treat `503` on `/` plus a `200` on
`/.well-known/acme-challenge/...` as "starting", not "broken", and alert on it only
if it persists beyond a few minutes.
