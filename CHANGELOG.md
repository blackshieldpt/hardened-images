# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once tagged.

## [Unreleased]

## [0.3.0] - 2026-08-25

The minor bump — rather than 0.2.1 — is because consumers pinning a floating
`:<version>` tag must change it. Two images move:

| image | old tag | new tag |
|-------|---------|---------|
| `go` | `1.26` | `1.27` |
| `zookeeper` | `3.9` | `3.9.5` |

Immutable `:<version>-<commit>` pins and digests are unaffected. One image is new
(`nginx-acme`), `zookeeper` is now built from upstream source rather than installed
from Wolfi, and `go`'s prod image no longer ships a shell.

### Added
- **`nginx-acme`** — a new image: the `nginx` image plus
  [lego](https://github.com/go-acme/lego) 5.3.1, which obtains its own TLS
  certificate from an ACME CA and keeps it renewed. Set `TLS_MODE=acme`,
  `TLS_SERVER_NAME` and `TLS_ACME_EMAIL`, mount a volume at `/var/lib/acme`, and
  that is the whole configuration: no certbot on the host, no companion container,
  no hook scripts, no cron, and no downtime for a renewal.

  **`nginx` is untouched.** A separate image rather than a mode of the existing one
  because lego is ~40 MB and brings 206 Go modules into the SBOM and the
  vulnerability scan, and deployments that terminate TLS elsewhere should not carry
  that. With `TLS_MODE` unset, `nginx-acme` behaves identically to `nginx`.

  It works in-image because the container already owns port 80, which is the hard
  part of HTTP-01 — every external arrangement has to either take that port away
  from nginx or coordinate with it. The renewal loop signals **its own pid 1**, so
  unlike `nginxproxy/acme-companion` nothing mounts a docker socket next to a
  network-exposed service.

  Two phases, because nginx treats an `ssl_certificate` pointing at a missing file
  as a *fatal* error and so cannot start in order to answer the challenge that
  produces its first certificate. Phase 1 serves the challenge on `:80` and `503`s
  everything else, with `:443` closed; phase 2 is the full TLS config, promoted by
  `SIGHUP` the moment the certificate arrives — no restart, no dropped connections.
  The usual alternative, a self-signed placeholder, means shipping a known private
  key in a public image and briefly serving it to real clients.

  lego is built from source because Wolfi has no `lego` package — its only ACME
  client is `acme.sh`, needing curl + openssl + socat, three dependencies these
  images deliberately do not carry. Built as `versitygw` is: `git-checkout` with
  `expected-commit`, `CGO_ENABLED=0`, and a build-time assertion that the result is
  not dynamically linked.

  **A High advisory the gate would have passed:** lego 5.3.1 pins
  `google.golang.org/grpc` v1.82.0, carrying GHSA-hrxh-6v49-42gf (High, gRPC-Go xDS
  RBAC and HTTP/2), fixed in v1.82.1. `SEVERITY_THRESHOLD` is CRITICAL, so nothing
  would have failed. The melange pipeline bumps it before building. Also worth
  recording: trivy's language scanners see nothing inside a static Go binary
  (`Number of language-specific files num=0`), so **grype alone** covers those 206
  modules.

  **What this adds to the pipeline.** A twentieth image, so the build matrix runs
  two more jobs (prod and dev) and publishes `ghcr.io/blackshieldpt/nginx-acme` with
  the same three tags as everything else. Its version tracks the nginx line —
  `VERSION_nginx_acme` in `config.env`, bumped together with `VERSION_nginx`, since
  it is the same upstream nginx underneath. Its dev variant gets curl and openssl,
  as `nginx`'s does. The lego version is pinned by hand in the melange `vars:` and
  `check-updates` cannot see it: `resolve_version()` only reads `package.version`
  when the melange carries an `identifier:`, and adding one here would make the
  image publish as the entrypoint package's version instead of nginx's.

  Because the image is a copy of `nginx` plus a client, its smoke test asserts the
  copies have not drifted — `nginx-hardened.conf` and the default template must be
  byte-identical to `nginx`'s, and both entrypoints must still share their envsubst
  core — alongside phase-1 startup, the challenge path being served rather than
  redirected, `lego --version`, nginx still being pid 1, survival of `SIGHUP`, a
  writable state directory, and that nothing happens when `TLS_MODE` is unset. See
  [`images/nginx-acme/README.md`](images/nginx-acme/README.md).
- `check-updates` now also detects **frozen Wolfi packages** and **unobtainable
  fixes**, neither of which is version drift and neither of which any existing check
  could see. A frozen package *is* the newest version, so the version comparison
  calls it current, the daily relock finds nothing to change, and the scan gate stays
  quiet if the scanner has not annotated it — which is exactly how `etcd`, `openbao`,
  `nginx-stable` and the `valkey-8.1` line all rotted unnoticed.
  - **FROZEN**: a pinned package Wolfi has not rebuilt in `STALE_AFTER_DAYS`
    (default 45). Rebuilds are how a Wolfi package picks up patched libraries, so a
    stale build is a stale dependency tree at a current version. Aged only for the
    package carrying an image's software — the base layer (`bash`, `zlib`,
    `ca-certificates-bundle`, `su-exec`) is low-churn and routinely months old
    without anything being wrong, and ageing it weekly would be noise that teaches
    you to skim the report.
  - **UNOBTAINABLE FIX**: Wolfi's advisory data names a fixed version that does not
    exist in the public index — a known CVE with an identified fix you cannot get.
    Precise enough to run across every package an image installs.
  Neither produces a bump PR, because there is nothing to bump to; both go to the
  tracking issue so the choice (accept, VEX, or build from source) is deliberate.
  On the current tree this reports `kafka-4.3` and `zookeeper-3.9` as frozen at 56
  and 57 days, and `zookeeper-3.9` as naming a fix at `3.9.5-r11` that was never
  published.

