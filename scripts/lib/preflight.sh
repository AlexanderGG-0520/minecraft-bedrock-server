# shellcheck shell=bash

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch "${DATA_DIR}/.write_test" 2>/dev/null || die "${DATA_DIR} is not writable"
  safe_rm_f "${DATA_DIR}/.write_test"

  [[ -n "${EULA:-}" ]] || die "EULA is not set (set EULA=true)"
  [[ "${EULA}" == "true" ]] || die "EULA must be true"

  [[ "${RUN_UID}" =~ ^[0-9]+$ ]] || die "RUN_UID must be numeric"
  [[ "${RUN_GID}" =~ ^[0-9]+$ ]] || die "RUN_GID must be numeric"

  validate_boolean "FIX_OWNERSHIP" "${FIX_OWNERSHIP}"
  validate_boolean "FORCE_REINSTALL" "${FORCE_REINSTALL}"
  validate_boolean "INSTALL_ONLY" "${INSTALL_ONLY}"
  validate_boolean "HOOKS_ENABLED" "${HOOKS_ENABLED}"
  validate_boolean "HOOKS_STRICT" "${HOOKS_STRICT}"
  validate_boolean "ENABLE_RCON" "${ENABLE_RCON}"
  validate_boolean "BEHAVIORPACKS_ENABLED" "${BEHAVIORPACKS_ENABLED}"
  validate_boolean "BEHAVIORPACKS_SYNC_ONCE" "${BEHAVIORPACKS_SYNC_ONCE}"
  validate_boolean "BEHAVIORPACKS_REMOVE_EXTRA" "${BEHAVIORPACKS_REMOVE_EXTRA}"
  validate_boolean "RESOURCEPACKS_ENABLED" "${RESOURCEPACKS_ENABLED}"
  validate_boolean "RESOURCEPACKS_SYNC_ONCE" "${RESOURCEPACKS_SYNC_ONCE}"
  validate_boolean "RESOURCEPACKS_REMOVE_EXTRA" "${RESOURCEPACKS_REMOVE_EXTRA}"
  validate_boolean "WORLD_INSTALL_ONCE" "${WORLD_INSTALL_ONCE}"
  validate_boolean "WORLD_REPLACE" "${WORLD_REPLACE}"

  validate_nonnegative_int "HOOKS_TIMEOUT_SEC" "${HOOKS_TIMEOUT_SEC}"
  validate_nonnegative_int "READY_DELAY" "${READY_DELAY}"
  validate_nonnegative_int "RCON_RETRIES" "${RCON_RETRIES}"
  validate_nonnegative_int "RCON_RETRY_DELAY" "${RCON_RETRY_DELAY}"
  validate_nonnegative_int "RCON_TIMEOUT" "${RCON_TIMEOUT}"
  validate_nonnegative_int "SHUTDOWN_WAIT_TIMEOUT" "${SHUTDOWN_WAIT_TIMEOUT}"
  validate_nonnegative_int "SHUTDOWN_TERM_WAIT" "${SHUTDOWN_TERM_WAIT}"

  if is_true "${HOOKS_ENABLED}"; then
    [[ -n "${HOOKS_DIR}" && "${HOOKS_DIR}" == /* && "${HOOKS_DIR}" != "/" ]] \
      || die "HOOKS_DIR must be an absolute non-root path"
  fi

  if is_true "${ENABLE_RCON}"; then
    [[ -n "${RCON_PASSWORD}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
    validate_port "RCON_PORT" "${RCON_PORT}"
  fi

  validate_rcon_startup_commands_config \
    || die "Invalid RCON startup command configuration"

  validate_port "SERVER_PORT" "${SERVER_PORT:-}"
  validate_port "SERVER_PORTV6" "${SERVER_PORTV6:-}"

  safe_rm_f "${DATA_DIR}/.ready" || true
  log INFO "Preflight OK"
}
