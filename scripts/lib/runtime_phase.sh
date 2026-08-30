# shellcheck shell=bash

run_runtime_phase() {
  install

  if is_true "${INSTALL_ONLY:-false}"; then
    log INFO "INSTALL_ONLY=true, skipping runtime launch"
    return 0
  fi

  runtime
}
