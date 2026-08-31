# shellcheck shell=bash

refuse_unsafe_filesystem_path() {
  local path="${1:-}"
  local action="${2:-operate on}"
  local resolved_path

  if [[ -z "${path}" || "${path}" == "/" ]]; then
    log ERROR "Refusing to ${action} unsafe path"
    return 1
  fi

  if command -v realpath >/dev/null 2>&1; then
    resolved_path="$(realpath -m -- "${path}")" || {
      log ERROR "Refusing to ${action} unsafe path"
      return 1
    }
    if [[ "${resolved_path}" == "/" ]]; then
      log ERROR "Refusing to ${action} unsafe path"
      return 1
    fi
  fi

  return 0
}

safe_rm_f() {
  local path="${1:-}"
  refuse_unsafe_filesystem_path "${path}" "remove" || return 1
  rm -f -- "${path}"
}

safe_rm_rf() {
  local path="${1:-}"
  refuse_unsafe_filesystem_path "${path}" "remove" || return 1
  rm -rf -- "${path}"
}

safe_mv() {
  local src="${1:-}"
  local dst="${2:-}"
  refuse_unsafe_filesystem_path "${src}" "move from" || return 1
  refuse_unsafe_filesystem_path "${dst}" "move to" || return 1
  mv -- "${src}" "${dst}"
}

safe_mv_f() {
  local src="${1:-}"
  local dst="${2:-}"
  refuse_unsafe_filesystem_path "${src}" "move from" || return 1
  refuse_unsafe_filesystem_path "${dst}" "move to" || return 1
  mv -f -- "${src}" "${dst}"
}

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
  local remove_extra="${4:-true}"
  local parent base staging backup

  [[ -d "${src}" ]] || {
    log INFO "No ${name} directory found (${src}), skipping"
    return 0
  }

  if ! find "${src}" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    log INFO "${name} input directory is empty (${src}), skipping activation"
    return 0
  fi

  parent="$(dirname "${dst}")"
  base="$(basename "${dst}")"
  mkdir -p "${parent}"

  staging="$(mktemp -d "${parent}/.${base}.staging.XXXXXX")" \
    || die "Failed to create ${name} staging directory"
  backup="$(mktemp -d "${parent}/.${base}.old.XXXXXX")" \
    || { safe_rm_rf "${staging}"; die "Failed to create ${name} backup directory"; }
  safe_rm_rf "${backup}"

  if ! is_true "${remove_extra}" && [[ -d "${dst}" ]]; then
    log INFO "Preserving existing ${name} entries not present in managed input"
    if ! rsync -a "${dst}/" "${staging}/"; then
      safe_rm_rf "${staging}" || true
      die "Failed to seed ${name} staging directory from current state"
    fi
  fi

  log INFO "Activating ${name} (atomic) (${src} -> ${dst})"
  if ! rsync -a "${src}/" "${staging}/"; then
    safe_rm_rf "${staging}" || true
    die "Failed to stage ${name}"
  fi

  if [[ -d "${dst}" ]]; then
    if ! safe_mv "${dst}" "${backup}"; then
      safe_rm_rf "${staging}" || true
      die "Failed to preserve current ${name} before activation"
    fi
  fi

  if ! safe_mv "${staging}" "${dst}"; then
    [[ ! -d "${backup}" ]] || safe_mv "${backup}" "${dst}" || true
    safe_rm_rf "${staging}" || true
    die "Failed to activate ${name}"
  fi

  [[ ! -d "${backup}" ]] || safe_rm_rf "${backup}"
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

drop_privileges_if_needed() {
  local current_uid current_gid mode
  current_uid="$(id -u)"
  current_gid="$(id -g)"
  mode="run"
  is_true "${INSTALL_ONLY:-false}" && mode="install-only"

  if [[ "${current_uid}" == "${RUN_UID}" && "${current_gid}" == "${RUN_GID}" ]]; then
    return 0
  fi

  if [[ "${current_uid}" != "0" ]]; then
    die "Container is already non-root as ${current_uid}:${current_gid}, but RUN_UID:RUN_GID requests ${RUN_UID}:${RUN_GID}"
  fi

  if [[ "${RUN_UID}" == "0" && "${RUN_GID}" == "0" ]]; then
    return 0
  fi

  log INFO "Dropping privileges before lifecycle: ${RUN_UID}:${RUN_GID} (mode=${mode})"
  export RUN_UID RUN_GID INSTALL_ONLY
  exec gosu "${RUN_UID}:${RUN_GID}" /usr/local/bin/docker-entrypoint.sh "${mode}"
}
