#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

calls=()
rcon_exec() {
  calls+=("$*")
}

ENABLE_RCON=true
RCON_CMDS_STARTUP=$'say first\n\nlist\nsay last'
run_rcon_startup_commands

[[ "${#calls[@]}" -eq 3 ]] || {
  printf 'unexpected startup command count: %s\n' "${#calls[@]}" >&2
  exit 1
}
[[ "${calls[0]}" == "say first" && "${calls[1]}" == "list" && "${calls[2]}" == "say last" ]] || {
  printf 'startup commands executed in unexpected order\n' >&2
  exit 1
}

ENABLE_RCON=false
if validate_rcon_startup_commands_config >/dev/null 2>&1; then
  printf 'startup commands were accepted with RCON disabled\n' >&2
  exit 1
fi

printf 'rcon startup smoke: ok\n'
