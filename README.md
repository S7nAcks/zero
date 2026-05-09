# ckpool + ckdb — Docker Setup

Runs **ckpool** and **ckdb** (built from the official Bitbucket source) alongside a
**PostgreSQL 16** sidecar. Your **bitcoind** lives outside Docker.

---

## Directory layout

```
ckpool-docker/
├── ckpool/
│   ├── Dockerfile       ← multi-stage build (builder + slim runtime)
│   └── entrypoint.sh    ← starts ckdb, waits for its socket, then ckpool
├── conf/
│   ├── ckpool.conf      ← ckpool configuration (edit before first run)
│   └── ckdb.conf        ← ckdb / PostgreSQL connection config
├── postgres/
│   └── init-ckdb.sh     ← creates the ckdb database + user on first start
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Quick start

### 1. Configure your secrets

```bash
cp .env.example .env
# Edit .env — at minimum change POSTGRES_PASSWORD and CKDB_PASS
```

### 2. Configure ckpool

Edit `conf/ckpool.conf` and replace the placeholders:

| Placeholder | Replace with |
|---|---|
| `BITCOIND_HOST` | IP/hostname of your bitcoind (use `host.docker.internal` if local) |
| `BITCOIND_RPCPORT` | RPC port, typically `8332` |
| `BITCOIND_RPCUSER` | Your bitcoind `rpcuser` |
| `BITCOIND_RPCPASS` | Your bitcoind `rpcpassword` |
| `YOUR_BITCOIN_ADDRESS` | Payout address for block rewards |
| `BITCOIND_ZMQPORT` | ZMQ port (e.g. `28332`) — remove the `zmqblock` line if not using ZMQ |

### 3. Configure ckdb

Edit `conf/ckdb.conf`:
- Set `dbpass` to match `CKDB_PASS` in your `.env`
- `dbhost` defaults to `db` (the Compose service name) — leave it unless you move Postgres

### 4. Allow ckpool in bitcoind

If bitcoind is running on the host, add this to `bitcoin.conf`:

```ini
rpcallowip=172.16.0.0/12   # Docker bridge range
rpcbind=0.0.0.0
```

Or bind to the Docker host gateway specifically:

```ini
rpcbind=0.0.0.0
rpcallowip=172.17.0.1      # usually the docker0 gateway
```

### 5. Build and run

```bash
docker compose build
docker compose up -d
```

First build compiles ckpool from source — takes a few minutes.

### 6. Check logs

```bash
docker compose logs -f ckpool
```

---

## Ports

| Port | Service |
|---|---|
| `3333` | Stratum (miners connect here) |
| `4028` | ckpool management API (`ckpmsg`) |
| `5432` | PostgreSQL (localhost only) |

---

## Startup sequence

The entrypoint does the following in order:

1. Waits for PostgreSQL to accept connections (TCP check on port 5432)
2. Starts **ckdb** in the background
3. Waits for ckdb's Unix socket (`/zero/ckpool/run/ckdb/listener`) to appear
4. Starts **ckpool** in the foreground (PID 1 for clean signal handling)

---

## Useful commands

```bash
# Rebuild after ckpool source updates
docker compose build --no-cache ckpool

# Send a message via ckpmsg
docker compose exec ckpool ckpmsg -s /zero/ckpool/run/ckpool/listener -c ping

# Connect psql to the ckdb database
docker compose exec db psql -U ckdb -d ckdb

# View ckdb logs
docker compose exec ckpool cat /zero/ckpool/log/ckdb.log

# Graceful stop
docker compose stop
```

---

## Updating ckpool

```bash
docker compose build --no-cache ckpool
docker compose up -d ckpool
```

The build always pulls the latest commit from the configured `BRANCH` (default: `master`).

---

## Volumes

| Volume | Contents |
|---|---|
| `pgdata` | PostgreSQL data directory |
| `ckpool-logs` | ckpool and ckdb log files (`/zero/ckpool/log`) |

All volumes persist across container restarts. To wipe and start fresh:

```bash
docker compose down -v
```
