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
        ca-certificates \
        git \
        libtool \
        libzmq3-dev \
        pkg-config \
        yasm \
    && rm -rf /var/lib/apt/lists/*

# ── fetch sources ──────────────────────────────────────
WORKDIR "/zero/ckpool"
RUN git clone --recursive --branch "${BRANCH}" "${REPO_URL}" /zero/ckpool

# ── build with ckdb support ────────────────────────────
RUN cd src/jansson-2.14 \
    && autoreconf -fi \
    && ./configure
RUN ./autogen.sh \
    && ./configure \
    && make -j"$(nproc)"

# ── install to /zero/ckpool prefix ────────────────────
RUN make install prefix="/zero/ckpool" DESTDIR="/staging"

# ═══════════════════════════════════════════════════════
# Runtime image — minimal
# ═══════════════════════════════════════════════════════
FROM ubuntu:24.04 AS runtime

LABEL maintainer="S7nAcks/zero" \
      description="ckpool + ckdb (official ckolivas source, amd64, Ubuntu 24.04)"

# ── runtime dependencies only ─────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        nano \
    && rm -rf /var/lib/apt/lists/*

# ── create dedicated user ─────────────────────────────
RUN groupadd --gid 1000 ckpool \
    && useradd --uid 1000 --gid 1000 --no-create-home ckpool

# ── copy binaries from builder ────────────────────────
COPY --from=builder "/staging/zero/ckpool/bin/ckpool"  "/zero/ckpool/bin/ckpool"
COPY --from=builder "/staging/zero/ckpool/bin/ckdb"    "/zero/ckpool/bin/ckdb"
COPY --from=builder "/staging/zero/ckpool/bin/ckpmsg"  "/zero/ckpool/bin/ckpmsg"

# ── directories ───────────────────────────────────────
RUN mkdir -p \
        "/zero/ckpool/conf" \
        "/zero/ckpool/log" \
        "/zero/ckpool/run/ckpool" \
        "/zero/ckpool/run/ckdb" \
    && chown -R ckpool:ckpool "/zero/ckpool"

# PATH so binaries are callable without full path
ENV PATH="/zero":"/zero/ckpool":"/zero/ckpool/bin:${PATH}"

# ── entrypoint ────────────────────────────────────────
COPY entrypoint.sh "/zero/ckpool/bin/entrypoint.sh"
RUN chmod +x "/zero/ckpool/bin/entrypoint.sh"

USER ckpool

ENTRYPOINT ["/zero/ckpool/bin/entrypoint.sh"]
