#!/usr/bin/env bash
# -------------------------------------------------------
# postgres/init-ckdb.sh
# Runs once on first container start (docker-entrypoint-initdb.d)
# -------------------------------------------------------
set -e

CKDB_USER="${CKDB_USER:-ckdb}"
CKDB_PASS="${CKDB_PASS:-CHANGE_ME}"
CKDB_NAME="${CKDB_NAME:-ckdb}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER ${CKDB_USER} WITH PASSWORD '${CKDB_PASS}';
    CREATE DATABASE ${CKDB_NAME} OWNER ${CKDB_USER};
    GRANT ALL PRIVILEGES ON DATABASE ${CKDB_NAME} TO ${CKDB_USER};
EOSQL

echo "ckdb database and user created."
