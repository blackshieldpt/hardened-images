# Hardened OpenBao 2.7 config: single-node integrated (raft) storage, HTTP
# listener with no in-image TLS — terminate TLS at your ingress/proxy, or mount
# your own config with tls_cert_file/tls_key_file. Override by bind-mounting a
# replacement at /etc/openbao/openbao.hcl (or point `bao server -config=` elsewhere).
#
# 2.7 removed the `file` backend the 2.6 image uses. Raft rather than upstream's
# new pebbledb: it is the established integrated backend, supports raft snapshots
# for backups, and can be HA. This config is a single node bound to loopback; a
# cluster needs its own config with reachable addresses from the start.
ui = false

# Integrated storage memory-maps its database; mlock would pin all of it in RAM.
# OpenBao recommends disabling it with raft.
disable_mlock = true

storage "raft" {
  path    = "/openbao/data"
  node_id = "openbao-0"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = "true"
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
