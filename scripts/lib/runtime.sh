# shellcheck shell=bash

run_server() {
  local elapsed=0
  local status=0

  cleanup_rcon_lock_on_boot
  safe_rm_f "${DATA_DIR}/.ready" 2>/dev/null || true

  (
    cd "${DATA_DIR}"
    export LD_LIBRARY_PATH="${DATA_DIR}:${LD_LIBRARY_PATH:-}"
    exec ./bedrock_server
  ) &
  SERVER_PID=$!

  while (( elapsed < READY_DELAY )); do
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
      wait "${SERVER_PID}" || status=$?
      safe_rm_f "${DATA_DIR}/.ready" 2>/dev/null || true
      return "${status}"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    wait "${SERVER_PID}" || status=$?
    return "${status}"
  fi

  if ! run_rcon_startup_commands; then
    log ERROR "RCON startup commands failed; stopping server before readiness"
    safe_rm_f "${DATA_DIR}/.ready" 2>/dev/null || true

    if rcon_stop_once; then
      log INFO "RCON startup command failure shutdown completed"
    else
      log WARN "RCON startup command failure shutdown was unavailable; sending TERM"
      kill -TERM "${SERVER_PID}" 2>/dev/null || true
    fi

    wait "${SERVER_PID}" >/dev/null 2>&1 || true
    return 1
  fi

  if kill -0 "${SERVER_PID}" 2>/dev/null; then
    touch "${DATA_DIR}/.ready" \
      || die "Failed to create readiness file: ${DATA_DIR}/.ready"
    log INFO "Readiness file created"
  fi

  wait "${SERVER_PID}" || status=$?
  safe_rm_f "${DATA_DIR}/.ready" 2>/dev/null || true
  return "${status}"
}

runtime() {
  log INFO "Starting runtime"
  run_phase_hooks "pre-runtime"
  run_server
}

healthcheck() {
  [[ -f "${DATA_DIR}/.ready" ]] || die "ready file is missing"
  pgrep -f '/bedrock_server$' >/dev/null || die "bedrock_server process is not running"
}
