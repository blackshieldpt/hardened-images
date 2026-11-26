#!/bin/sh
set -e

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    if [ -n "${POSTGRES_PASSWORD:-}" ]; then
        pwfile=$(mktemp)
        printf '%s' "$POSTGRES_PASSWORD" > "$pwfile"
        initdb --username="${POSTGRES_USER:-postgres}" --pwfile="$pwfile" --auth-host=scram-sha-256 --auth-local=trust
        rm -f "$pwfile"
    else
        initdb --username="${POSTGRES_USER:-postgres}" --auth-host=scram-sha-256 --auth-local=trust
    fi

    {
        echo "host all all 0.0.0.0/0 scram-sha-256"
        echo "host all all ::/0 scram-sha-256"
    } >> "$PGDATA/pg_hba.conf"

    echo "listen_addresses = '*'" >> "$PGDATA/postgresql.conf"

    if [ -d /docker-entrypoint-initdb.d ]; then
        pg_ctl -D "$PGDATA" -w start -o "-c listen_addresses=''"
        for f in /docker-entrypoint-initdb.d/*; do
            case "$f" in
                *.sql)    echo "Running $f"; psql --username "${POSTGRES_USER:-postgres}" -f "$f" ;;
                *.sql.gz) echo "Running $f"; gunzip -c "$f" | psql --username "${POSTGRES_USER:-postgres}" ;;
                *.sh)     echo "Running $f"; . "$f" ;;
            esac
        done
        pg_ctl -D "$PGDATA" -w stop
    fi
fi

exec "$@"
