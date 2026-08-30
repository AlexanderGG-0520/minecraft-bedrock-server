# shellcheck shell=bash

run_server() {
  cleanup_rcon_lock_on_boot
  (
    cd "${DATA_DIR}"
    export LD_LIBRARY_PATH="${DATA_DIR}:${LD_LIBRARY_PATH:-}"
    ./bedrock_server
  ) &
  SERVER_PID=$!
  wait "${SERVER_PID}"
}

runtime() {
  log INFO "Starting runtime"
  touch "${DATA_DIR}/.ready" || true
  sleep "${READY_DELAY}" || true

  if [[ "$(id -u)" -eq 0 && ( "${RUN_UID}" != "0" || "${RUN_GID}" != "0" ) ]]; then
    log INFO "Dropping privileges to ${RUN_UID}:${RUN_GID}"
    exec gosu "${RUN_UID}:${RUN_GID}" /usr/local/bin/docker-entrypoint.sh run
  fi

  run_server
}

healthcheck() {
  [[ -f "${DATA_DIR}/.ready" ]] || die "ready file is missing"
  pgrep -f '/bedrock_server$' >/dev/null || die "bedrock_server process is not running"
}
