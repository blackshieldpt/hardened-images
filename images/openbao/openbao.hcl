# Hardened OpenBao config: single-node file storage, HTTP listener with no
# in-image TLS — terminate TLS at your ingress/proxy, or mount your own config
# with tls_cert_file/tls_key_file. Override by bind-mounting a replacement at
# /etc/openbao/openbao.hcl (or point `bao server -config=` elsewhere).
ui = false

storage "file" {
  path = "/openbao/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr = "http://0.0.0.0:8200"
