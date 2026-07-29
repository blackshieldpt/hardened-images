# Hardened Valkey

Wolfi-based hardened Valkey image, assembled with apko from the Wolfi `valkey-9.1` package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi valkey-9.1, valkey-9.1-cli) |
| Version    | 9.1 |
| User       | valkey (UID 65532) |
| Shell      | bash (unavoidable: `valkey-9.1` → `posix-libc-utils` → `bash`); no `/bin/sh` |
| Image size | ~23 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 6379 | TCP      | Valkey/RESP |

## Usage

```bash
docker run -d -p 6379:6379 hub.blackshield.pt/test_images/valkey:9.1
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/valkey:latest-dev
```

## Volumes

`/data` (workdir)

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `docker exec CONTAINER valkey-cli ping`

## Notes

- Protected mode is enabled by default; pass `--requirepass secret` for authenticated access.
- `valkey-cli` is included in the image.
