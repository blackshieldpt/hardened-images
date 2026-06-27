# Hardened Manticore Search

Wolfi-based hardened Manticore Search image, built with melange by repackaging searchd/indexer and runtime modules from the upstream bundle `.deb` (SHA256-pinned), then assembled with apko.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (upstream bundle .deb) |
| Version    | 25.0.0 |
| User       | manticore (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~251 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9306 | TCP | MySQL protocol |
| 9308 | HTTP | HTTP API |
| 9312 | TCP | binary |

## Usage

```bash
docker run -d -p 9306:9306 -p 9308:9308 -v mtcdata:/var/lib/manticore hub.blackshield.pt/test_images/manticore:25.0.0
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/manticore:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/manticore | Data directory |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `docker exec CONTAINER searchd --status --config /etc/manticoresearch/manticore.conf` (or `curl -fsS http://HOST:9308/`).

## Notes

- Config at `/etc/manticoresearch/manticore.conf`; data under `/var/lib/manticore`.
- Bundled modules (columnar, secondary, knn) ship under `/usr/share/manticore`.
