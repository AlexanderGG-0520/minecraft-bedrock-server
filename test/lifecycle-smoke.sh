#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

calls=()
record() { calls+=("$1"); }
run_phase_hooks() { record "hook:$1"; }
install_dirs() { record install_dirs; }
install_eula() { record install_eula; }
install_bds() { record install_bds; }
ldd_check() { record ldd_check; }
install_world_zip_from_s3() { record install_world; }
install_behaviorpacks() { record install_behaviorpacks; }
activate_behaviorpacks() { record activate_behaviorpacks; }
install_resourcepacks() { record install_resourcepacks; }
activate_resourcepacks() { record activate_resourcepacks; }
apply_server_properties_from_env() { record apply_server_properties; }

install

expected_install="hook:pre-install install_dirs install_eula install_bds ldd_check install_world install_behaviorpacks activate_behaviorpacks install_resourcepacks activate_resourcepacks apply_server_properties hook:post-install"
actual_install="${calls[*]}"
[[ "${actual_install}" == "${expected_install}" ]] || {
  printf 'unexpected install order\nexpected: %s\nactual:   %s\n' "${expected_install}" "${actual_install}" >&2
  exit 1
}

calls=()
install() { record install; }
runtime() { record runtime; }
INSTALL_ONLY=false
run_runtime_phase

[[ "${calls[*]}" == "install runtime" ]] || {
  printf 'unexpected runtime phase order: %s\n' "${calls[*]}" >&2
  exit 1
}

calls=()
INSTALL_ONLY=true
run_runtime_phase
[[ "${calls[*]}" == "install" ]] || {
  printf 'install-only unexpectedly launched runtime: %s\n' "${calls[*]}" >&2
  exit 1
}

printf 'lifecycle smoke: ok\n'
