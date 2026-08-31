#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

required_functions=(
  initialize_config
  preflight
  run_phase_hooks
  install_bds
  install_world_zip_from_s3
  activate_managed_content
  install_behaviorpacks
  install_resourcepacks
  apply_server_properties_from_env
  rcon_exec
  run_rcon_startup_commands
  graceful_shutdown
  install
  runtime
  run_runtime_phase
  handle_command_mode
  healthcheck
)

for function_name in "${required_functions[@]}"; do
  declare -F "${function_name}" >/dev/null \
    || { printf 'missing function: %s\n' "${function_name}" >&2; exit 1; }
done

printf 'module loading smoke: ok\n'
