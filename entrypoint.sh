#!/usr/bin/env bash
set -Eeuo pipefail

ENTRYPOINT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -d "${ENTRYPOINT_DIR}/scripts/lib" ]]; then
  LIB_DIR="${ENTRYPOINT_DIR}/scripts/lib"
else
  LIB_DIR="/usr/local/lib/minecraft-bedrock-server"
fi

[[ -d "${LIB_DIR}" ]] || {
  printf 'ERROR: runtime library directory not found: %s\n' "${LIB_DIR}" >&2
  exit 1
}

# shellcheck source=scripts/lib/logging.sh
source "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=scripts/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=scripts/lib/filesystem.sh
source "${LIB_DIR}/filesystem.sh"
# shellcheck source=scripts/lib/content_state.sh
source "${LIB_DIR}/content_state.sh"
# shellcheck source=scripts/lib/player_access.sh
source "${LIB_DIR}/player_access.sh"
# shellcheck source=scripts/lib/preflight.sh
source "${LIB_DIR}/preflight.sh"
# shellcheck source=scripts/lib/lifecycle.sh
source "${LIB_DIR}/lifecycle.sh"
# shellcheck source=scripts/lib/s3_client.sh
source "${LIB_DIR}/s3_client.sh"
# shellcheck source=scripts/lib/content_assets.sh
source "${LIB_DIR}/content_assets.sh"
# shellcheck source=scripts/lib/world_pack_binding.sh
source "${LIB_DIR}/world_pack_binding.sh"
# shellcheck source=scripts/lib/server_install.sh
source "${LIB_DIR}/server_install.sh"
# shellcheck source=scripts/lib/server_properties.sh
source "${LIB_DIR}/server_properties.sh"
# shellcheck source=scripts/lib/world_install.sh
source "${LIB_DIR}/world_install.sh"
# shellcheck source=scripts/lib/rcon.sh
source "${LIB_DIR}/rcon.sh"
# shellcheck source=scripts/lib/shutdown.sh
source "${LIB_DIR}/shutdown.sh"
# shellcheck source=scripts/lib/runtime.sh
source "${LIB_DIR}/runtime.sh"
# shellcheck source=scripts/lib/install_phase.sh
source "${LIB_DIR}/install_phase.sh"
# shellcheck source=scripts/lib/runtime_phase.sh
source "${LIB_DIR}/runtime_phase.sh"
# shellcheck source=scripts/lib/command_mode.sh
source "${LIB_DIR}/command_mode.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

initialize_config
trap 'graceful_shutdown' TERM INT QUIT

handle_command_mode "$@"
if (( COMMAND_MODE_SHIFT > 0 )); then
  shift "${COMMAND_MODE_SHIFT}" || true
fi

main() {
  log INFO "Minecraft Bedrock Runtime Booting..."
  preflight
  fix_ownership_if_needed
  drop_privileges_if_needed
  run_runtime_phase
}

main "$@"
