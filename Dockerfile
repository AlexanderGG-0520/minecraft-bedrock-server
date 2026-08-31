# syntax=docker/dockerfile:1

ARG GO_VERSION=1.25.9

FROM debian:trixie-20260824-slim AS mcrcon-builder

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


FROM golang:${GO_VERSION}-trixie AS mc-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG MC_VERSION=RELEASE.2025-08-13T08-35-41Z
ARG GRPC_VERSION=1.79.3
ARG X_CRYPTO_VERSION=0.43.0
ARG PROMETHEUS_VERSION=0.311.2-0.20260410083055-07c6232d159b

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    go version; \
    go env GOVERSION; \
    git clone --depth 1 --branch "${MC_VERSION}" https://github.com/minio/mc /tmp/mc; \
    cd /tmp/mc; \
    go mod edit \
      -require="google.golang.org/grpc@v${GRPC_VERSION}" \
      -require="golang.org/x/crypto@v${X_CRYPTO_VERSION}" \
      -require="github.com/prometheus/prometheus@v${PROMETHEUS_VERSION}"; \
    go mod tidy; \
    go list -m google.golang.org/grpc golang.org/x/crypto github.com/prometheus/prometheus; \
    CGO_ENABLED=0 go build -trimpath -ldflags "$(go run buildscripts/gen-ldflags.go) -s -w" -o /usr/local/bin/mc .; \
    go version -m /usr/local/bin/mc; \
    /usr/local/bin/mc --version; \
    /usr/local/bin/mc --help >/dev/null


FROM golang:${GO_VERSION}-trixie AS gosu-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG GOSU_VERSION=1.19

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    go version; \
    go env GOVERSION; \
    git clone --depth 1 --branch "${GOSU_VERSION}" https://github.com/tianon/gosu /tmp/gosu; \
    cd /tmp/gosu; \
    go mod tidy; \
    go list -m golang.org/x/sys github.com/moby/sys/user; \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /usr/local/bin/gosu .; \
    go version -m /usr/local/bin/gosu; \
    /usr/local/bin/gosu --version


FROM debian:trixie-20260824-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

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
      procps \
      libc6 \
      libstdc++6 \
      libgcc-s1 \
      libcurl4 \
      libssl3 \
      tzdata \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd --gid 1000 minecraft; \
    useradd \
      --uid 1000 \
      --gid 1000 \
      --home-dir /data \
      --create-home \
      --shell /usr/sbin/nologin \
      minecraft; \
    mkdir -p /behavior_packs /resource_packs; \
    chown minecraft:minecraft /behavior_packs /resource_packs

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=gosu-builder /usr/local/bin/gosu /usr/local/bin/gosu
COPY --from=mcrcon-builder /usr/local/bin/mcrcon /usr/local/bin/mcrcon
RUN set -eux; \
    /usr/local/bin/mc --help >/dev/null; \
    /usr/local/bin/gosu --version; \
    test "$(/usr/local/bin/gosu minecraft id -u)" = "1000"; \
    ! command -v go

COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/lib/ /usr/local/lib/minecraft-bedrock-server/
RUN set -eux; \
    chmod 0755 /usr/local/bin/docker-entrypoint.sh; \
    find /usr/local/lib/minecraft-bedrock-server -type f -name '*.sh' -exec chmod 0644 {} +

WORKDIR /data
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
  CMD ["/usr/local/bin/docker-entrypoint.sh","healthcheck"]

ENTRYPOINT ["/usr/bin/tini","-g","--","/usr/local/bin/docker-entrypoint.sh"]
CMD []
USER minecraft

FROM base AS bedrock-latest
ENV BDS_CHANNEL=latest

FROM base AS bedrock-stable
ARG BDS_STABLE_VERSION
ENV BDS_CHANNEL=stable
ENV BDS_STABLE_VERSION=${BDS_STABLE_VERSION}
