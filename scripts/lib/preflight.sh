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

  case "${BDS_CHANNEL}" in
    latest|stable) ;;
    *) die "BDS_CHANNEL must be latest or stable (got: ${BDS_CHANNEL})" ;;
  esac
  if [[ "${BDS_CHANNEL}" == "stable" && -z "${BDS_STABLE_VERSION}" && -z "${BDS_DOWNLOAD_URL}" ]]; then
    die "BDS_CHANNEL=stable requires BDS_STABLE_VERSION"
  fi

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
  validate_boolean "BDS_ALLOWLIST_REMOVE_EXTRA" "${BDS_ALLOWLIST_REMOVE_EXTRA}"
  validate_boolean "BDS_PERMISSIONS_REMOVE_EXTRA" "${BDS_PERMISSIONS_REMOVE_EXTRA}"
  validate_boolean "WORLD_PACKS_BINDING_ENABLED" "${WORLD_PACKS_BINDING_ENABLED}"
  validate_boolean "WORLD_PACKS_REMOVE_EXTRA" "${WORLD_PACKS_REMOVE_EXTRA}"

  validate_nonnegative_int "HOOKS_TIMEOUT_SEC" "${HOOKS_TIMEOUT_SEC}"
  validate_nonnegative_int "READY_DELAY" "${READY_DELAY}"
  validate_positive_int "RCON_RETRIES" "${RCON_RETRIES}"
  validate_nonnegative_int "RCON_RETRY_DELAY" "${RCON_RETRY_DELAY}"
  validate_positive_int "RCON_TIMEOUT" "${RCON_TIMEOUT}"
  validate_positive_int "SHUTDOWN_WAIT_TIMEOUT" "${SHUTDOWN_WAIT_TIMEOUT}"
  validate_nonnegative_int "SHUTDOWN_TERM_WAIT" "${SHUTDOWN_TERM_WAIT}"

  if is_true "${HOOKS_ENABLED}"; then
    [[ -n "${HOOKS_DIR}" && "${HOOKS_DIR}" == /* && "${HOOKS_DIR}" != "/" ]] \
      || die "HOOKS_DIR must be an absolute non-root path"
  fi

  if [[ -n "${BDS_ALLOWLIST_JSON}" && -n "${BDS_ALLOWLIST_FILE}" ]]; then
    die "Set only one of BDS_ALLOWLIST_JSON or BDS_ALLOWLIST_FILE"
  fi
  if [[ -n "${BDS_PERMISSIONS_JSON}" && -n "${BDS_PERMISSIONS_FILE}" ]]; then
    die "Set only one of BDS_PERMISSIONS_JSON or BDS_PERMISSIONS_FILE"
  fi

  local source_var source_value
  for source_var in BDS_ALLOWLIST_FILE BDS_PERMISSIONS_FILE; do
    source_value="${!source_var}"
    [[ -n "${source_value}" ]] || continue
    [[ "${source_value}" == /* && "${source_value}" != "/" ]] \
      || die "${source_var} must be an absolute non-root path"
    [[ -f "${source_value}" ]] || die "${source_var} does not exist: ${source_value}"
  done

  if [[ -n "${WORLD_PACKS_LEVEL_NAME}" ]]; then
    [[ "${WORLD_PACKS_LEVEL_NAME}" != "." \
      && "${WORLD_PACKS_LEVEL_NAME}" != ".." \
      && "${WORLD_PACKS_LEVEL_NAME}" != */* \
      && "${WORLD_PACKS_LEVEL_NAME}" != *\\* \
      && "${WORLD_PACKS_LEVEL_NAME}" != *$'\n'* \
      && "${WORLD_PACKS_LEVEL_NAME}" != *$'\r'* ]] \
      || die "WORLD_PACKS_LEVEL_NAME must be a single safe world directory name"
  fi

  if ! is_true "${INSTALL_ONLY}"; then
    if is_true "${ENABLE_RCON}"; then
      [[ -n "${RCON_PASSWORD}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
      validate_port "RCON_PORT" "${RCON_PORT}"
    fi

    validate_rcon_startup_commands_config \
      || die "Invalid RCON startup command configuration"
  fi

  validate_port "SERVER_PORT" "${SERVER_PORT:-}"
  validate_port "SERVER_PORTV6" "${SERVER_PORTV6:-}"

  safe_rm_f "${DATA_DIR}/.ready" || true
  log INFO "Preflight OK"
}
