# Hardened ClickHouse

Wolfi-based hardened ClickHouse image, built with melange by repackaging the upstream `clickhouse-common-static` binary and version-matched configs (all SHA256-pinned), then assembled with apko.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (upstream static binary) |
| Version    | 26.1.12.23 |
| User       | clickhouse (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~602 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8123 | HTTP | HTTP |
| 9000 | TCP | native |
| 9009 | HTTP | interserver |

## Usage

```bash
docker run -d -p 8123:8123 -p 9000:9000 -v chdata:/var/lib/clickhouse hub.blackshield.pt/test_images/clickhouse:26.1.12.23
```

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

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `docker exec CONTAINER clickhouse-client --query "SELECT 1"` (or `curl -fsS 'http://HOST:8123/?query=SELECT%201'`).

## Notes

- Hardened overlay at `/etc/clickhouse-server/config.d/hardened.xml`: console logging, warning level, listen on `0.0.0.0`, data paths under `/var/lib/clickhouse`.
- `clickhouse-server`, `clickhouse-client`, and `clickhouse-local` are symlinks to the single static binary.
