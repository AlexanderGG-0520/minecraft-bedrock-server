# shellcheck shell=bash

wait_for_server_exit() {
  local wait_timeout="$1"
  local elapsed=0

  while [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; do
    if (( elapsed >= wait_timeout )); then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 0
}

graceful_shutdown() {
  log INFO "[shutdown] begin"
  safe_rm_f "${DATA_DIR}/.ready" 2>/dev/null || true

  if rcon_stop_once; then
    log INFO "[shutdown] rcon stop succeeded"
  else
    log WARN "[shutdown] rcon stop failed/unavailable, sending TERM"
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
      kill -TERM "${SERVER_PID}" 2>/dev/null || true
    fi
  fi

  log INFO "[shutdown] waiting (timeout: ${SHUTDOWN_WAIT_TIMEOUT}s)"
  if wait_for_server_exit "${SHUTDOWN_WAIT_TIMEOUT}"; then
    exit 0
  fi

  log WARN "[shutdown] timeout exceeded, sending TERM"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
  fi

  if wait_for_server_exit "${SHUTDOWN_TERM_WAIT}"; then
    exit 0
  fi

  log WARN "[shutdown] forcing kill"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -KILL "${SERVER_PID}" 2>/dev/null || true
  fi
  exit 0
}
