# Hardened OpenBao 2.7

Wolfi-based hardened [OpenBao](https://openbao.org) 2.7 image (the open-source,
Vault-compatible secrets manager), built from upstream source with melange (pure
Go, CGO disabled) and assembled with apko. The same melange package ships a
single-node hardened config backed by integrated (raft) storage.

This is a separate image from [`openbao`](../openbao/) (2.6) because OpenBao 2.7
removed the `file` storage backend that image uses. Start new deployments here;
existing `openbao` deployments must migrate their data first (see below).

## Details

| Property   | Value |
|------------|-------|
| Build      | melange (OpenBao source, CGO disabled) + apko |
| Version    | 2.7.1 |
| Storage    | raft (integrated), single node `openbao-0` |
| User       | openbao (UID 65532) |
| Shell      | none (distroless) |
| License    | MPL-2.0 |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8200 | HTTP | API |
| 8201 | TCP  | cluster (raft) |

## Usage

```bash
docker run -d -p 8200:8200 -v baodata:/openbao/data \
  hub.blackshield.pt/test_images/openbao27:2.7.1
```

The default command is `server -config=/etc/openbao/openbao.hcl`. A fresh server
starts **uninitialized and sealed** — initialize and unseal it before use:

```bash
docker exec CONTAINER bao operator init
docker exec CONTAINER bao operator unseal <key>
```

## Migrating from `openbao` (2.6, file storage)

2.7 can no longer *run* on `file`, but its `bao operator migrate` still reads it as
a source (upstream removes that in 2.8), so the migration runs in this image:

1. Stop the 2.6 server.
2. Write a `migrate.hcl` (world-readable: the container reads it as UID 65532):

   ```hcl
   storage_source "file" {
     path = "/openbao/old"
   }
   storage_destination "raft" {
     path    = "/openbao/data"
     node_id = "openbao-0"
   }
   cluster_addr = "https://127.0.0.1:8201"
   ```

3. Run it with the old volume mounted elsewhere and a new one at `/openbao/data`:

   ```bash
   docker run --rm -v baodata:/openbao/old -v baoraft:/openbao/data \
     -v "$PWD/migrate.hcl:/migrate.hcl:ro" \
     hub.blackshield.pt/test_images/openbao27:2.7.1 operator migrate -config=/migrate.hcl
   ```

4. Start `openbao27` with `-v baoraft:/openbao/data` and unseal it with the
   existing keys. Tokens carry over.

Keep the old volume until the new server has been verified. `node_id` must match
the shipped config (`openbao-0`) unless you mount your own. A Docker named volume
takes its owner from the image; a bind mount or Kubernetes volume must be owned
by 65532 with mode 0700 (or use `fsGroup: 65532`).

## Configuration

Override the shipped config by bind-mounting your own at
`/etc/openbao/openbao.hcl`. The shipped one sets `api_addr`/`cluster_addr` to
loopback, which is right for a single node. Raft records the first node at its
`cluster_addr`, so a node bootstrapped from this config cannot later grow into a
cluster without a `peers.json` recovery: start a cluster from your own config,
with reachable addresses and `retry_join` blocks, from the beginning.

## Dev variant

A `:latest-dev` companion is built from the same source as prod plus a shell and
curl + jq (see the repo README "Dev Variants").

## Volumes

| Path | Purpose |
|------|---------|
| /openbao/data | raft storage |

## Notes

- **No in-image TLS.** The default listener sets `tls_disable = "true"` —
  terminate TLS at your ingress/proxy, or mount a config with
  `tls_cert_file`/`tls_key_file`.
- **Why raft, not pebbledb.** Upstream's own 2.7 packaging replaced `file` with the
  new non-HA `pebbledb` backend. This image uses raft because it is the long-standing
  integrated backend, supports `bao operator raft snapshot` for backups, and leaves
  the door open to HA. Mount your own config to use pebbledb instead.
- `disable_mlock = true`: raft memory-maps its database, and OpenBao recommends
  disabling mlock with integrated storage.
- Scanners cannot judge OpenBao's own CVEs here: advisories name
  `github.com/openbao/openbao`, and this binary's module is `.../openbao/v2`.
  Track OpenBao's release notes; the image follows 2.7.x patch releases.
- 2.7 also moved several built-in engines out of the main binary into
  [openbao-plugins](https://github.com/openbao/openbao-plugins): Kerberos, LDAP and
  RADIUS auth, and the LDAP secrets engine. They are not in this image.
- Built without the `ui` build tag, as with `openbao`.