### Changed
- **`go` moves to Go 1.27, and its prod image is now shell-less.** Wolfi dropped
  `go-1.26`'s `bash` dependency at 1.26.6-r0 and `go-1.27` declares no runtime
  dependencies either, so the package set is `wolfi-baselayout`,
  `ca-certificates-bundle` and the toolchain, and nothing else. The test asserts
  that (`check_no_shell` on prod, `check_dev` on the dev variant) rather than the
  shell it used to rely on, and the README no longer documents CGO builds against
  the prod image — there is no gcc or glibc-dev there to do them. CGO builds use
  the `-dev` variant, which installs both explicitly.
  - **Consumers pinning `go:1.26` must move to `go:1.27`.**
- `zookeeper` is now **built from upstream source** with melange instead of installing
  Wolfi's `zookeeper-3.9` — acting on the first thing the freeze detector above found.
  Wolfi's package stopped at `3.9.5-r4` on 2026-06-02 while its advisory data went on
  naming fixes in `-r7`, `-r8`, `-r9`, `-r10`, `-r11` and `-r12`: six revisions and
  ~13 CVEs pointing at builds nobody can obtain. The entire Kafka/ZooKeeper family in
  public Wolfi stops on that same date, so there was no newer line to move to either.
  - **48 findings (18 High, 11 Medium, 4 Low, 15 unrated) → 2 High, both documented
    as not applicable.** The 28 `zookeeper-3.9` apk rows disappear with the package;
    the 20 java-archive rows are fixed by the dependency overrides below. Note the
    gate is `CRITICAL`, so the two survivors never blocked it and the VEX below does
    not change that — it records the reasoning and keeps the grype table honest.
  - **A plain source build would not have fixed anything.** Every one of those CVEs is
    in a bundled jar, not in ZooKeeper's own code, and upstream's 3.9.5 pom pins netty
    4.1.130 and logback 1.3.15 — both *older* than what the frozen apk already shipped.
    The build overrides netty to **4.1.136.Final** (CVE-2026-59901; upstream's own
    `branch-3.9` only reached 4.1.135), jackson to **2.18.9** (CVE-2026-54515,
    CVE-2026-59889) and logback to **1.5.37** (CVE-2026-10532, the same bump upstream
    made in ZOOKEEPER-5057). The build then *asserts* those jars are the ones shipped,
    and so does the smoke test — a future bump that silently reverts to upstream's
    versions fails instead of quietly reintroducing the CVEs.
  - **Jetty is no longer shipped.** Jetty 9.4 is EOL: 9.4.58 is the last public
    release and the 9.4.63 its advisories name is commercial-only, so those four
    findings (2 High) were unfixable by any override. ZooKeeper loads the admin server
    reflectively precisely so Jetty can be omitted, and our `zoo.cfg` disables it.
    Two consequences for a bind-mounted `zoo.cfg`, both verified: `admin.enableServer=true`
    logs a `WARN`/`NoClassDefFoundError` and keeps serving clients with no admin
    endpoint — so an HTTP probe against it fails while the server looks healthy — and
    `PrometheusMetricsProvider` exits 1 at startup. Both are in the image README.
  - The two remaining findings are JLine Telnet-server flaws that ship inside the
    `jline` uber-jar, which ZooKeeper uses only for `zkCli.sh` line editing. Fixed
    only in jline 4.2.1, an API break — waived in a new
    `images/zookeeper/vex.openvex.json`, the first per-image VEX here.
  - Runtime dependencies that used to arrive as auto-deps of the Wolfi package (the
    JRE, `bash`, `grep`, `sed`, `procps`) are now declared explicitly in the apko
    config. `VERSION_zookeeper` is gone from `config.env`; the version comes from
    `package.version`, and `check-updates` now tracks the image against
    `apache/zookeeper` tags instead of reporting it frozen.
  - **Consumers pinning `zookeeper:3.9` must move to `zookeeper:3.9.5`.**
