# Hardened PostgreSQL

Wolfi-based hardened PostgreSQL image, assembled with apko from the Wolfi `postgresql-18` package, with the entrypoint shipped via a small melange package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi postgresql-18) + melange (entrypoint) |
| Version    | 18 |
| User       | postgres (UID 65532) |
| Shell      | busybox |
| Image size | ~305 MB |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 5432 | TCP | PostgreSQL |

## Usage

```bash
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=secret -v pgdata:/var/lib/postgresql/data hub.blackshield.pt/test_images/postgresql:18
```

| Variable | Default | Description |
|----------|---------|-------------|
| POSTGRES_PASSWORD | unset | superuser password — required for first init |
| POSTGRES_USER | postgres | superuser name |

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/postgresql:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /var/lib/postgresql/data | Data directory |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from your orchestrator: `docker exec CONTAINER pg_isready -U postgres`.

## Notes

- Keeps `busybox` because the entrypoint (a `/bin/sh` script) runs `initdb` and `/docker-entrypoint-initdb.d/` scripts (`.sql`, `.sql.gz`, `.sh`).
- First-boot init runs only when the data directory is empty.
