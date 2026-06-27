#!/bin/sh
set -e

SUPERUSER="${REDPANDA_SUPERUSER:-admin}"
SUPERUSER_PASSWORD="${REDPANDA_SUPERUSER_PASSWORD:-}"

if [ -z "$SUPERUSER_PASSWORD" ]; then
    echo "ERROR: REDPANDA_SUPERUSER_PASSWORD must be set"
    exit 1
fi

ADVERTISE_HOST="${REDPANDA_ADVERTISE_HOST:-$(hostname)}"
sed -i "s/SUPERUSER_PLACEHOLDER/$SUPERUSER/" /etc/redpanda/redpanda.yaml
sed -i "s/127\.0\.0\.1/$ADVERTISE_HOST/g" /etc/redpanda/redpanda.yaml

(
    until rpk cluster health --api-urls localhost:9644 2>/dev/null; do
        sleep 1
    done
    rpk acl user create "$SUPERUSER" -p "$SUPERUSER_PASSWORD" \
        --mechanism SCRAM-SHA-256 --api-urls localhost:9644 2>/dev/null || true
) &

exec redpanda --redpanda-cfg /etc/redpanda/redpanda.yaml "$@"
