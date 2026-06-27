# Hardened Kafka

Wolfi-based hardened Apache Kafka image (KRaft mode), assembled with apko from the Wolfi `kafka-4.2` package, with the KRaft config and entrypoint shipped via a small melange package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi kafka-4.2) + melange (config + entrypoint) |
| Version    | 4.2 |
| User       | kafka (UID 65532) |
| Shell      | bash + busybox |
| Image size | ~361 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9092 | TCP | Kafka API (PLAINTEXT) |
| 9093 | TCP | KRaft controller |

## Usage

```bash
docker run -d -p 9092:9092 -v kafkadata:/var/kafka/data hub.blackshield.pt/test_images/kafka:4.2
```

| Variable | Default | Description |
|----------|---------|-------------|
| KAFKA_CLUSTER_ID | random (first boot) | KRaft cluster id used to format storage |
| KAFKA_HEAP_OPTS | JVM default | e.g. `-Xmx1G -Xms256M` |
| KAFKA_CONFIG | /etc/kafka/server.properties | broker config path |

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/kafka:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/kafka/data | Log/segment data (KRaft metadata + topics) |

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `docker exec CONTAINER /usr/lib/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`.

## Notes

- Single-node **KRaft** mode (broker + controller) — no ZooKeeper required. The entrypoint formats KRaft storage on first boot.
- Config at `/etc/kafka/server.properties`; CLI tools under `/usr/lib/kafka/bin/`.
- A standalone `zookeeper` image is also published for ZooKeeper-mode deployments.
