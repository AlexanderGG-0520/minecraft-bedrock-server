# shellcheck shell=bash

cleanup_rcon_lock_on_boot() {
  safe_rm_rf "${RCON_STOP_LOCK}" 2>/dev/null || true
}

acquire_rcon_stop_lock() {
  mkdir "${RCON_STOP_LOCK}" 2>/dev/null
}

rcon_exec() {
  local cmd="$*"
  local attempt=1

  if ! is_true "${ENABLE_RCON}"; then
    log INFO "RCON disabled, skip: ${cmd}"
    return 1
  fi
  [[ -n "${RCON_PASSWORD}" ]] || return 1

  while true; do
    log INFO "[rcon] exec attempt ${attempt}/${RCON_RETRIES}: ${cmd}"
    if timeout "${RCON_TIMEOUT}" \
      mcrcon -H "${RCON_HOST}" -P "${RCON_PORT}" -p "${RCON_PASSWORD}" "${cmd}"; then
      log INFO "[rcon] exec succeeded: ${cmd}"
      return 0
    fi

    if (( attempt >= RCON_RETRIES )); then
      log ERROR "RCON failed after ${attempt} attempts: ${cmd}"
      return 1
    fi

    log WARN "RCON failed (attempt ${attempt}/${RCON_RETRIES}), retrying: ${cmd}"
    attempt=$((attempt + 1))
    sleep "${RCON_RETRY_DELAY}"
  done
}

rcon_startup_commands_configured() {
  local commands="${RCON_CMDS_STARTUP:-}"
  [[ -n "${commands//[[:space:]]/}" ]]
}

validate_rcon_startup_commands_config() {
  rcon_startup_commands_configured || return 0
  if ! is_true "${ENABLE_RCON}"; then
    log ERROR "RCON_CMDS_STARTUP requires ENABLE_RCON=true"
    return 1
  fi
  return 0
}

run_rcon_startup_commands() {
  local command
  local line_number=0
  local executed=0

  rcon_startup_commands_configured || return 0
  validate_rcon_startup_commands_config || return 1

  while IFS= read -r command || [[ -n "${command}" ]]; do
    line_number=$((line_number + 1))
    [[ "${command}" =~ ^[[:space:]]*$ ]] && continue

    executed=$((executed + 1))
    log INFO "[rcon] startup command ${executed} (line ${line_number}): ${command}"
    if ! rcon_exec "${command}"; then
      log ERROR "[rcon] startup command ${executed} failed: ${command}"
      return 1
    fi
  done <<< "${RCON_CMDS_STARTUP}"

  log INFO "[rcon] completed ${executed} startup command(s)"
}

rcon_stop_once() {
  if [[ "${RCON_STOP_IN_PROGRESS}" == "1" ]]; then
    return "${RCON_STOP_RESULT}"
  fi

  if ! acquire_rcon_stop_lock; then
    log INFO "rcon_stop already running (lock exists), skipping"
    return "${RCON_STOP_RESULT}"
  fi

  RCON_STOP_IN_PROGRESS=1
  log INFO "[shutdown] rcon: stop"

  if rcon_exec "stop"; then
    RCON_STOP_RESULT=0
  else
    RCON_STOP_RESULT=1
  fi

  return "${RCON_STOP_RESULT}"
}
