# Hardened MinIO

Wolfi-based hardened MinIO image, assembled with apko from the Wolfi `minio` package (S3-compatible object storage), with the `mc` client included.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi minio, mc) |
| Version    | 0.20260604.005411 (Wolfi package version; upstream `RELEASE.2026-06-04T00-54-11Z`) |
| User       | minio (UID 65532) |
| Shell      | none (distroless) |
| License    | AGPL-3.0-or-later |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9000 | HTTP | S3 API |
| 9001 | HTTP | web console |

## Usage

```bash
docker run -d -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  -v $(pwd)/data:/data \
  hub.blackshield.pt/test_images/minio:0.20260604.005411
```

The default command is `server /data --console-address :9001`. Override it to change
the data path or flags:

```bash
docker run --rm hub.blackshield.pt/test_images/minio:latest server /export --address :9000
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/minio:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /data | object storage backend |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `curl -fsS http://HOST:9000/minio/health/live`.

## Notes

- Entrypoint is `/usr/bin/minio`; workdir `/data`.
- Set `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` — without them MinIO falls back to
  the well-known `minioadmin` / `minioadmin` defaults.
- The `mc` client ships in the image; invoke it via `docker exec … mc …` (prod is
  shell-less, so configure aliases through env/flags rather than an interactive shell).
- Version is the Wolfi package date-string, not a semver line like the other images.
