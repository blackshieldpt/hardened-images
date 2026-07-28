# Hardened Python (app base)

Wolfi-based hardened Python image, assembled with apko. Same hardened CPython as
the `python` image, plus the system libraries a typical web app loads at runtime
(libsodium, libmagic, DejaVu fonts) and **no default entrypoint** so the
downstream image sets its own `CMD` (e.g. gunicorn).

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi python-3.14; no pip — see Usage) |
| Version    | 3.14 |
| User       | nonroot (UID 65532) |
| Shell      | none (distroless) |
| Entrypoint | none (`[]`) — set your own `CMD` |
| Extra libs | libsodium, libmagic, ttf-dejavu, ld-linux (ldconfig) |
| HOME       | `/tmp` (world-writable, for non-root gunicorn control socket) |

## Why a separate image

- **`ctypes.util.find_library` works.** apko generates `/etc/ld.so.cache` at
  build (via the `ld-linux` trigger) and the image ships `/sbin/ldconfig`, so
  `find_library('sodium')` resolves both from the cache and via the
  `ldconfig -p` fallback CPython uses. No per-app `sitecustomize.py` shim needed.
- **No forced entrypoint.** Unlike `python:3.14` (entrypoint `python3.14`), this
  base leaves the entrypoint empty so the app image's `CMD` runs directly.
- **Writable HOME.** `HOME=/tmp` lets a non-root gunicorn create its control
  socket without extra config.

## Usage

The runtime image carries **no pip**. An installer with network reach is the readiest
arbitrary-code-fetch-and-execute primitive in an otherwise shell-less image (`pip
install --target /tmp` works even under a read-only rootfs), and nothing needs it once
the app is built. Install dependencies in a builder stage on the `-dev` variant — same
Wolfi CPython, so the installed tree is ABI-compatible — and copy `site-packages`
across:

```dockerfile
FROM hub.blackshield.pt/test_images/python-sodium:3.14-dev AS build
COPY requirements.txt /
RUN pip install --no-cache-dir -r /requirements.txt

FROM hub.blackshield.pt/test_images/python-sodium:3.14
COPY --from=build /usr/lib/python3.14/site-packages /usr/lib/python3.14/site-packages
COPY . /app
CMD ["gunicorn", "myapp:app", "--bind", "0.0.0.0:8000"]
```

```bash
# ad-hoc:
docker run --rm hub.blackshield.pt/test_images/python-sodium:3.14 \
  python3.14 -c "import ctypes.util as u; print(u.find_library('sodium'))"
```

## Dev variant

A `:latest-dev` companion adds a shell, gcc, git and **pip** (see the repo README "Dev
Variants"). It is the stage to install dependencies in. For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/python-sodium:latest-dev
```

## Readiness

Not applicable (base image — `docker run ... python3.14 --version`).

## Notes

- No entrypoint; `python3.14` is at `/usr/bin/python3.14`. No pip in the runtime
  image — it is `pip3.14` on the `-dev` variant.
- pip removal is defence in depth, not a boundary: `python-3.14-base` hard-depends on
  `py3-pip-wheel`, so `/usr/share/python-wheels/pip-*.whl` still ships and
  `python -m ensurepip --user` restores a working pip into `HOME=/tmp` offline. That
  takes code execution the attacker must already have; what the removal buys is that
  pip is not simply *there* for the app user to reach.
- Workdir is `/app`; `HOME=/tmp`.
- System libs are loaded dynamically — install the matching Python bindings
  (e.g. `pysodium`, `python-magic`) in the `-dev` builder stage.
