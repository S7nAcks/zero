#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# entrypoint.sh — starts cron (ckstats ingester) then ckpool
#
# Required environment variables:
#   CKPOOL_CONFIG   path to ckpool.conf   (default: /zero/ckpool/ckpool.conf)
#   DB_HOST         postgres hostname      (default: postgres)
#   DB_PORT         postgres port          (default: 5432)
#   DB_NAME         postgres database      (default: ckstats)
#   DB_USER         postgres user          (default: ckpool)
#   DB_PASSWORD     postgres password      (REQUIRED)
#
# Optional:
#   API_URL         ckpool log dir for ckstats  (default: /zero/ckpool/log)
#   DB_SSL          true/false                  (default: false)
#   CKPOOL_LOGLEVEL 0-5                         (default: 5)
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

log() { echo "[entrypoint] $(date -u '+%Y-%m-%dT%H:%M:%SZ')  $*"; }
die() { log "FATAL: $*" >&2; exit 1; }

# ── defaults ──────────────────────────────────────────────────────────────
CKPOOL_CONFIG="${CKPOOL_CONFIG:-/zero/ckpool/ckpool.conf}"
DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-ckstats}"
DB_USER="${DB_USER:-ckpool}"
DB_PASSWORD="${DB_PASSWORD:-}"
API_URL="${API_URL:-/zero/ckpool/log}"
DB_SSL="${DB_SSL:-false}"
CKPOOL_LOGLEVEL="${CKPOOL_LOGLEVEL:-5}"

# ── validate ──────────────────────────────────────────────────────────────
[[ -z "${DB_PASSWORD}" ]]   && die "DB_PASSWORD is not set"
[[ -f "${CKPOOL_CONFIG}" ]] || die "ckpool.conf not found at ${CKPOOL_CONFIG} — mount it via -v"

# ── write ckstats .env ────────────────────────────────────────────────────
cat > /ckstats/.env <<ENVEOF
API_URL="${API_URL}"
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${DB_NAME}"
DB_SSL="${DB_SSL}"
ENVEOF
chmod 600 /zero/ckstats/.env
chown ckpool:ckpool /zero/ckstats/.env
log ".env written for ckstats"

# ── wait for PostgreSQL ───────────────────────────────────────────────────
log "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
attempt=0
until PGPASSWORD="${DB_PASSWORD}" pg_isready \
        -h "${DB_HOST}" -p "${DB_PORT}" \
        -U "${DB_USER}" -d "${DB_NAME}" -q 2>/dev/null; do
    attempt=$(( attempt + 1 ))
    (( attempt > 30 )) && die "PostgreSQL not ready after 30 attempts"
    log "  not ready yet (attempt ${attempt}/30), retrying in 3s..."
    sleep 3
done
log "PostgreSQL is ready"

# ── run migrations (idempotent — safe on every start) ─────────────────────
log "Running ckstats database migrations..."
cd /ckstats
su -s /bin/bash ckpool -c \
    "cd /ckstats && node_modules/.bin/typeorm migration:run -d scripts/ormconfig.js" \
    || log "WARNING: migrations failed — check DB credentials"
log "Migrations done"

# ── make env available inside cron (cron doesn't inherit shell env) ───────
printenv | grep -E '^(API_URL|DB_|NODE_)' >> /etc/environment

# ── start cron (jobs in /etc/cron.d/ckstats run as ckpool user) ──────────
log "Starting cron for ckstats ingestion..."
service cron start
log "Cron started"

# ── tail ckstats logs to stdout ───────────────────────────────────────────
touch /zero/ckstats/logs/seed.log /zero/ckstats/logs/users.log /zero/ckstats/logs/cleanup.log
tail -F /zero/ckstats/logs/seed.log /zero/ckstats/logs/users.log /zero/ckstats/logs/cleanup.log &
TAIL_PID=$!

# ── signal handler ────────────────────────────────────────────────────────
_shutdown() {
    log "Caught signal — shutting down..."
    kill -TERM "${CKPOOL_PID:-}" 2>/dev/null || true
    kill "${TAIL_PID:-}" 2>/dev/null || true
    service cron stop 2>/dev/null || true
    wait "${CKPOOL_PID:-}" 2>/dev/null || true
    log "Shutdown complete"
    exit 0
}
trap '_shutdown' SIGTERM SIGINT SIGHUP

# ── start ckpool (drop to ckpool user) ────────────────────────────────────
log "Starting ckpool..."
su -s /bin/bash ckpool -c \
    "exec /zero/ckpool/ckpool -c '${CKPOOL_CONFIG}' -l ${CKPOOL_LOGLEVEL}" &
CKPOOL_PID=$!
log "ckpool started (PID ${CKPOOL_PID})"

# ── monitor: exit container if ckpool dies ────────────────────────────────
while true; do
    if ! kill -0 "${CKPOOL_PID}" 2>/dev/null; then
        log "ERROR: ckpool exited unexpectedly"
        _shutdown
        exit 1
    fi
    sleep 5
done