- `scripts/propose-update.sh` takes the git tag shape from the image's melange
  `git-checkout` step instead of assuming a `v<version>` prefix. It hardcoded `v`, so
  ZooKeeper's `release-3.9.5` would have failed the lookup and fallen through to the
  tracking issue rather than opening a PR — as Kafka's bare `4.3.1` will when it moves
  from source.
- `vex/EXAMPLE.openvex.json.sample` used a `pkg:oci/...` product identifier, which
  grype does not match — copying it produced waivers that silently did nothing. The
  sample and `vex/README.md` now use a plain image reference, and the README says how
  to verify a waiver actually applies when the finding is below the gate threshold.

### Fixed
- **`nginx-acme` now reaches the CA instead of failing in lego's argument
  parser.** lego 5.x scopes issuance and renewal options to its `run` command;
  the loop placed `--accept-tos` and the remaining options before that command,
  where they were treated as unknown global flags. The smoke test now exercises
  the full option set and rejects this otherwise-silent renewal-loop failure.

## [0.2.0] - 2026-07-29

Security release. The minor bump — rather than 0.1.7 — is because consumers pinning a
floating `:<version>` tag must change it. Nine images move:

| image | old tag | new tag |
|-------|---------|---------|
| `clickhouse` | `26.1.12.23` | `26.7.1.1315` |
| `etcd` | `3.6` | `3.6.14` |
| `kafka` | `4.2` | `4.3` |
| `mailpit` | `1.30.0` | `1.30.6` |
| `manticore` | `25.0.0` | `28.4.4` |
| `minio` | `0.20260604.005411` | `0.20260717.120751` |
| `nginx` | `1.30` | `1.31` |
| `openbao` | `2.5.4` | `2.6.1` |
| `valkey` | `8.1` | `9.1` |

Immutable `:<version>-<commit>` pins and digests are unaffected.

Three images also stop shipping content they previously carried: `python-sodium` drops
pip from the runtime variant, `manticore` drops the bundled PHP tools and the
client-library source tree, and `etcd`/`openbao` are now built from source rather than
installed from Wolfi.

Two things worth reading before upgrading:

- **Several of the vulnerabilities fixed here were invisible to both grype and trivy.**
  The affected code was vendored inside a static binary or a bundled library tree, so
  the images scanned clean while carrying it — ClickHouse's OpenSSL 3.5.6 (fifteen
  CVEs) and Redpanda's krb5 (CVSS 8.7) were both found by reading binaries, not
  reports.
- **A version bump is not automatically a fix.** `kafka` 4.2 → 4.3 halves the reported
  finding count while shipping byte-identical vulnerable JARs, because Wolfi has not
  annotated the newer line. The Security section below says which changes were real.

### Security

- Swept every repackaged-source image for vendored code that ships inside a
  binary or tree the apk/Go scanners cannot see — the class of problem the
  `redpanda` krb5 and `manticore` PHP findings both belong to. Results:
  - `clickhouse` **statically links OpenSSL 3.5.6**, which is affected by fifteen
    CVEs fixed upstream in OpenSSL 3.5.7 (including CVE-2026-45447, a heap
    use-after-free in `PKCS7_verify()`, and CVE-2026-42768, a Bleichenbacher
    oracle in `CMS_decrypt()`). Both scanners report the image completely clean.
    **Fixed** by the ClickHouse upgrade below.
  - `redpanda` bundles its own glibc 2.35, OpenSSL and krb5 under
    `/opt/redpanda/lib`. Its OpenSSL is **3.5.7**, i.e. current.
  - `mailpit` and `versitygw` are pure-Go static builds, so their dependencies
    stay scanner-visible; both are patched below.
  - The config-only melange images (`kafka`, `nats`, `nginx`, `openbao`,
    `postgresql`, `zookeeper`) ship no upstream binaries — their software comes
    from Wolfi apks and is fully visible.

