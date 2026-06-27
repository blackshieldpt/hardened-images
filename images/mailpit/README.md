# Hardened Mailpit

Wolfi-based hardened Mailpit image, built with melange by repackaging the upstream static release binary (SHA256-pinned), then assembled with apko.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (upstream static release binary) |
| Version    | 1.30.0 |
| User       | mailpit (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~27 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 1025 | SMTP     | mail submission |
| 8025 | HTTP     | web UI + API |

## Usage

```bash
docker run -d -p 1025:1025 -p 8025:8025 hub.blackshield.pt/test_images/mailpit:1.30.0
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + openssl (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/mailpit:latest-dev
```

## Volumes

`/data` (optional, when `MP_DATABASE` is set)

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `curl -fsS http://HOST:8025/livez`

## Notes

- SMTP testing server: catches mail on 1025, view it on the 8025 web UI.
- Stores messages in memory unless `MP_DATABASE` points at `/data`.
