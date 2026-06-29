# Hardened Node.js 24

Wolfi-based hardened Node.js image, assembled with apko from the Wolfi `nodejs-24` package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi nodejs-24, npm) |
| Version    | 24 |
| User       | nonroot (UID 65532) |
| Shell      | none (distroless) |
| Image size | ~158 MB |

## Usage

```bash
docker run --rm -v $(pwd):/app -w /app hub.blackshield.pt/test_images/node24:24 index.js
```

## Building applications (multi-stage)

**The prod image is distroless (no `/bin/sh`), so `RUN npm …` does not work there.**
Use the dev variant for the build stage, then copy artifacts into the prod image:

```dockerfile
FROM hub.blackshield.pt/test_images/node24:24-dev AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM hub.blackshield.pt/test_images/node24:24
WORKDIR /app
COPY --from=build /app /app
CMD ["dist/server.js"]
```

The dev image ships `gcc`, `make`, and `git` for dependency compilation. If you build
native addons (e.g. `bcrypt`, `sharp` from source), you also need `python3` — it's
not included by default; `node-gyp` will fail without it.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and gcc + git (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/node24:latest-dev
```

## Readiness

Not applicable (runtime image — `docker run ... node --version`)

## Notes

- Entrypoint is `/usr/bin/node`; workdir `/app`.
- `npm` (11.x) is included but cannot self-execute without a shell — invoke via `docker run --entrypoint node IMAGE /usr/bin/npm …` on prod, or use the dev variant for `RUN npm` in a Dockerfile.