### Added
- `check-updates` now **opens a PR per image that is behind upstream**, with the bump
  already applied — version pin, dependent package names, and whatever the image
  derives from them (lockfile, `expected-commit`) — via a new
  `scripts/propose-update.sh`. Nothing merges automatically: the PR's own build,
  smoke test and scan are what decide whether the bump is good, which matters
  because a version bump can make findings *disappear* without fixing anything.
  It also now covers **Wolfi version lines**, not just from-source pins. The daily
  relock moves patches within a line but never the line itself, which is how
  `valkey` sat on a line Wolfi had not rebuilt in 298 days while `valkey-9.1` was a
  week old. Deliberate line pins (`node`, `node24`) are marked `# pinned-line` in
  `config.env` and reported as pinned rather than behind. Images pinning an artifact
  by sha256 (`clickhouse`, `manticore`, `redpanda`) still get a tracking issue
  rather than a half-applied PR — the artifact must be fetched and hashed, and a tag
  can exist before its artifact does.
- `check-updates` workflow (weekly) and `make check-updates`: reports from-source
  images whose pinned `package.version` has fallen behind upstream, into a single
  tracking issue updated in place. The daily relock covers apk-based images, but
  the from-source pins were checked by nothing — and **every one of them had
  drifted**, `manticore` by three major lines. It reports rather than bumps: each
  image pins a different artifact shape (deb filename + sha256, tgz sha256, git
  `expected-commit`), and a tag can exist before its artifact does, so the bump
  stays a human step.

### Changed
- `clickhouse`: 26.1.12.23 → 26.7.1.1315, moving the statically linked OpenSSL from
  3.5.6 to **3.5.7** and clearing the fifteen CVEs above. Verified by reading the
  version banner out of the built binary, not from upstream metadata.
  Two consequences worth knowing:
  - **26.7 is a `-stable` release, not LTS.** ClickHouse backports only to the three
    latest stable releases, so this line needs re-bumping roughly quarterly. The
    `update.github` `tag-filter` moves from `v26.1.` to `v26.7.` accordingly. This was
    a deliberate trade: the current LTS line (26.3.x) still ships OpenSSL 3.5.6, so no
    LTS release fixes these CVEs today.
  - The previous pin, 26.1, had already fallen out of ClickHouse's backport window.
  Consumers pinning `clickhouse:26.1.12.23` must move to `clickhouse:26.7.1.1315`.
- `etcd` and `openbao` are now **built from upstream source** with melange instead of
  installing Wolfi's `etcd-3.6` / `openbao`. Both of those packages stopped being
  rebuilt in early June 2026 while Wolfi's advisory data went on naming fixes —
  `etcd 3.6.13-r1`/`3.6.14-r0`, `openbao 2.5.5-r2`/`2.6.1-r0` — in versions that were
  never published to the public repo, so the "FIXED IN" column pointed at builds
  nobody could obtain. Building from source gets those versions and links against
  Wolfi's current Go toolchain, which is what carried the stdlib findings.
  - `etcd` 3.6.12-r1 → **3.6.14**: 12 findings (4 High) → **1 Medium**.
  - `openbao` 2.5.4-r2 → **2.6.1**: 15 findings (4 High) → **none**. 2.6.1 is exactly
    the version Wolfi's advisory names for CVE-2026-56852 (High).
  Both are pure Go with CGO disabled, so unlike the repackaged-binary images their
  module graph stays visible to grype and trivy. Both now carry `update.github`
  blocks, so `check-updates` covers them from day one — the from-source pins are
  hand-maintained, and that is precisely how every other one had rotted.
  `VERSION_etcd` and `VERSION_openbao` are gone from `config.env`; the version now
  comes from `package.version`, and each build asserts the binary reports it.
  Consumers pinning `etcd:3.6` must move to `etcd:3.6.14`, and `openbao:2.5.4` to
  `openbao:2.6.1`.
