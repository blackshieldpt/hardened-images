# Hardened Python 3.15

Wolfi-based hardened Python image, assembled with apko from the Wolfi `python-3.15` package.

Same image as [`python`](../python/), which stays on 3.14, on the 3.15 line.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi python-3.15, py3.15-pip) |
| Version    | 3.15 |
| User       | nonroot (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~132 MB |

## Usage

```bash
docker run --rm -v $(pwd):/app hub.blackshield.pt/test_images/python315:3.15 /app/main.py
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and gcc + git (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/python315:latest-dev
```

## Readiness

Not applicable (runtime image — `docker run ... --version`)

## Notes

- Entrypoint is `/usr/bin/python3.15`; workdir `/app`.
- pip is available as `pip3.15` (`docker run --entrypoint pip3.15 IMAGE --version`).
