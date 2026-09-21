# Hardened Kafka

Wolfi-based hardened Apache Kafka image (KRaft mode), assembled with apko from the upstream Apache distribution — repackaged by melange with Connect removed and its vulnerable bundled jars replaced — plus the KRaft config and entrypoint.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko + melange (upstream tarball repackaged, patched jars) |
| Version    | 4.3.1 |
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
docker run -d -p 9092:9092 -v kafkadata:/var/kafka/data hub.blackshield.pt/test_images/kafka:4.3.1
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

## Why not the Wolfi package

Wolfi's `kafka-4.3` stopped being rebuilt on 2026-06-02 at `4.3.0-r1`, and the whole
Kafka/ZooKeeper family in public Wolfi stops on that date, so no pin change helped.
The image carried 7 High and 14 Medium findings as a result.

Every one of them was a **bundled jar**, not Kafka's own code — so a build from
source would have reproduced them exactly: upstream's `dependencies.gradle` pins
jackson 2.21.2, jetty 12.0.34 and jline 3.30.4 at both 4.3.0 and 4.3.1. The fix is
therefore to repackage the upstream distribution and change the jars:

| Jar | Upstream 4.3.1 | Shipped here | Why |
|---|---|---|---|
| jetty (10 jars), jersey (6), swagger | 12.0.34 / 3.1.10 | **removed** | Connect-only; see below. Clears GHSA-2fvj-hgj9-j2gr (High) and two Mediums |
| jackson (9 jars) | 2.21.2 | **2.21.5** | GHSA-j3rv-43j4-c7qm, GHSA-rmj7-2vxq-3g9f, GHSA-r7wm-3cxj-wff9 (High) + 7 Mediums |
| jline | 3.30.4 | **3.30.14** | CVE-2026-56740, CVE-2026-56741 (High) |
| log4j2 (4 jars) | 2.25.4 | **2.25.5** | GHSA-qv9r-c865-cp47 |
| lz4-java | 1.10.2 | **1.11.1** | GHSA-xx22-p4ch-683r. Note the coordinate is `at.yawk.lz4`, the maintained fork — `org.lz4` stops at 1.8.1 |

`jackson-annotations` stays at 2.21: it tracks the minor line only, publishes no
patch releases, and carries no findings.

Each replacement names the version it replaces and fails the build if that version
is not what upstream shipped, so a Kafka bump cannot silently turn a swap into a
downgrade. The melange build asserts the patched jars by exact filename and the
smoke test asserts the same set against the running image.

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
