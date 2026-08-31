# shellcheck shell=bash

worlds_directory_has_content() {
  find "${DATA_DIR}/worlds" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

world_state_marker() {
  printf '%s/.managed/world-source.json\n' "${DATA_DIR}"
}

world_source_fingerprint() {
  printf 's3://%s/%s' "${WORLD_S3_BUCKET}" "${WORLD_S3_KEY}" \
    | sha256sum \
    | awk '{print $1}'
}

validate_world_state_marker() {
  local marker="$1"
  jq -e '
    type == "object"
    and .schema_version == 1
    and .source_type == "s3"
    and (.source_fingerprint | type == "string" and length > 0)
    and (.archive_sha256 | type == "string" and length > 0)
  ' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt world source marker: ${marker}"
}

write_world_state_marker() {
  local source_fingerprint="$1"
  local archive_sha256="$2"
  local marker marker_dir tmp

  marker="$(world_state_marker)"
  marker_dir="$(dirname "${marker}")"
  mkdir -p "${marker_dir}"
  tmp="$(mktemp "${marker_dir}/.world-source.json.tmp.XXXXXX")" \
    || die "Failed to create world source marker temporary file"

  if ! jq -n \
    --arg source_fingerprint "${source_fingerprint}" \
    --arg archive_sha256 "${archive_sha256}" \
    '{schema_version:1,source_type:"s3",source_fingerprint:$source_fingerprint,archive_sha256:$archive_sha256}' \
    > "${tmp}"; then
    safe_rm_f "${tmp}" || true
    die "Failed to build world source marker"
  fi

  safe_mv_f "${tmp}" "${marker}" || die "Failed to activate world source marker"
}

log_world_source_drift_if_managed() {
  local marker current_source installed_source
  marker="$(world_state_marker)"
  [[ -f "${marker}" ]] || return 0

  validate_world_state_marker "${marker}"
  current_source="$(world_source_fingerprint)"
  installed_source="$(jq -r '.source_fingerprint' "${marker}")"

  if [[ "${current_source}" != "${installed_source}" ]]; then
    log WARN "Configured world source differs from the managed installed source; preserving existing worlds because WORLD_INSTALL_ONCE=true"
  fi
}

validate_zip_entries_safe() {
  local archive="$1"
  local entry normalized

  while IFS= read -r entry; do
    normalized="$(printf '%s' "${entry}" | tr '\\' '/')"

    if [[ "${normalized}" == /* || "${normalized}" =~ (^|/)\.\.(/|$) ]]; then
      log ERROR "Unsafe path in world archive: ${entry}"
      return 1
    fi
  done < <(unzip -Z1 "${archive}" 2>/dev/null) || return 1

  return 0
}

cleanup_world_install_temps() {
  local archive="${1:-}"
  local extract_dir="${2:-}"
  [[ -z "${archive}" ]] || safe_rm_f "${archive}" || true
  [[ -z "${extract_dir}" ]] || safe_rm_rf "${extract_dir}" || true
}

install_world_zip_from_s3() {
  [[ -n "${WORLD_S3_BUCKET}" && -n "${WORLD_S3_KEY}" ]] || {
    log INFO "WORLD_S3_BUCKET/KEY not set, skipping world import"
    return 0
  }

  if worlds_directory_has_content; then
    if is_true "${WORLD_INSTALL_ONCE}"; then
      log_world_source_drift_if_managed
      log INFO "Worlds already exist, skipping world import (WORLD_INSTALL_ONCE=true)"
      return 0
    fi

    if ! is_true "${WORLD_REPLACE}"; then
      die "Worlds already exist and WORLD_INSTALL_ONCE=false. Refusing replacement unless WORLD_REPLACE=true"
    fi
  fi

  mc_configure
  local tmp_zip tmp_dir source_dir source_fingerprint archive_sha256
  tmp_zip="$(mktemp /tmp/worlds.XXXXXX.zip)" \
    || die "Failed to create world archive temporary file"
  tmp_dir="$(mktemp -d /tmp/worlds.extract.XXXXXX)" || {
    cleanup_world_install_temps "${tmp_zip}" ""
    die "Failed to create world extraction directory"
  }

  log INFO "Downloading worlds zip from s3://${WORLD_S3_BUCKET}/${WORLD_S3_KEY}"
  if ! mc cp "s3/${WORLD_S3_BUCKET}/${WORLD_S3_KEY}" "${tmp_zip}"; then
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "Failed to download worlds zip"
  fi

  if ! unzip -tq "${tmp_zip}" >/dev/null; then
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "World archive failed integrity validation"
  fi

  if ! validate_zip_entries_safe "${tmp_zip}"; then
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "World archive contains unsafe paths"
  fi

  source_fingerprint="$(world_source_fingerprint)"
  archive_sha256="$(sha256sum "${tmp_zip}" | awk '{print $1}')"
  [[ -n "${source_fingerprint}" && -n "${archive_sha256}" ]] || {
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "Failed to fingerprint world source"
  }

  log INFO "Extracting worlds zip"
  if ! unzip -q "${tmp_zip}" -d "${tmp_dir}"; then
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "Failed to unzip worlds archive"
  fi

  if [[ -d "${tmp_dir}/worlds" ]]; then
    source_dir="${tmp_dir}/worlds"
  else
    source_dir="${tmp_dir}"
  fi

  if ! find "${source_dir}" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
    die "World archive is empty"
  fi

  if worlds_directory_has_content; then
    log WARN "Replacing existing worlds because WORLD_REPLACE=true"
  fi

  activate_dir_atomic "${source_dir}" "${DATA_DIR}/worlds" "worlds" true
  write_world_state_marker "${source_fingerprint}" "${archive_sha256}"
  cleanup_world_install_temps "${tmp_zip}" "${tmp_dir}"
  log INFO "World archive installed successfully"
}
