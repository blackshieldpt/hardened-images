# Hardened Python

Wolfi-based hardened Python image, assembled with apko from the Wolfi `python-3.14` package.

**This image stays on 3.14.** Python 3.15 ships separately as
[`python315`](../python315/), so moving an app across is a choice of image rather
than a tag that changes underneath it.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi python-3.14, py3.14-pip) |
| Version    | 3.14 |
| User       | nonroot (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~84 MB |

## Usage

```bash
docker run --rm -v $(pwd):/app hub.blackshield.pt/test_images/python:3.14 /app/main.py
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and gcc + git (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/python:latest-dev
```

## Readiness

Not applicable (runtime image — `docker run ... --version`)

## Notes

- Entrypoint is `/usr/bin/python3.14`; workdir `/app`.
- pip is available as `pip3.14` (`docker run --entrypoint pip3.14 IMAGE --version`).