- `kafka`: 4.2 → 4.3. Read the finding count with care — it drops from 38 to 18, but
  **the vulnerable code is unchanged**: jackson-databind 2.21.2, jackson-core 2.21.2,
  jetty 12.0.34 and jline-remote-telnet 3.30.4 are byte-identical across both lines
  (only lz4-java moves, 1.10.1 → 1.10.2, and it stays flagged). The 20 rows that
  vanish are apk-level duplicates: Wolfi annotates `kafka-4.2` with those advisories
  and has not annotated `kafka-4.3` at all. The bump is still worth taking — 4.3 is
  the maintained line — but it is not a fix, and the real remedy is a Wolfi rebuild
  (`kafka-4.2.1-r3` and later, never published) that refreshes the bundled JARs.
  Consumers pinning `kafka:4.2` must move to `kafka:4.3`.
- `mailpit`: 1.30.0 → 1.30.6, clearing GHSA-28pq-6qxg-wg5r and GHSA-w4mc-hhc6-xp28
  in mailpit itself (fixed in 1.30.1 / 1.30.2), and the dependency patch now also
  bumps `x/text` and `x/image` — eight further High/Medium advisories. Scans clean.
- `manticore`: 25.0.0 → **28.4.4**, three major lines forward, and the image now ships
  considerably less. The pin had gone stale because nothing tracked upstream versions
  for from-source images (see the `check-updates` entry above); 28.4.4 is the newest
  build published to Manticore's apt channel — GitHub tags 28.5.3, but no deb exists
  for it in either the stable or dev channel.
  - The upstream bundle's **PHP tools** (`manticore-backup`, `manticore-buddy`,
    `manticore-load`) are no longer copied in. They ship their own composer `vendor/`
    trees, which carried **CVE-2026-54133 (Critical)** in `mtdowling/jmespath.php` plus
    ~19 High/Medium findings across `composer/composer`, `guzzlehttp/*` and
    `symfony/cache` — enough to fail the scan gate and block every publish since at
    least 2026-07-27. Nothing in the image could execute them: there is no PHP
    interpreter and `manticore.conf` sets no `buddy_path`. The `.so` modules sharing
    that directory (columnar, secondary, knn, galera) are retained, and the build
    asserts they survive.
  - `/usr/share/manticore/api` is gone too — client-library *source* (libsphinxclient
    C sources, a Ruby client with its specs, `sphinxapi.php`) that searchd never reads.
    99 files; the image drops from 2213 to 2114.
  - The `.php` guard added with the PHP-tool removal **never worked**: written as
    `! find … | grep -q .`, and under `set -e` a command whose status is inverted with
    `!` is exempt from triggering an exit, so it silently passed whatever it found. It
    is now an explicit `if … exit 1` covering the whole package — possible because
    `api/`, the only source of legitimate `.php`, is gone — and verified to fail the
    build when a `.php` is planted. The `.so` checks were always effective.
  - The build now asserts `searchd --version` reports `package.version`; the previous
    check was `searchd --help … || true`, which asserted nothing, while `vars.deb`
    carries its own copy of the version and could silently disagree with it.
  Consumers pinning `manticore:25.0.0` must move to `manticore:28.4.4`.
- `minio`: tagged `0.20260717.120751` — the committed lock had already picked up that
  build via relock, but `VERSION_minio` still carried the older `0.20260604.005411`,
  so the tag understated what shipped.
- `nginx`: built from Wolfi `nginx-mainline` (1.31.3) instead of `nginx-stable`, and
  tagged `1.31` instead of `1.30`. `nginx-stable` is capped at 1.30.2 in Wolfi, which
  is affected by CVE-2026-42055 (heap buffer overflow in HTTP/2 proxying, CVSS 4.0
  9.2) and CVE-2026-48142; upstream fixed both in 1.30.3 / 1.31.2, but Wolfi has so
  far only published the fix on the mainline line. This will move back to
  `nginx-stable` once its patched build lands. Consumers pinning `nginx:1.30` must
  move to `nginx:1.31`.
