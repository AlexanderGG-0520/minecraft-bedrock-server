# ============================================================
# MC Builder for mcrcon
# ============================================================
ARG MC_RELEASE=RELEASE.2025-08-13T08-35-41Z
ARG GO_VERSION=1.24.11

FROM golang:${GO_VERSION}-bookworm AS mc-builder
ARG MC_RELEASE

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch ${MC_RELEASE} https://github.com/minio/mc.git .

# x/crypto CVE
RUN go get golang.org/x/crypto@v0.43.0 && go mod tidy

# Build static mc binary
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/mc .

# ============================================================
FROM debian:stable-slim AS mcrcon-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      build-essential \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    git clone --depth 1 https://github.com/Tiiffi/mcrcon /tmp/mcrcon; \
    make -C /tmp/mcrcon; \
    install -m 0755 /tmp/mcrcon/mcrcon /usr/local/bin/mcrcon


FROM debian:stable-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

# NOTE:
# - Do NOT EXPOSE ports here (container/internal port is env-driven; user maps explicitly).
RUN set -eux; \
    apt-get update; \
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
      libstdc++6 \
      libgcc-s1 \
      libcurl4 \
      libssl3 \
    ; \
    rm -rf /var/lib/apt/lists/*

# MinIO client (mc) for S3 sync
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) MC_ARCH="amd64" ;; \
      arm64) MC_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH} (use amd64/arm64)"; exit 1 ;; \
    esac; \
    curl -fsSL "https://dl.min.io/client/mc/release/linux-${MC_ARCH}/mc" -o /usr/local/bin/mc; \
    chmod +x /usr/local/bin/mc; \
    /usr/local/bin/mc --version

# RCON client
COPY --from=mcrcon-builder /usr/local/bin/mcrcon /usr/local/bin/mcrcon

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /data
VOLUME ["/data"]

ARG UID=10001
ARG GID=10001

ENTRYPOINT ["/usr/bin/tini","-g","--","/usr/local/bin/entrypoint.sh"]
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
