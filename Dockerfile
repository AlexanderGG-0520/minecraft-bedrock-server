# syntax=docker/dockerfile:1

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


FROM debian:trixie-20260316-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG TARGETARCH

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

RUN set -eux; \
    groupadd --gid 1000 minecraft; \
    useradd \
      --uid 1000 \
      --gid 1000 \
      --home-dir /data \
      --create-home \
      --shell /usr/sbin/nologin \
      minecraft

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) MC_ARCH="amd64" ;; \
      arm64) MC_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH:-unknown} (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    MC_BASE_URL="https://dl.min.io/client/mc/release/linux-${MC_ARCH}"; \
    curl -fsSL --retry 3 "${MC_BASE_URL}/mc" -o /usr/local/bin/mc; \
    curl -fsSL --retry 3 "${MC_BASE_URL}/mc.sha256sum" -o /tmp/mc.sha256sum; \
    expected="$(cut -d' ' -f1 /tmp/mc.sha256sum)"; \
    actual="$(sha256sum /usr/local/bin/mc | cut -d' ' -f1)"; \
    test "${actual}" = "${expected}"; \
    chmod 0755 /usr/local/bin/mc; \
    rm -f /tmp/mc.sha256sum; \
    /usr/local/bin/mc --version

COPY --from=mcrcon-builder /usr/local/bin/mcrcon /usr/local/bin/mcrcon

COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

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