- `python-sodium`: **pip is no longer in the runtime image** — it moved to the `-dev`
  variant. An installer with network reach is the readiest
  arbitrary-code-fetch-and-execute primitive in an otherwise shell-less image, and
  nothing needs it once the app is built. Install dependencies in a `-dev` builder
  stage and copy `site-packages` across (see the image README). Dropping `py3.14-pip`
  also drops `py3.14-setuptools`, so `pkg_resources` / `_distutils_hack` are gone from
  the runtime image unless the app's own dependency tree installs setuptools.
  To be precise about what this does and does not buy — the image README says the
  same: `python-3.14-base` hard-depends on `py3-pip-wheel`, so
  `/usr/share/python-wheels/pip-*.whl` still ships and `python -m ensurepip --user`
  restores a working pip offline. This is defence in depth, not a boundary; it takes
  code execution an attacker must already have. What it removes is pip simply being
  *there*, on PATH, for the app user.
- `redpanda`: 26.1.9 → 26.1.14. 26.1.9 ships a bundled krb5 under `/opt/redpanda/lib`
  affected by CVE-2026-40355 and CVE-2026-40356 (NegoEx message parsing; unauthenticated
  remote crash, CVSS 8.7), which upstream patched in 26.1.10 and fully resolved by moving
  to krb5 1.22.2 in 26.1.11. Because the broker vendors its own libraries, **no apk or
  Go-module scanner surfaced this** — the image scanned clean throughout. rpk's patched
  dependency set also now bumps `x/net`, `x/text`, `klauspost/compress` and `grpc`.
- `valkey`: **8.1 → 9.1**. Not a rebuild — a whole line move. Wolfi last built
  `valkey-8.1` on 2025-10-03 (298 days), while `valkey-9.1` (9.1.1, exactly upstream
  latest) was built seven days ago. Nothing noticed because the relock only moves
  patches *within* the pinned line. Verified beyond the smoke test that data written
  by 8.1 loads under 9.1, since that is what an upgrade actually does. Consumers
  pinning `valkey:8.1` must move to `valkey:9.1`.
- `versitygw`: dependency patch added to bump `x/text` past GO-2026-5970. The image
  built from v1.6.0 sources otherwise stays as-is. Scans clean.
- CI tool installs are retried and then **verified**, and `cosign` joins the cached,
  pinned toolchain instead of `sigstore/cosign-installer`. Three separate install paths
  reddened runs in a single day: `trivy` (missing binary), `cosign` (three times), and
  `apt`, which reported success while `bubblewrap` was simply not installed — surfacing
  two steps later as an opaque `bwrap not found` from `check-tools`. Each install now
  retries, and the step asserts every tool is present and reports its pinned version,
  so a silent partial install fails where it happens rather than somewhere downstream.
  With cosign cached, a warm cache needs no network at all: 11.5s cold, 0.15s warm for
  the whole toolchain. `relock.yml` gets the same apt retry and assertion.

## [0.1.6] - 2026-07-13

### Added
- `versitygw` image: hardened, shell-less Versity S3 Gateway 1.6.0, built from
  source with melange (versitygw isn't packaged in Wolfi), pure-Go/static
  (CGO disabled). Non-root; defaults to the POSIX backend serving `/data` as S3
  with a health endpoint at `GET /_health`. No in-image TLS (terminate upstream).
  Its smoke test does an authenticated SigV4 round-trip (create bucket, PUT +
  GET object, verify body) via a new stdlib-only `scripts/s3-roundtrip.py`.

## [0.1.5] - 2026-07-04

### Added
- `openbao` image: hardened, shell-less OpenBao 2.5.4 (the Vault-compatible
  secrets manager, Wolfi `openbao`), non-root with a single-node `file`-storage
  config shipped via a small melange package. No in-image TLS (terminate
  upstream); needs no `mlock`/`CAP_IPC_LOCK`.

## [0.1.4] - 2026-06-29

### Added
- `nginx` image: runtime `envsubst` config templating, matching the official
  image's contract. A busybox entrypoint renders `*.template` files (via an
  explicit allowlist driven by `NGINX_ENVSUBST_FILTER`, so nginx's own
  `$host`/`$remote_addr` survive) into a writable `conf.d` that the config
  includes — so one immutable image is configurable per environment. No
  templates keeps the default welcome page.

### Changed
- `nginx` now ships its entrypoint/config via melange, so it resolves its package
  set fresh each build instead of from a committed apko lockfile.

## [0.1.3] - 2026-06-29

