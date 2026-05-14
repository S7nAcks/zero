#!/usr/bin/env bash
# -------------------------------------------------------
# entrypoint.sh — starts ckdb then ckpool
# -------------------------------------------------------
set -euo pipefail

CKPOOL_CONF="${CKPOOL_CONF:-/zero/.pools/ckpool/conf/ckpool.conf}"
CKDB_CONF="${CKDB_CONF:-/zero/ckpool/.pools/conf/ckdb.conf}"
CKDB_SOCKDIR="${CKDB_SOCKDIR:-/zero/ckpool/.pools/run/ckdb}"
CKPOOL_SOCKDIR="${CKPOOL_SOCKDIR:-/zero/ckpool/.pools/run/ckpool}"
CKPOOL_LOGDIR="${CKPOOL_LOGDIR:-/zero/ckpool/.pools/log}"
CKDB_LOGDIR="${CKDB_LOGDIR:-/zero/ckpool/.pools/log}"

log() { echo "[entrypoint] $*"; }

# ── wait for PostgreSQL ───────────────────────────────
wait_for_postgres() {
    local host="${PGHOST:-db}"
    local port="${PGPORT:-5432}"
    local retries=30
    log "Waiting for PostgreSQL at ${host}:${port} ..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            log "ERROR: PostgreSQL did not become available in time."
            exit 1
        fi
        sleep 2
    done
    log "PostgreSQL is up."
}

# ── start ckdb ────────────────────────────────────────
start_ckdb() {
    log "Starting ckdb ..."
    ckdb \
        -c "${CKDB_CONF}" \
        -s "${CKDB_SOCKDIR}" \
        -L "${CKDB_LOGDIR}" \
        &
    CKDB_PID=$!
    log "ckdb PID: ${CKDB_PID}"

    # Give ckdb a moment to create its socket
    local retries=20
    local sock="${CKDB_SOCKDIR}/listener"
    log "Waiting for ckdb socket at ${sock} ..."
    while [ ! -S "$sock" ] && [ ! -e "$sock" ]; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            log "WARNING: ckdb socket not detected; proceeding anyway."
            break
        fi
        sleep 1
    done
    log "ckdb ready."
}

# ── start ckpool ──────────────────────────────────────
start_ckpool() {
    log "Starting ckpool ..."
    exec ckpool \
        -c "${CKPOOL_CONF}" \
        -s "${CKPOOL_SOCKDIR}" \
        -S "${CKDB_SOCKDIR}" \
        -L "${CKPOOL_LOGDIR}"
}

# ── handle shutdown ───────────────────────────────────
cleanup() {
    log "Shutting down ..."
    if [ -n "${CKDB_PID:-}" ]; then
        kill "$CKDB_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT TERM INT

# ── main ──────────────────────────────────────────────
wait_for_postgres
start_ckdb
start_ckpool
