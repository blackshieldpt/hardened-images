# Hardened NATS

Wolfi-based hardened NATS image, assembled with apko from the Wolfi `nats-server` package, with the hardened config shipped via a small melange package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi nats-server) + melange (config) |
| Version    | 2.14.1 |
| User       | nats (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~18 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 4222 | TCP | client |
| 6222 | TCP | cluster routing |
| 8222 | HTTP | monitoring |

## Usage

```bash
docker run -d -p 4222:4222 -p 8222:8222 hub.blackshield.pt/test_images/nats:2.14.1
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/nats:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /data | JetStream store at `/data/jetstream` |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `curl -fsS http://HOST:8222/healthz`.

## Notes

- JetStream is enabled by default; config at `/etc/nats/nats.conf`.
- Monitoring endpoints under `http://HOST:8222/` (`/varz`, `/jsz`, `/healthz`).
