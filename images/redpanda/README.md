# Hardened Redpanda

Wolfi-based hardened Redpanda image, built with melange by repackaging the upstream broker `.deb` and `rpk` release (SHA256-pinned), then assembled with apko.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (upstream broker .deb + rpk) |
| Version    | 26.1.14 |
| User       | redpanda (UID 65532) |
| Shell      | bash + busybox |
| Image size | ~299 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9092 | TCP | Kafka API, SASL |
| 8081 | HTTP | Schema Registry |
| 8082 | HTTP | Pandaproxy |
| 9644 | HTTP | Admin API |

## Usage

```bash
docker run -d -p 9092:9092 -p 9644:9644 -e REDPANDA_SUPERUSER_PASSWORD=secret -v rpdata:/var/lib/redpanda/data hub.blackshield.pt/test_images/redpanda:26.1.14
```

| Variable | Default | Description |
|----------|---------|-------------|
| REDPANDA_SUPERUSER_PASSWORD | unset | superuser password — required |
| REDPANDA_SUPERUSER | admin | superuser name |
| REDPANDA_ADVERTISE_HOST | container hostname | advertised address for external clients |

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/redpanda:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/redpanda/data | Data directory |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `docker exec CONTAINER rpk cluster health`.

## Notes

- SASL/SCRAM-SHA-256 is required; the entrypoint bootstraps the superuser once the cluster is healthy.
- Keeps `bash` + `busybox` because the broker launcher and the bootstrap entrypoint are shell scripts.
- The hermetic `/opt/redpanda` tree (bundled loader + libs) comes from the upstream package.
