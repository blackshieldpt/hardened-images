#!/bin/sh
set -e

# Honor the upstream CLICKHOUSE_* user/password contract by generating a
# users.d override (ClickHouse natively merges /etc/clickhouse-server/users.d/*.xml).
# Stateless: regenerated every boot, removed when no vars are set, so behavior is
# unchanged from stock when the container gets no CLICKHOUSE_* configuration.
ENV_XML=/etc/clickhouse-server/users.d/00-env.xml

if [ "${CLICKHOUSE_SKIP_USER_SETUP:-0}" != "1" ] && \
   { [ -n "${CLICKHOUSE_USER:-}" ] || [ -n "${CLICKHOUSE_PASSWORD:-}" ] || \
     [ -n "${CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT:-}" ]; }; then

    user="${CLICKHOUSE_USER:-default}"
    # The username becomes an XML element name, which cannot be escaped — constrain it.
    case "$user" in
        ''|*[!A-Za-z0-9_]*)
            echo "entrypoint: invalid CLICKHOUSE_USER '$user' (allowed: A-Za-z0-9_)" >&2
            exit 1 ;;
    esac

    if [ -n "${CLICKHOUSE_PASSWORD:-}" ]; then
        # printf, not echo: a trailing newline would change the hash.
        hash=$(printf %s "$CLICKHOUSE_PASSWORD" | sha256sum | cut -d' ' -f1)
        cred="<password_sha256_hex>${hash}</password_sha256_hex>"
    else
        cred="<password></password>"
    fi

    [ "${CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT:-0}" = "1" ] && access=1 || access=0

    # replace="replace" swaps the whole user node, dropping the stock empty
    # <password> so ClickHouse never sees two auth methods for one user.
    cat > "$ENV_XML" <<EOF
<clickhouse>
  <users>
    <${user} replace="replace">
      ${cred}
      <networks><ip>::/0</ip></networks>
      <profile>default</profile>
      <quota>default</quota>
      <access_management>${access}</access_management>
      <named_collection_control>${access}</named_collection_control>
      <show_named_collections>${access}</show_named_collections>
      <show_named_collections_secrets>${access}</show_named_collections_secrets>
    </${user}>
  </users>
</clickhouse>
EOF
else
    # No user vars (or explicitly skipped): drop any override from a previous boot.
    rm -f "$ENV_XML"
fi

exec clickhouse-server --config-file=/etc/clickhouse-server/config.xml "$@"
