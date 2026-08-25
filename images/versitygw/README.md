# Hardened VersityGW

Wolfi-based hardened [VersityGW](https://github.com/versity/versitygw) image (the
Versity S3 Gateway, an S3 protocol translator over POSIX/other backends), built
with melange from source (versitygw isn't packaged in Wolfi) and assembled with
apko. Pure-Go, static (CGO disabled).

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (from source) |
| Version    | 1.7.0 |
| User       | versitygw (UID 65532) |
| Shell      | none (distroless) |
| License    | Apache-2.0 |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 7070 | HTTP | S3 API |

## Usage

```bash
docker run -d -p 7070:7070 -v vgwdata:/data \
  -e ROOT_ACCESS_KEY=admin -e ROOT_SECRET_KEY=change-me \
  hub.blackshield.pt/test_images/versitygw:1.7.0
```

The default command is `--health /_health posix /data` — the POSIX backend
serves `/data` as S3 (each top-level directory is a bucket), with a health
endpoint at `GET /_health`. `ROOT_ACCESS_KEY`/`ROOT_SECRET_KEY` set the admin
credentials for the single-account mode; without them the gateway logs a warning
and starts with no configured account.

## Configuration

Point the command at a different backend or tune the gateway via flags/env
(`VGW_PORT`, `VGW_REGION`, `VGW_MAX_CONNECTIONS`, …). For example, an in-image
different data path:

```bash
docker run -d -p 7070:7070 -v vgwdata:/srv \
  -e ROOT_ACCESS_KEY=admin -e ROOT_SECRET_KEY=change-me \
  hub.blackshield.pt/test_images/versitygw:1.7.0 --health /_health posix /srv
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and
curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/versitygw:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /data | POSIX backend root (buckets are top-level directories) |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from
your orchestrator: `curl -fsS http://HOST:7070/_health`

## Notes

- **No in-image TLS.** The default listener is plain HTTP — terminate TLS at your
  ingress/proxy, or pass `--cert`/`--key` (and mount the material). Do not expose
  `:7070` untrusted without TLS.
- The POSIX backend `chdir`s into its data directory, so pass an absolute path
  (the default `/data` is absolute).
- Runs non-root (UID 65532); `/data` is owned by that UID.
