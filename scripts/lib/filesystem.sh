# shellcheck shell=bash

install_dirs() {
  log INFO "Preparing directory structure"
  mkdir -p \
    "${DATA_DIR}/logs" \
    "${DATA_DIR}/worlds" \
    "${DATA_DIR}/behavior_packs" \
    "${DATA_DIR}/resource_packs"

  mkdir -p "${INPUT_BEHAVIORPACKS_DIR}" "${INPUT_RESOURCEPACKS_DIR}" || true
}

install_eula() {
  log INFO "Handling EULA"
  printf 'eula=true\n' > "${DATA_DIR}/eula.txt"
}

activate_dir_atomic() {
  local src="$1"
  local dst="$2"
  local name="$3"
  local parent base staging backup

  [[ -d "${src}" ]] || {
    log INFO "No ${name} directory found (${src}), skipping"
    return 0
  }

  parent="$(dirname "${dst}")"
  base="$(basename "${dst}")"
  staging="${parent}/.${base}.staging"
  backup="${parent}/.${base}.old"

  log INFO "Activating ${name} (atomic) (${src} -> ${dst})"
  rm -rf -- "${staging}"
  mkdir -p "${staging}"
  rsync -a --delete "${src}/" "${staging}/"

  if [[ -d "${dst}" ]]; then
    rm -rf -- "${backup}"
    mv -- "${dst}" "${backup}"
  fi
  mv -- "${staging}" "${dst}"
  rm -rf -- "${backup}"
}

fix_ownership_if_needed() {
  if [[ "$(id -u)" -ne 0 ]]; then
    return 0
  fi
  if ! is_true "${FIX_OWNERSHIP}"; then
    return 0
  fi
  if [[ "${RUN_UID}" == "0" && "${RUN_GID}" == "0" ]]; then
    return 0
  fi

  log INFO "Fixing ownership: ${DATA_DIR} -> ${RUN_UID}:${RUN_GID}"
  chown -R "${RUN_UID}:${RUN_GID}" "${DATA_DIR}" \
    || die "chown failed (set FIX_OWNERSHIP=false to skip)"
}
