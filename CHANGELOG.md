# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once tagged.

## [Unreleased]

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
- `mailpit`: 1.30.0 → 1.30.6, clearing GHSA-28pq-6qxg-wg5r and GHSA-w4mc-hhc6-xp28
  in mailpit itself (fixed in 1.30.1 / 1.30.2), and the dependency patch now also
  bumps `x/text` and `x/image` — eight further High/Medium advisories. Scans clean.
- `versitygw`: dependency patch added to bump `x/text` past GO-2026-5970. The image
  built from v1.6.0 sources otherwise stays as-is. Scans clean.
- `manticore`: 25.0.0 → 28.4.4, three major lines forward. The pin had gone stale
  because nothing tracks upstream versions for from-source images (see below);
  28.4.4 is the newest build published to Manticore's apt channel — GitHub tags
  28.5.3, but no deb exists for it yet. Consumers pinning `manticore:25.0.0` must
  move to `manticore:28.4.4`.
  The image also no longer ships `/usr/share/manticore/api` — client-library
  *source* (libsphinxclient C sources, a Ruby client with its specs, and
  `sphinxapi.php`) that searchd never reads. 99 files; the image drops from 2213
  to 2114. Get clients from your own package manager instead.
  Also **fixes the `.php` guard added alongside the PHP-tool removal**: it was
  written as `! find … | grep -q .`, and under `set -e` a command whose status is
  inverted with `!` is exempt from triggering an exit, so it silently passed
  whatever it found — it had been a no-op since it merged. It is now an explicit
  `if … exit 1` covering the whole package (possible because `api/`, the only
  source of legitimate `.php`, is gone), verified to fail the build when a `.php`
  is planted. The `.so` checks were always effective — plain commands under `set -e`.
- `manticore`: the upstream bundle's PHP tools (`manticore-backup`, `manticore-buddy`,
  `manticore-load`) are no longer copied into the image. They ship their own composer
  `vendor/` trees, which carried **CVE-2026-54133 (Critical)** in `mtdowling/jmespath.php`
  plus ~19 High/Medium findings across `composer/composer`, `guzzlehttp/*` and
  `symfony/cache` — enough to fail the scan gate and block every publish since at least
  2026-07-27. Nothing in the image could execute them: there is no PHP interpreter and
  `manticore.conf` sets no `buddy_path`. The `.so` modules that share that directory
  (columnar, secondary, knn, galera) are retained, and the melange build now asserts
  both that no `.php` file survives and that those four libraries do.
- `nginx`: built from Wolfi `nginx-mainline` (1.31.3) instead of `nginx-stable`, and
  tagged `1.31` instead of `1.30`. `nginx-stable` is capped at 1.30.2 in Wolfi, which
  is affected by CVE-2026-42055 (heap buffer overflow in HTTP/2 proxying, CVSS 4.0
  9.2) and CVE-2026-48142; upstream fixed both in 1.30.3 / 1.31.2, but Wolfi has so
  far only published the fix on the mainline line. This will move back to
  `nginx-stable` once its patched build lands. Consumers pinning `nginx:1.30` must
  move to `nginx:1.31`.
- `redpanda`: 26.1.9 → 26.1.14. 26.1.9 ships a bundled krb5 under `/opt/redpanda/lib`
  affected by CVE-2026-40355 and CVE-2026-40356 (NegoEx message parsing; unauthenticated
  remote crash, CVSS 8.7), which upstream patched in 26.1.10 and fully resolved by moving
  to krb5 1.22.2 in 26.1.11. Because the broker vendors its own libraries, **no apk or
  Go-module scanner surfaced this** — the image scanned clean throughout. rpk's patched
  dependency set also now bumps `x/net`, `x/text`, `klauspost/compress` and `grpc`.
- `minio`: tagged `0.20260717.120751` — the committed lock had already picked up that
  build via relock, but `VERSION_minio` still carried the older `0.20260604.005411`,
  so the tag understated what shipped.
- `python-sodium`: **pip is no longer in the runtime image** — it moved to the `-dev`
  variant. An installer with network reach is the readiest
  arbitrary-code-fetch-and-execute primitive in an otherwise shell-less image, and
  nothing needs it once the app is built. Install dependencies in a `-dev` builder
  stage and copy `site-packages` across (see the image README). Dropping `py3.14-pip`
  also drops `py3.14-setuptools`, so `pkg_resources` / `_distutils_hack` are gone from
  the runtime image unless the app's own dependency tree installs setuptools.

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

[Unreleased]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/blackshieldpt/hardened-images/releases/tag/v0.1.0