### Added
- `clickhouse` image: honor the upstream `CLICKHOUSE_*` env-var contract. A
  busybox entrypoint generates a `users.d` override from `CLICKHOUSE_USER`,
  `CLICKHOUSE_PASSWORD` (stored as `password_sha256_hex`),
  `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT`, and `CLICKHOUSE_SKIP_USER_SETUP` — so
  the hardened image is a drop-in for deployments that set a password. No vars
  set keeps stock (passwordless) behavior; database creation stays app-side.

## [0.1.2] - 2026-06-29

### Added
- `python-sodium` image: hardened, shell-less Python 3.14 app base — same CPython as
  `python` plus the system libs web apps load at runtime (`libsodium`,
  `libmagic`, `ttf-dejavu`) and `ld-linux` so `ctypes.util.find_library` resolves
  via the apko-generated `/etc/ld.so.cache` and the `ldconfig -p` fallback. Ships
  no entrypoint (the app sets its own `CMD`) and `HOME=/tmp` for non-root gunicorn.

## [0.1.1] - 2026-06-29

### Added
- `node24` image: hardened, shell-less Node.js 24 (Wolfi `nodejs-24`), published
  alongside the existing `node` (22) image so both major lines stay available.
- `minio` image: hardened, shell-less MinIO S3-compatible object storage (Wolfi
  `minio` + `mc` client), apk-native and lock-pinned.

### Changed
- Bump GitHub Actions off the deprecated Node 20 runtime: `actions/checkout` v5,
  `actions/upload-artifact` v6, `docker/login-action` v4,
  `actions/attest-build-provenance` v3.

### Fixed
- Melange-repackaged images no longer attempt committed apko lockfiles: their
  package is signed with an ephemeral per-build key, so a committed lock's
  control hash never matches on rebuild (`control hash mismatch`). They now
  resolve fresh each build; committed lockfiles remain for apk-native images,
  and `relock` / `make lock` skip melange images.
- Harden the in-pipeline verify step so a hung cosign/Rekor fetch can't stall the
  build: bound the step with a shell timeout, bound each cosign call, skip the
  Rekor query in the self-check, and discard cosign payload stdout to clear
  log-pipe backpressure.

## [0.1.0] - 2026-06-27

### Added
- Hardened, distroless OCI images for 14 packages (nginx, node, go, python,
  postgresql, valkey, clickhouse, nats, manticore, mailpit, redpanda, kafka,
  zookeeper, etcd), built with apko/melange on Wolfi and published to
  `ghcr.io/blackshieldpt/<image>` from GitHub Actions.
- Supply-chain attestations on every image: keyless cosign signature (Fulcio
  OIDC), SLSA build provenance (`actions/attest-build-provenance`, L3), and
  CycloneDX + SPDX SBOMs.
- Blocking Grype + Trivy scan gate with an OpenVEX waiver path (`vex/`) and a
  `SCAN_GATE` toggle.
- SBOM publishing: downloadable workflow artifact per build, plus optional
  upload to Dependency-Track (secret-driven host).
- Committed apko lockfiles with `SOURCE_DATE_EPOCH` pinned to the source commit,
  for byte-reproducible builds; `make lock` / `lock-all` to regenerate them.
- Daily `relock` workflow: re-resolves lockfiles and, on a Wolfi update, commits
  the change via a deploy key, which republishes the patched (still reproducible)
  image automatically.
- Immutable per-build tag `:<version>-<commit>` alongside the floating
  `:<version>` and `:latest` tags.
- `mailpit` and `redpanda`'s `rpk` built from source (patched `x/crypto` /
  `x/net`) to clear bundled Go-dependency CVEs that the gate blocked.
- Dev variants (`-dev`): the hardened image plus a shell and toolchain, for
  debugging; built, signed, attested, and SBOM'd, with an advisory (non-gating)
  scan.
- Optional mirror to a second registry (secret-driven).

### Changed
- Build from committed lockfiles instead of re-resolving each build.
- Pin the CycloneDX SBOM to spec 1.6 for Dependency-Track compatibility.
- Made the in-pipeline verify step capped and non-blocking (real verification
  happens at consume time).
- Skip the build matrix on docs-only changes (`paths-ignore`).

### Fixed
- Re-enable unprivileged user namespaces for melange's bubblewrap sandbox on
  Ubuntu 24.04 runners.
- `make check-tools` now checks `melange` and `bwrap`; README/Makefile
  inconsistencies corrected.

[Unreleased]: https://github.com/blackshieldpt/hardened-images/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/blackshieldpt/hardened-images/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/blackshieldpt/hardened-images/releases/tag/v0.1.0
