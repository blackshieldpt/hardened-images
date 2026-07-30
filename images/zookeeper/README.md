# Hardened ZooKeeper

Wolfi-based hardened Apache ZooKeeper image. ZooKeeper is built from upstream source
with melange, with its vulnerable bundled jars overridden — see [Why from
source](#why-from-source) — and a standalone `zoo.cfg` shipped in the same package.

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (ZooKeeper from source) + apko |
| Version    | 3.9.5 |
| User       | zookeeper (UID 65532) |
| Shell      | bash + busybox |
| Image size | ~225 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 2181 | TCP | Client connections |

## Usage

```bash
docker run -d -p 2181:2181 -v zkdata:/var/lib/zookeeper/data hub.blackshield.pt/test_images/zookeeper:3.9.5
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

## Why from source

Wolfi's `zookeeper-3.9` package stopped being rebuilt on 2026-06-02 at `3.9.5-r4`,
while Wolfi's advisory data kept naming fixes in `-r7` through `-r12` — six revisions
and roughly 13 CVEs whose "FIXED IN" pointed at builds that were never published. The
whole Kafka/ZooKeeper package family in public Wolfi stops on that date, so no pin
change could help.

Every one of those CVEs is in a bundled jar rather than in ZooKeeper itself, so
building 3.9.5 unchanged would have reproduced them — upstream's pom pins netty and
logback *older* than the frozen apk shipped. The build therefore overrides them:

| Dependency | Upstream 3.9.5 | Shipped here | Why |
|---|---|---|---|
| netty | 4.1.130.Final | **4.1.136.Final** | CVE-2026-59901 (netty-codec); upstream's `branch-3.9` only reached 4.1.135 |
| jackson | 2.15.2 | **2.18.9** | CVE-2026-54515, CVE-2026-59889 |
| logback | 1.3.15 | **1.5.37** | CVE-2026-10532; the same bump upstream made in ZOOKEEPER-5057 |

The melange build asserts these exact jars are the ones installed, and the smoke test
asserts it again against the built image, so a version bump cannot silently fall back
to upstream's pinned versions and reintroduce the CVEs.

## Notes

- Standalone mode; config at `/usr/share/java/zookeeper/conf/zoo.cfg` (`dataDir=/var/lib/zookeeper/data`, `clientPort=2181`).
- Admin (Jetty) server is disabled; four-letter-word commands `ruok,stat,srvr,conf,mntr` are whitelisted.
- **Jetty is not shipped at all.** Jetty 9.4 is EOL — 9.4.58 is the last public
  release and the 9.4.63 its advisories name is commercial-only — so its findings
  could not be fixed, only removed. ZooKeeper loads the admin server by reflection
  specifically so Jetty can be omitted, and falls back to a no-op admin server.
  Two consequences for a bind-mounted `zoo.cfg`, both verified against this image:
  - `admin.enableServer=true` does **not** fail the container. ZooKeeper logs
    `WARN AdminServerFactory -- Unable to load jetty, not starting JettyAdminServer`
    with a `NoClassDefFoundError` and carries on serving clients normally, with no
    admin endpoint. If you probe `/commands/ruok` over HTTP, that probe will fail
    while the server itself looks healthy — use `zkServer.sh status` or a four-letter
    word on 2181 instead.
  - `metricsProvider.className=...PrometheusMetricsProvider` **does** fail: the JVM
    exits 1 at startup on `NoClassDefFoundError: org/eclipse/jetty/server/Handler`.
  If you need either, you need a build that keeps the Jetty jars — and with it four
  findings that have no available fix.
- The Prometheus jars (`simpleclient*`, `zookeeper-prometheus-metrics`) are still in
  `lib/` but cannot load, since Jetty and `javax.servlet-api` are gone. They carry no
  findings today; they are dead weight worth removing if the metrics provider is
  never coming back.
- Two JLine advisories are waived in `vex.openvex.json`: they are Telnet-server flaws
  in a module bundled inside the `jline` uber-jar, and ZooKeeper uses JLine only for
  `zkCli.sh` line editing. The fix is jline 4.2.1, an API break for `zkCli`.
- `zkCli.sh` and `zkServer.sh` are under `/usr/share/java/zookeeper/bin/`.
