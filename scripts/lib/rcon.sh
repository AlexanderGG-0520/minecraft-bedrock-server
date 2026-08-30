# shellcheck shell=bash

cleanup_rcon_lock_on_boot() {
  rm -rf -- "${RCON_STOP_LOCK}" 2>/dev/null || true
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
    if timeout "${RCON_TIMEOUT}" \
      mcrcon -H "${RCON_HOST}" -P "${RCON_PORT}" -p "${RCON_PASSWORD}" "${cmd}"; then
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
