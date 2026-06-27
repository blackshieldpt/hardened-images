# Hardened etcd

Wolfi-based hardened etcd image, assembled with apko from the Wolfi `etcd-3.6` package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi etcd-3.6) |
| Version    | 3.6 |
| User       | etcd (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~77 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 2379 | HTTP/gRPC | Client API |
| 2380 | HTTP | Peer (cluster) |

## Usage

```bash
docker run -d -p 2379:2379 -v etcddata:/var/lib/etcd hub.blackshield.pt/test_images/etcd:3.6
```

Configuration is driven by `ETCD_*` environment variables (e.g. `ETCD_NAME`, `ETCD_INITIAL_CLUSTER`). The image defaults to a single node listening for clients on `0.0.0.0:2379` with data in `/var/lib/etcd`.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/etcd:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/etcd | Data directory |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless). Probe from your orchestrator: `docker exec CONTAINER etcdctl endpoint health`.

## Notes

- `etcd`, `etcdctl`, and `etcdutl` are included.
- Client listen address is `0.0.0.0:2379`; advertised client URL defaults to `127.0.0.1:2379` (override via `ETCD_ADVERTISE_CLIENT_URLS` for multi-host clients).
