#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

base_config() {
  DATA_DIR="${tmp_dir}/data"
  mkdir -p "${DATA_DIR}"
  EULA=true
  initialize_config
}

base_config
INSTALL_ONLY=true
ENABLE_RCON=true
RCON_PASSWORD=""
preflight

base_config
INSTALL_ONLY=false
ENABLE_RCON=true
RCON_PASSWORD=""
if (preflight >/dev/null 2>&1); then
  printf 'runtime preflight accepted empty RCON password\n' >&2
  exit 1
fi

base_config
INSTALL_ONLY=false
ENABLE_RCON=false
RCON_RETRIES=0
if (preflight >/dev/null 2>&1); then
  printf 'preflight accepted RCON_RETRIES=0\n' >&2
  exit 1
fi

base_config
INSTALL_ONLY=false
ENABLE_RCON=false
RCON_TIMEOUT=0
if (preflight >/dev/null 2>&1); then
  printf 'preflight accepted RCON_TIMEOUT=0\n' >&2
  exit 1
fi

base_config
INSTALL_ONLY=false
ENABLE_RCON=false
BDS_CHANNEL=invalid
if (preflight >/dev/null 2>&1); then
  printf 'preflight accepted invalid BDS_CHANNEL\n' >&2
  exit 1
fi

printf 'preflight safety smoke: ok\n'
