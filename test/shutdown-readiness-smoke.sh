#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=entrypoint.sh
source "${repo_root}/entrypoint.sh"

DATA_DIR="$(mktemp -d)"
trap 'rm -rf -- "${DATA_DIR}"' EXIT

SHUTDOWN_WAIT_TIMEOUT=0
SHUTDOWN_TERM_WAIT=0
SERVER_PID=""

touch "${DATA_DIR}/.ready"
rcon_stop_once() { return 0; }

(graceful_shutdown)

[[ ! -e "${DATA_DIR}/.ready" ]] || {
  printf 'shutdown did not clear readiness state\n' >&2
  exit 1
}

printf 'shutdown readiness smoke: ok\n'
