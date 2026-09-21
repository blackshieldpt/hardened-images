# Findings with no available fix

A register of findings that the scan reports, that are **real**, and that no
version bump can currently clear. They are not waived: no VEX statement suppresses
them, they appear in every scan report, and the gate still counts them. This file
exists so the same three findings are not re-investigated from scratch every time
someone reads a scan.

A finding belongs here only when the fix does not exist — not when it exists and is
inconvenient. If a fix ships, the entry is deleted and the pin moves.

Nothing here is Critical; if one of these is ever rated Critical, it blocks the
gate and becomes a decision (bump, waive with justification, or drop the package),
not an entry.

| Finding | Where | Why it cannot be fixed | Re-check when |
|---|---|---|---|
| `CVE-2026-19499` (High), `CVE-2026-19542`, `CVE-2026-89092` (Medium) | glibc, in every image that carries it | No fixed version published in Wolfi. The daily relock picks up a patched glibc the moment one exists. | Wolfi publishes a glibc rebuild naming these |
| `GHSA-2v4p-qf9q-27wj` (High) | `google.golang.org/grpc`, in etcd, nginx-acme, openbao, redpanda, minio | No released fix. Grype names `1.85.0-dev.0.20260825072537-93e31b48545e` — a pre-release commit, not a version anything should pin. v1.84.0 is the newest release and is what the floor pins name. | grpc cuts a release ≥ 1.85.0 |
| `GO-2026-4887` (High) | `github.com/docker/docker` v28.5.2, in redpanda's `rpk` | The advisory points at 29.3.1, but `docker/docker` publishes no v29 module path — it moved to `moby/moby` — so `go get` cannot reach it. Only linked for `rpk container`, which builds local dev clusters and is never run by this broker image. | rpk drops the dependency, or docker/docker publishes a v29 module path |

`scripts/check-updates.sh` reports the Wolfi side of this independently: a package
whose advisory data names a fix that was never published shows up as
`UNOBTAINABLE FIX`, and one that has stopped being rebuilt as `FROZEN`.

Last reviewed: 2026-09-21.
