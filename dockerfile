# -------------------------------------------------------
# ckpool + ckdb  —  built from official Bitbucket source
# Target: linux/amd64  |  Base: Ubuntu 24.04 LTS
# -------------------------------------------------------
FROM ubuntu:24.04 AS builder

# ── build-time args ────────────────────────────────────
ARG REPO_URL="https://bitbucket.org/ckolivas/ckpool"
ARG BRANCH="master"

# ── build dependencies ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        git \
        libgsl-dev \
        libpq-dev \
        libtool \
        pkg-config \
        yasm \
    && rm -rf /var/lib/apt/lists/*

# ── fetch sources ──────────────────────────────────────
WORKDIR "/zero/.pools/ckpool"
RUN git clone --depth=1 --branch "${BRANCH}" "${REPO_URL}" .

# ── build with ckdb support ────────────────────────────
RUN ./autogen.sh \
    && ./configure \
    && make -j"$(nproc)"

# ── install to /zero/ckpool prefix ────────────────────
RUN make install prefix="/zero/.pools/ckpool" DESTDIR="/staging"



# ═══════════════════════════════════════════════════════
# Runtime image — minimal
# ═══════════════════════════════════════════════════════
FROM ubuntu:24.04 AS runtime

LABEL maintainer="S7nAcks/zero" \
      description="ckpool + ckdb (official ckolivas source, amd64, Ubuntu 24.04)"

# ── runtime dependencies only ─────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgsl28 \
        libpq5 \
        libssl3 \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# ── create dedicated user ─────────────────────────────
RUN groupadd --gid 1000 ckpool \
    && useradd --uid 1000 --gid 1000 --no-create-home ckpool

# ── copy binaries from builder ────────────────────────
COPY --from=builder "/staging/zero/.pools/ckpool/bin/ckpool"  "/zero/.pools/ckpool/bin/ckpool"
COPY --from=builder "/staging/zero/.pools/ckpool/bin/ckdb"    "/zero/.pools/ckpool/bin/ckdb"
COPY --from=builder "/staging/zero/.pools/ckpool/bin/ckpmsg"  "/zero/.pools/ckpool/bin/ckpmsg"

# ── directories ───────────────────────────────────────
RUN mkdir -p \
        "/zero/.pools/ckpool/conf" \
        "/zero/.pools/ckpool/log" \
        "/zero/.pools/ckpool/run/ckpool" \
        "/zero/.pools/ckpool/run/ckdb" \
    && chown -R ckpool:ckpool "/zero/.pools/ckpool"

# PATH so binaries are callable without full path
ENV PATH="/zero/.pools/ckpool":"/zero/.pools/ckpool/bin:${PATH}"

# ── entrypoint ────────────────────────────────────────
COPY entrypoint.sh "/zero/.pools/ckpool/bin/entrypoint.sh"
RUN chmod +x "/zero/.pools/ckpool/bin/entrypoint.sh"

USER ckpool

ENTRYPOINT ["/zero/.pools/ckpool/bin/entrypoint.sh"]
