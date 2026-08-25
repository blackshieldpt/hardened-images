# Hardened Go

Wolfi-based hardened Go image, assembled with apko from the Wolfi `go-1.27` package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi go-1.27) |
| Version    | 1.27 |
| User       | nonroot (UID 65532) |
| Shell      | none |
| Image size | ~193 MB |

## Usage

```bash
# Pure-Go build (CGO_ENABLED=0)
docker run --rm -v $(pwd):/app -w /app hub.blackshield.pt/ocicore/go:1.27 build -o /out/app .

```

`GOPATH` is `/app/go`, `GOBIN` is `/app/bin` (on `PATH`).

## Building applications (multi-stage)

```dockerfile
FROM hub.blackshield.pt/ocicore/go:1.27-dev AS build
WORKDIR /app
COPY --chown=65532:65532 . .
RUN go mod tidy && go build -o /out/app

FROM hub.blackshield.pt/ocicore/go:1.27
COPY --from=build /out/app /usr/bin/app
ENTRYPOINT ["/usr/bin/app"]
```

`--chown=65532` is needed because the dev variant runs as UID 65532 — files copied by
Docker are root-owned, and `go mod tidy` must be able to update `go.mod`/`go.sum`.

## Permission caveat (`docker run` with bind mounts)

The image runs as UID 65532. Bind-mounted project files are root-owned on the host and
read-only to the container user. For `docker run` one-shot builds:

```bash
# Pre-resolve dependencies on the host, then build
go mod tidy && go mod download
docker run --rm -v $PWD:/app -w /app hub.blackshield.pt/ocicore/go:1.27 build -o /tmp/app .
```

Or make the directory world-readable: `chmod -R o+rX $PWD`.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and gcc + git
(see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/ocicore/go:latest-dev
```

## Readiness

Not applicable (runtime image — `docker run ... go version`)

## Notes

- Entrypoint is `/usr/bin/go`; workdir `/app`.
- The `go-1.27` package has no runtime dependencies, so the prod image ships no shell and no C toolchain. CGO builds need the `-dev` variant (gcc).
