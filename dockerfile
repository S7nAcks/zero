# ═══════════════════════════════════════════════════════
# ckpool + ckdb  —  built from official Bitbucket source
# Target: linux/amd64  |  Base: Ubuntu 24.04 LTS
# ═══════════════════════════════════════════════════════
FROM ubuntu:24.04 AS builder

# ── set directory ──────────────────────────────────────
WORKDIR "/zero"

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
        libjansson-dev \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ── fetch sources ──────────────────────────────────────
RUN git clone --recursive --branch "${BRANCH}" "${REPO_URL}" "/zero/ckpool"

# ── set directory ──────────────────────────────────────
WORKDIR "/zero/ckpool"

# ── remove --no-recursive flag from autogen.sh ─────────
RUN sed -i 's/--no-recursive//g' autogen.sh

# ── build with ckdb support ────────────────────────────
RUN ./autogen.sh \
    && ./configure --prefix="/zero/ckpool" \
    && make -j"$(nproc)"

# ── install to /zero/ckpool prefix ────────────────────
# RUN make install DESTDIR="/staging"

# ═══════════════════════════════════════════════════════
# Runtime image — minimal
# ═══════════════════════════════════════════════════════
FROM ubuntu:24.04 AS runtime

# ── set directory ──────────────────────────────────────
WORKDIR "/zero"

# ── set label ──────────────────────────────────────────
LABEL maintainer="S7nAcks/zero" \
      description="ckpool + ckdb (official ckolivas source, amd64, Ubuntu 24.04)"

# ── runtime dependencies only ─────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        nano \
    && rm -rf /var/lib/apt/lists/*

# ── create dedicated user ─────────────────────────────
RUN groupadd -r ckpool && useradd -r -g ckpool --no-create-home ckpool

# ── copy binaries from builder ────────────────────────
COPY --from=builder "/zero/ckpool/src/ckpool"  "/zero/ckpool/ckpool"
COPY --from=builder "/zero/ckpool/src/ckpmsg"    "/zero/ckpool/ckpmsg"
COPY --from=builder "/zero/ckpool/src/notifier"  "/zero/ckpool/notifier"

# ── directories ───────────────────────────────────────
RUN mkdir -p \
        "/zero/ckpool/log" \
        "/zero/ckpool/sockets/ckpool" \
        "/zero/ckpool/sockets/ckdb" \
    && chown -R ckpool:ckpool "/zero/ckpool"

# PATH so binaries are callable without full path
ENV PATH="/zero:/zero/ckpool:${PATH}"

# ── entrypoint ────────────────────────────────────────
COPY entrypoint.sh "/zero/ckpool/entrypoint.sh"
RUN chmod +x "/zero/ckpool/entrypoint.sh"

USER ckpool

EXPOSE 3333

ENTRYPOINT ["/zero/ckpool/entrypoint.sh"]
