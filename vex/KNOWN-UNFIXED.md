# Findings with no available fix

A register of findings that the scan reports, that are **real**, and that no
version bump can currently clear. They are not waived: no VEX statement suppresses
them, they appear in every scan report, and the gate still counts them. This file
exists so the same findings are not re-investigated from scratch every time
someone reads a scan.

A finding belongs here only when the fix does not exist — not when it exists and is
inconvenient. If a fix ships, the entry is deleted and the pin moves.

Nothing here is Critical; if one of these is ever rated Critical, it blocks the
gate and becomes a decision (bump, waive with justification, or drop the package),
not an entry.

| Finding | Where | Why it cannot be fixed | Re-check when |
|---|---|---|---|
| `CVE-2026-8674`, `CVE-2026-86805`, `CVE-2026-89092` (Medium), `CVE-2026-95818` (Low) | glibc, in every image that carries it | No fixed version published in Wolfi. The daily relock picks up a patched glibc the moment one exists. | Wolfi publishes a glibc rebuild naming these |
| `CVE-2025-15367`, `CVE-2026-87910` (Medium) | `python-3.14`, in python and python-sodium | No fixed version published in Wolfi; 3.14.8 is the newest. | Wolfi publishes a python-3.14 naming these |
| `CVE-2026-90781`, `CVE-2026-96674`, `CVE-2026-96675` (Medium) | `alsa-lib`, pulled in by the JRE in kafka and zookeeper | No fixed version published in Wolfi. | Wolfi publishes an alsa-lib rebuild naming these |
| `GO-2026-4887` / `CVE-2026-41567`, `CVE-2026-42306` (High) | `github.com/docker/docker` v28.5.2, in redpanda's `rpk` | The advisory points at 29.3.1, but `docker/docker` publishes no v29 module path — it moved to `moby/moby` — so `go get` cannot reach it. Only linked for `rpk container`, which builds local dev clusters and is never run by this broker image. Trivy reports it under the two CVE ids. | rpk drops the dependency, or docker/docker publishes a v29 module path |
| `CVE-2026-97687`, `CVE-2026-97689` (High, urllib3 2.7.0), `GHSA-6v7p-g79w-8964` (High, msgpack 1.1.2), `CVE-2025-47273` (High, setuptools 70.3.0) | vendored inside pip, in python | pip 26.2.1 — the newest release, and what Wolfi ships — vendors exactly these versions (`pip/_vendor/vendor.txt`). Seen only by trivy, which reads the vendor list. | pip releases with newer vendored copies and Wolfi rebuilds py3.14-pip |
| `GO-2026-5932` (unrated) | `golang.org/x/crypto` v0.56.0, in openbao, openbao27 and others | No fixed version named in the advisory yet. | The advisory names a fixed x/crypto release |

The python and `docker/docker` CVE-id rows are visible only since `scan.sh` started
running trivy with `--detection-priority comprehensive` (2026-10-03); before that,
trivy skipped every file an apk package owns.

`scripts/check-updates.sh` reports the Wolfi side of this independently: a package
whose advisory data names a fix that was never published shows up as
`UNOBTAINABLE FIX`, and one that has stopped being rebuilt as `FROZEN`.

Last reviewed: 2026-10-03.
