# Hardened OpenBao

Wolfi-based hardened [OpenBao](https://openbao.org) image (the open-source,
Vault-compatible secrets manager), assembled with apko from the Wolfi `openbao`
package, with a single-node config shipped via a small melange package.

## Details

| Property   | Value |
|------------|-------|
| Build      | apko (Wolfi openbao) + melange (config) |
| Version    | 2.5.4 |
| User       | openbao (UID 65532) |
| Shell      | none (distroless) |
| License    | MPL-2.0 |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8200 | HTTP | API |
| 8201 | TCP  | cluster |

## Usage

```bash
docker run -d -p 8200:8200 -v baodata:/openbao/data \
  hub.blackshield.pt/test_images/openbao:2.5.4
```

The default command is `server -config=/etc/openbao/openbao.hcl` (single-node
`file` storage at `/openbao/data`, HTTP listener on `:8200`). A fresh server
starts **uninitialized and sealed** — initialize and unseal it before use:

```bash
docker exec CONTAINER bao operator init
docker exec CONTAINER bao operator unseal <key>
```

## Configuration

Override the shipped config by bind-mounting your own at
`/etc/openbao/openbao.hcl`, or point the command elsewhere:

```bash
docker run -d -p 8200:8200 \
  -v "$PWD/my-openbao.hcl:/etc/openbao/openbao.hcl:ro" -v baodata:/openbao/data \
  hub.blackshield.pt/test_images/openbao:2.5.4
```

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and
curl + jq (see the repo README "Dev Variants"). For interactive use:

```bash
docker run -it --entrypoint /bin/sh hub.blackshield.pt/test_images/openbao:latest-dev
```

## Volumes

| Path | Purpose |
|------|---------|
| /openbao/data | `file` storage backend |

## Readiness

No in-image `HEALTHCHECK` (the image is distroless/shell-minimal). Probe from
your orchestrator: `curl -fsS http://HOST:8200/v1/sys/seal-status` (returns 200
even while sealed/uninitialized).

## Notes

- **No in-image TLS.** The default listener sets `tls_disable = "true"` —
  terminate TLS at your ingress/proxy, or mount a config with
  `tls_cert_file`/`tls_key_file`. Do not expose `:8200` untrusted without TLS.
- Runs non-root (UID 65532); OpenBao does not require `mlock`/`CAP_IPC_LOCK`.
- `BAO_ADDR=http://127.0.0.1:8200` is set so `docker exec … bao …` reaches the
  local server without `-address`.
- Version is the config-package tag; the actual `bao` version tracks the Wolfi
  `openbao` package (CVE-patched on rebuild).
