# shellcheck shell=bash

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch "${DATA_DIR}/.write_test" 2>/dev/null || die "${DATA_DIR} is not writable"
  rm -f -- "${DATA_DIR}/.write_test"

  [[ -n "${EULA:-}" ]] || die "EULA is not set (set EULA=true)"
  [[ "${EULA}" == "true" ]] || die "EULA must be true"

  [[ "${RUN_UID}" =~ ^[0-9]+$ ]] || die "RUN_UID must be numeric"
  [[ "${RUN_GID}" =~ ^[0-9]+$ ]] || die "RUN_GID must be numeric"

  if is_true "${ENABLE_RCON}"; then
    [[ -n "${RCON_PASSWORD}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
    validate_port "RCON_PORT" "${RCON_PORT}"
  fi

  validate_port "SERVER_PORT" "${SERVER_PORT:-}"
  validate_port "SERVER_PORTV6" "${SERVER_PORTV6:-}"

  rm -f -- "${DATA_DIR}/.ready" || true
  log INFO "Preflight OK"
}
