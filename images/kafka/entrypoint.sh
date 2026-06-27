#!/bin/bash
set -e

KAFKA_DATA_DIR="${KAFKA_DATA_DIR:-/var/kafka/data}"
KAFKA_CONFIG="${KAFKA_CONFIG:-/etc/kafka/server.properties}"
BIN=/usr/lib/kafka/bin

# Format KRaft storage on first boot.
if [ ! -f "${KAFKA_DATA_DIR}/meta.properties" ]; then
    CLUSTER_ID="${KAFKA_CLUSTER_ID:-$("${BIN}/kafka-storage.sh" random-uuid)}"
    echo "Formatting KRaft storage (cluster id: ${CLUSTER_ID})"
    "${BIN}/kafka-storage.sh" format -t "${CLUSTER_ID}" -c "${KAFKA_CONFIG}" --ignore-formatted
fi

exec "${BIN}/kafka-server-start.sh" "${KAFKA_CONFIG}" "$@"
