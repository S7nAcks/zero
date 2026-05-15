# ═══════════════════════════════════════════════════════
# ckpool + ckstats
#   ckpool  — built from official bitbucket ckolivas
#   ckstats — built from official github mrv777
# Target: linux/amd64  |  Base: Ubuntu 24.04 LTS
# ═══════════════════════════════════════════════════════
FROM ubuntu:22.04 AS builder

# ── set directory ──────────────────────────────────────
WORKDIR "/zero"

# ── build dependencies ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        git \
        libtool \
        libzmq3-dev \
        pkg-config \
        yasm \
    && rm -rf /var/lib/apt/lists/*

# ── get sources ────────────────────────────────────────
RUN git clone --recursive "https://bitbucket.org/ckolivas/ckpool" "/zero/ckpool"
RUN git clone --recursive "https://github.com/mrv777/ckstats.git" "/zero/ckstats"

# ── set ckpool directory ───────────────────────────────
WORKDIR "/zero/ckpool"

# ── remove --no-recursive flag from autogen.sh ─────────
RUN sed -i 's/--no-recursive//g' autogen.sh

# ── build ckpool ───────────────────────────────────────
RUN ./autogen.sh \
    && ./configure --prefix="/zero/ckpool" \
    && make -j"$(nproc)"

# ── set ckstats directory ──────────────────────────────
WORKDIR "/zero/ckstats"

# ── build ckstats ──────────────────────────────────────
RUN pnpm install --frozen-lockfile
RUN pnpm exec tsc --project tsconfig.scripts.json
RUN pnpm prune --prod



# ═══════════════════════════════════════════════════════
# Runtime image — minimal
# ═══════════════════════════════════════════════════════
FROM ubuntu:24.04 AS runtime

# ── set directory ──────────────────────────────────────
WORKDIR "/zero"

# ── set label ──────────────────────────────────────────
LABEL maintainer="S7nAcks/zero" description="ckpool (official ckolivas) + ckstats ingester (no web UI), amd64, Ubuntu 24.04"

# ── runtime dependencies only ─────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        cron \
        nano \
        postgresql-client \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm \
    && rm -rf /var/lib/apt/lists/*

# ── create dedicated user ─────────────────────────────
RUN groupadd -r ckpool && useradd -r -g ckpool --no-create-home ckpool

# ── copy ckpool binaries from builder ─────────────────
RUN mkdir -p \
        "/zero/ckpool" \
        "/zero/ckpool/log" \
        "/zero/ckpool/sockets"

COPY --from=builder "/zero/ckpool/src/ckpool"   "/zero/ckpool/ckpool"
COPY --from=builder "/zero/ckpool/src/ckdb"     "/zero/ckpool/ckdb"
COPY --from=builder "/zero/ckpool/src/ckpmsg"   "/zero/ckpool/ckpmsg"
COPY --from=builder "/zero/ckpool/src/notifier" "/zero/ckpool/notifier"

RUN chown -R ckpool:ckpool "/zero/ckpool"

# ── copy ckstats binaries from builder ────────────────
RUN mkdir -p \
        "/zero/ckstats" \
        "/zero/ckstats/logs"

COPY --from=builder "/zero/ckstats/scripts"               "/zero/ckstats/scripts"
COPY --from=builder "/zero/ckstats/node_modules"          "/zero/ckstats/node_modules"
COPY --from=builder "/zero/ckstats/package.json"          "/zero/ckstats/package.json"
COPY --from=builder "/zero/ckstats/ormconfig.ts"          "/zero/ckstats/ormconfig.ts"
COPY --from=builder "/zero/ckstats/migrations"            "/zero/ckstats/migrations"
COPY --from=builder "/zero/ckstats/tsconfig.scripts.json" "/zero/ckstats/tsconfig.scripts.json"

RUN chown -R ckpool:ckpool "/zero/ckstats"

# ── crontab for ckstats ingestion ─────────────────────
# seed + update-users every minute, cleanup every 2 hours
RUN    echo '*/1 * * * * ckpool cd /zero/ckstats && /usr/bin/node scripts/seed.js        >> /zero/ckstats/logs/seed.log    2>&1' >  /etc/cron.d/ckstats \
    && echo '*/1 * * * * ckpool cd /zero/ckstats && /usr/bin/node scripts/updateUsers.js >> /zero/ckstats/logs/users.log   2>&1' >> /etc/cron.d/ckstats \
    && echo '5 */2 * * * ckpool cd /zero/ckstats && /usr/bin/node scripts/cleanup.js     >> /zero/ckstats/logs/cleanup.log 2>&1' >> /etc/cron.d/ckstats \
    && chmod 0644 /etc/cron.d/ckstats

# ── set path ──────────────────────────────────────────
ENV PATH="/zero:/zero/ckpool:/zero/ckstats:${PATH}"

# ── set port ──────────────────────────────────────────
EXPOSE 3333

# ── entrypoint ────────────────────────────────────────
COPY entrypoint.sh "/zero/entrypoint.sh"
RUN chmod +x "/zero/entrypoint.sh"

ENTRYPOINT ["/zero/ckpool/entrypoint.sh"]
