# Hardened ClickHouse

Wolfi-based hardened ClickHouse image, built with melange by repackaging the upstream `clickhouse-common-static` binary and version-matched configs (all SHA256-pinned), then assembled with apko.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (upstream static binary) + entrypoint |
| Version    | 26.7.1.1315 |
| User       | clickhouse (UID 65532) |
| Shell      | busybox (env-var entrypoint) |
| Image size | ~602 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8123 | HTTP | HTTP |
| 9000 | TCP | native |
| 9009 | HTTP | interserver |

## Usage

```bash
docker run -d -p 8123:8123 -p 9000:9000 \
  -e CLICKHOUSE_PASSWORD=secret -v chdata:/var/lib/clickhouse \
  hub.blackshield.pt/test_images/clickhouse:26.7.1.1315
```

### Environment variables

The entrypoint honors the same user/password contract as the official image,
generating `/etc/clickhouse-server/users.d/00-env.xml` on each boot (stateless;
the password is stored hashed as `password_sha256_hex`). With **no** `CLICKHOUSE_*`
vars set, behavior is unchanged (stock `default` user, no password).

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_USER` | `default` | User to configure. |
| `CLICKHOUSE_PASSWORD` | unset | Password for that user (stored hashed). |
| `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT` | `0` | `1` grants the user access/named-collection management. |
| `CLICKHOUSE_SKIP_USER_SETUP` | `0` | `1` skips all of the above (stock defaults). |

Database creation (`CLICKHOUSE_DB`) and `/docker-entrypoint-initdb.d/` are **not**
handled — create databases from your application (`CREATE DATABASE IF NOT EXISTS`).

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/clickhouse:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/clickhouse | Data directory |

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `docker exec CONTAINER clickhouse-client --query "SELECT 1"` (or `curl -fsS 'http://HOST:8123/?query=SELECT%201'`). When `CLICKHOUSE_PASSWORD` is set, the probe must authenticate — `clickhouse-client` reads `CLICKHOUSE_PASSWORD` from the env, or pass `--password`.

## Notes

- Hardened overlay at `/etc/clickhouse-server/config.d/hardened.xml`: console logging, warning level, listen on `0.0.0.0`, data paths under `/var/lib/clickhouse`.
- `clickhouse-server`, `clickhouse-client`, and `clickhouse-local` are symlinks to the single static binary.
- Keeps `busybox`: the entrypoint (`/usr/local/bin/entrypoint.sh`) generates the user/password `users.d` override from `CLICKHOUSE_*` before exec'ing the server.
