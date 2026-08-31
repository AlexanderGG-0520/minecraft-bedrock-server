# shellcheck shell=bash

MANAGED_STATE_SCHEMA_VERSION=2

managed_state_read_schema_version() {
  local marker="$1"
  local context="$2"
  local version

  jq -e 'type == "object"' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt ${context}: ${marker}"

  version="$(jq -er '
    .schema_version
    | select(type == "number" and . >= 1 and floor == .)
    | tostring
  ' "${marker}" 2>/dev/null)" \
    || die "Invalid/corrupt ${context} schema_version: ${marker}"

  printf '%s\n' "${version}"
}

managed_state_validate_envelope() {
  local marker="$1"
  local state_type="$2"
  local schema_version="$3"

  jq -e \
    --arg state_type "${state_type}" \
    --argjson schema_version "${schema_version}" '
      type == "object"
      and .schema_version == $schema_version
      and .state_type == $state_type
    ' "${marker}" >/dev/null 2>&1
}

managed_state_migrate_envelope() {
  local from_version="$1"
  local to_version="$2"
  local source="$3"
  local output="$4"
  local state_type="$5"

  case "${from_version}:${to_version}" in
    1:2)
      jq --arg state_type "${state_type}" \
        '.schema_version = 2 | .state_type = $state_type' \
        "${source}" > "${output}"
      ;;
    *)
      return 1
      ;;
  esac
}

managed_state_ensure_current() {
  local marker="$1"
  local state_type="$2"
  local validator_fn="$3"
  local migration_fn="$4"
  local context="$5"
  local current_version

  if (( $# >= 6 )); then
    current_version="$6"
    shift 6
  else
    current_version="${MANAGED_STATE_SCHEMA_VERSION}"
    shift 5
  fi
  local validator_args=("$@")
  local version next_version marker_dir marker_base working next_tmp

  [[ -f "${marker}" ]] || return 0

  version="$(managed_state_read_schema_version "${marker}" "${context}")"
  if (( version > current_version )); then
    die "Unsupported future ${context} schema ${version}; runtime supports up to ${current_version}: ${marker}"
  fi

  if (( version == current_version )); then
    managed_state_validate_envelope "${marker}" "${state_type}" "${current_version}" \
      || die "Invalid/corrupt ${context} envelope: ${marker}"
    "${validator_fn}" "${marker}" "${validator_args[@]}" \
      || die "Invalid/corrupt ${context}: ${marker}"
    return 0
  fi

  marker_dir="$(dirname "${marker}")"
  marker_base="$(basename "${marker}")"
  working="$(mktemp "${marker_dir}/.${marker_base}.migrate.XXXXXX")" \
    || die "Failed to create ${context} migration temporary file"
  cp -- "${marker}" "${working}" \
    || { safe_rm_f "${working}" || true; die "Failed to stage ${context} for migration"; }

  while (( version < current_version )); do
    next_version=$((version + 1))
    next_tmp="$(mktemp "${marker_dir}/.${marker_base}.migrate-next.XXXXXX")" \
      || { safe_rm_f "${working}" || true; die "Failed to create next ${context} migration temporary file"; }

    if ! "${migration_fn}" "${version}" "${next_version}" "${working}" "${next_tmp}" "${state_type}"; then
      safe_rm_f "${working}" || true
      safe_rm_f "${next_tmp}" || true
      die "No supported ${context} migration path from schema ${version} to ${next_version}"
    fi

    safe_rm_f "${working}" || true
    working="${next_tmp}"
    version="$(managed_state_read_schema_version "${working}" "migrated ${context}")"
    [[ "${version}" == "${next_version}" ]] \
      || { safe_rm_f "${working}" || true; die "${context} migration produced unexpected schema ${version}; expected ${next_version}"; }
  done

  managed_state_validate_envelope "${working}" "${state_type}" "${current_version}" \
    || { safe_rm_f "${working}" || true; die "Migrated ${context} has an invalid envelope"; }
  "${validator_fn}" "${working}" "${validator_args[@]}" \
    || { safe_rm_f "${working}" || true; die "Migrated ${context} failed semantic validation"; }
  chmod 0644 "${working}" \
    || { safe_rm_f "${working}" || true; die "Failed to set migrated ${context} permissions"; }

  safe_mv_f "${working}" "${marker}" \
    || { safe_rm_f "${working}" || true; die "Failed to activate migrated ${context}"; }
  log INFO "Migrated ${context} schema to ${current_version}: ${marker}"
}
