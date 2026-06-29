# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once tagged.

## [Unreleased]

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

[Unreleased]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/blackshieldpt/hardened-images/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/blackshieldpt/hardened-images/releases/tag/v0.1.0
