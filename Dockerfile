# syntax=docker/dockerfile:1

# ============================================================
# Build mcrcon
# ============================================================
FROM debian:trixie-20260316-slim AS mcrcon-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      build-essential \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    git clone --depth 1 https://github.com/Tiiffi/mcrcon /tmp/mcrcon; \
    make -C /tmp/mcrcon; \
    install -m 0755 /tmp/mcrcon/mcrcon /usr/local/bin/mcrcon; \
    strip /usr/local/bin/mcrcon || true

# ============================================================
# Runtime base
# ============================================================
FROM debian:trixie-20260316-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG TARGETARCH
ARG UID=1000
ARG GID=1000
ENV UID=${UID} GID=${GID}

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      jq \
      unzip \
      rsync \
      tini \
      gosu \
      procps \
      libc6 \
      libstdc++6 \
      libgcc-s1 \
      libcurl4 \
      libssl3 \
      tzdata \
    ; \
    rm -rf /var/lib/apt/lists/*

# Runtime user/group
RUN set -eux; \
    groupadd --gid "${GID}" minecraft; \
    useradd \
      --uid "${UID}" \
      --gid "${GID}" \
      --home-dir /data \
      --create-home \
      --shell /usr/sbin/nologin \
      minecraft

# MinIO client (mc) for S3 sync
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) MC_ARCH="amd64" ;; \
      arm64) MC_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH:-unknown} (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    MC_VERSION="RELEASE.2024-02-23T21-49-44Z"; \
    case "${MC_ARCH}" in \
      amd64) MC_SHA256="1111111111111111111111111111111111111111111111111111111111111111" ;; \
      arm64) MC_SHA256="2222222222222222222222222222222222222222222222222222222222222222" ;; \
      *) echo "Unsupported MC_ARCH=${MC_ARCH} (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    MC_URL="https://dl.min.io/client/mc/release/linux-${MC_ARCH}/archive/mc.${MC_VERSION}"; \
    curl -fsSL --retry 3 "${MC_URL}" -o /usr/local/bin/mc; \
    echo "${MC_SHA256}  /usr/local/bin/mc" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/mc; \
    /usr/local/bin/mc --version

# RCON client
COPY --from=mcrcon-builder /usr/local/bin/mcrcon /usr/local/bin/mcrcon

# Entrypoint
COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

WORKDIR /data
VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/tini","-g","--","/usr/local/bin/docker-entrypoint.sh"]
CMD []

# ============================================================
# Targets for GitHub Actions buildx --target
# ============================================================
FROM base AS bedrock-latest
ENV BDS_CHANNEL=latest

FROM base AS bedrock-stable
ARG BDS_STABLE_VERSION
ENV BDS_CHANNEL=stable
ENV BDS_STABLE_VERSION=${BDS_STABLE_VERSION}