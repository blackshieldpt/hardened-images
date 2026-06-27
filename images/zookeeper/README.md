# Hardened ZooKeeper

Wolfi-based hardened Apache ZooKeeper image, assembled with apko from the Wolfi `zookeeper-3.9` package, with a standalone `zoo.cfg` shipped via a small melange package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi zookeeper-3.9) + melange (config) |
| Version    | 3.9 |
| User       | zookeeper (UID 65532) |
| Shell      | bash + busybox |
| Image size | ~228 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 2181 | TCP | Client connections |

## Usage

```bash
docker run -d -p 2181:2181 -v zkdata:/var/lib/zookeeper/data hub.blackshield.pt/test_images/zookeeper:3.9
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/zookeeper:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/zookeeper/data | Data directory |

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `docker exec CONTAINER /usr/share/java/zookeeper/bin/zkServer.sh status` (or `zkCli.sh -server localhost:2181 ls /`).

## Notes

- Standalone mode; config at `/usr/share/java/zookeeper/conf/zoo.cfg` (`dataDir=/var/lib/zookeeper/data`, `clientPort=2181`).
- Admin (Jetty) server is disabled; four-letter-word commands `ruok,stat,srvr,conf,mntr` are whitelisted.
- `zkCli.sh` and `zkServer.sh` are under `/usr/share/java/zookeeper/bin/`.
