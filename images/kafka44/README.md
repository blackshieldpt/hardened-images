# Hardened Kafka 4.4

Wolfi-based hardened Apache Kafka 4.4 image (KRaft mode), assembled with apko from the upstream Apache distribution — repackaged by melange with Connect removed and its one vulnerable bundled jar replaced — plus the KRaft config and entrypoint. Kafka 4.3 is the `kafka` image.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko + melange (upstream tarball repackaged, patched jar) |
| Version    | 4.4.0 |
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
docker run -d -p 9092:9092 -v kafkadata:/var/kafka/data hub.blackshield.pt/test_images/kafka44:4.4.0
```

| Variable | Default | Description |
|----------|---------|-------------|
| KAFKA_CLUSTER_ID | random (first boot) | KRaft cluster id used to format storage |
| KAFKA_HEAP_OPTS | JVM default | e.g. `-Xmx1G -Xms256M` |
| KAFKA_CONFIG | /etc/kafka/server.properties | broker config path |

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/kafka44:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/kafka/data | Log/segment data (KRaft metadata + topics) |

## Readiness

No in-image `HEALTHCHECK`. Probe from your orchestrator: `docker exec CONTAINER /usr/lib/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list`.

## Why a separate image

Kafka 4.4 storage directories are not forward-compatible: a directory formatted by
4.4's `kafka-storage` cannot be opened by a 4.3 broker. The entrypoint formats
storage on first boot, so a 4.3 -> 4.4 bump under the `kafka` tags would leave
volumes that cannot roll back. **Moving a volume from `kafka` to `kafka44` is
one-way.**

## Patched jars

Same approach as `kafka` (see its README for why this repackages the upstream
distribution instead of using Wolfi's frozen package or building from source).
4.4.0 already ships every jar `kafka` replaced up to 4.3.1 — jackson 2.21.7, log4j2
2.25.5, and jline 3.30.16, now split into `jline-reader`/`-terminal`/`-native`
without the builtins/telnet modules the jline findings are in. One swap remains:

| Jar | Upstream 4.4.0 | Shipped here | Why |
|---|---|---|---|
| jetty (10 jars), jersey (6), swagger | 12.0.39 / 3.1.10 | **removed** | Connect-only; see below |
| lz4-java | 1.11.2 | **1.11.4** | GHSA-mcr4-qmvw-px4g (High), GHSA-gm45-99xc-r7wv, GHSA-343h-94h5-c4wr. Note the coordinate is `at.yawk.lz4`, the maintained fork — `org.lz4` stops at 1.8.1 |

The replacement names the version it replaces and fails the build if that version
is not what upstream shipped, so a Kafka bump cannot silently turn the swap into a
downgrade. The melange build asserts the patched jar by exact filename and the
smoke test asserts it against the running image.

## Kafka Connect is not included

`connect-*`, `jetty-*`, `jersey-*` and `swagger-annotations` are removed, and the
`connect-distributed.sh` / `connect-standalone.sh` launchers with them. This image
is a broker: its entrypoint starts `kafka-server-start.sh` and nothing else.

**If you need Connect, this is not your image.** Running it needs its own config,
ports and lifecycle — it was never usable from here — but previously it would have
started rather than being absent.

## Notes

- Single-node **KRaft** mode (broker + controller) — no ZooKeeper required. The entrypoint formats KRaft storage on first boot.
- Config at `/etc/kafka/server.properties`; CLI tools under `/usr/lib/kafka/bin/`.
- A standalone `zookeeper` image is also published for ZooKeeper-mode deployments.
