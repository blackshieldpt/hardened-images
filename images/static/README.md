# Hardened static

The minimal runtime base: a filesystem skeleton and a CA trust store, and
nothing else. It exists to be the `FROM` line under a statically linked binary.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi `wolfi-baselayout`, `ca-certificates-bundle`) |
| Version    | 1 (see *Versioning* below) |
| User       | nonroot (UID 65532) |
| Work dir   | `/app`, owned by 65532 |
| Shell      | none |
| Entrypoint | none — the image is not runnable on its own |
| Image size | ~215 kB |

Two packages. No shell, no libc beyond the baselayout, no package manager, no
interpreter, no compiler. `SSL_CERT_FILE` is set to
`/etc/ssl/certs/ca-certificates.crt`, so a Go binary's `x509.SystemCertPool()`
resolves without configuration.

## Usage

For anything self-contained: `CGO_ENABLED=0` Go, Rust against musl, Zig, or a
statically linked C binary.

```dockerfile
FROM ghcr.io/blackshieldpt/go:1.27-dev AS build
WORKDIR /app
COPY --chown=65532:65532 . .
RUN CGO_ENABLED=0 go build -trimpath -o /tmp/app .

FROM ghcr.io/blackshieldpt/static:1
COPY --from=build --chown=65532:65532 /tmp/app /app/app
ENTRYPOINT ["/app/app"]
```

`/app` is pre-created and owned by UID 65532. That matters: a `WORKDIR` Docker
has to create itself is made root-owned, and the UID 65532 process then cannot
write to it.

### When not to use it

- **The binary links libc dynamically.** There is no `glibc-dynamic` here on
  purpose — carrying one would make this a worse copy of a real runtime instead
  of a floor. Use the matching language image (`go`, `python`, `node`) or add
  the runtime package to a dedicated image.
- **You need to `docker exec` in.** There is no shell. Use
  `ghcr.io/blackshieldpt/static:1-dev` for that, which is this image plus
  busybox, bash, `apk`, `curl`, `wget` and `jq` — for debugging, never for
  production.
- **Something must run at build time in the final stage.** There is no `RUN`
  target: no shell means no `RUN` in a stage built `FROM` this image. Create
  directories in an earlier stage and `COPY --from` them in.

## Creating directories without a shell

A `RUN mkdir` cannot work here. Prepare the tree in a stage that does have a
shell and copy it across, which also fixes ownership in one step:

```dockerfile
FROM ghcr.io/blackshieldpt/go:1.27-dev AS prep
USER 0
RUN mkdir -p /skel/data /skel/config

FROM ghcr.io/blackshieldpt/static:1
COPY --from=prep --chown=65532:65532 /skel/ /app/
```

Named volumes mounted at those paths inherit the ownership, so the container can
write to a freshly created volume.

## Versioning

There is no upstream project to track, so the version line is ours. `1` changes
only when the image's *contract* changes — the runtime user, the work dir, the
package set. Content patches (a `ca-certificates` refresh, a baselayout fix)
move `:1` and `:latest` without a version bump, which is what the immutable
`:1-<commit>` tag and the digest are for. Pin production to one of those.

## Tests

`test.sh` cannot `docker run` or `docker exec` this image, so it exports the
container's root filesystem and reads the tar listing from the host. It asserts
the CA bundle is present and populated, that no shell, package manager,
interpreter or toolchain binary exists, that `/app` is owned by 65532, and that
the image stays under 1 MiB. It then compiles a small `CGO_ENABLED=0` Go binary,
builds a throwaway image `FROM` this one, and checks that it runs as UID 65532
and can load the system cert pool — the property the image exists to provide.
