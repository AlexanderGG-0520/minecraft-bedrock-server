# shellcheck shell=bash

content_state_dir() {
  printf '%s/.managed/content-assets\n' "${DATA_DIR}"
}

content_state_marker() {
  local name="$1"
  printf '%s/%s.json\n' "$(content_state_dir)" "${name}"
}

validate_managed_entry_name() {
  local entry="$1"

  [[ -n "${entry}" ]] || return 1
  [[ "${entry}" != "." && "${entry}" != ".." ]] || return 1
  [[ "${entry}" != */* && "${entry}" != *$'\n'* && "${entry}" != *$'\r'* ]] || return 1
}

collect_top_level_entries() {
  local directory="$1"
  local entry base
  CONTENT_STATE_ENTRIES=()

  while IFS= read -r -d '' entry; do
    base="$(basename -- "${entry}")"
    validate_managed_entry_name "${base}" \
      || die "Unsupported managed content entry name: ${base}"
    CONTENT_STATE_ENTRIES+=("${base}")
  done < <(find "${directory}" -mindepth 1 -maxdepth 1 -print0 | sort -z)
}

validate_content_state_marker() {
  local marker="$1"

  jq -e '
    type == "object"
    and .schema_version == 1
    and (.name | type == "string" and length > 0)
    and (.managed_entries | type == "array")
    and all(.managed_entries[]; type == "string" and length > 0)
  ' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt managed content marker: ${marker}"

  local entry
  while IFS= read -r entry; do
    validate_managed_entry_name "${entry}" \
      || die "Unsafe entry in managed content marker: ${marker}"
  done < <(jq -r '.managed_entries[]' "${marker}")
}

read_managed_content_entries() {
  local marker="$1"
  PREVIOUS_MANAGED_ENTRIES=()

  [[ -f "${marker}" ]] || return 0
  validate_content_state_marker "${marker}"

  local entry
  while IFS= read -r entry; do
    PREVIOUS_MANAGED_ENTRIES+=("${entry}")
  done < <(jq -r '.managed_entries[]' "${marker}")
}

entry_in_array() {
  local needle="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ "${entry}" == "${needle}" ]] && return 0
  done
  return 1
}

prepare_content_state_marker() {
  local name="$1"
  local marker tmp
  shift
  local entries=("$@")

  mkdir -p "$(content_state_dir)"
  marker="$(content_state_marker "${name}")"
  tmp="$(mktemp "$(content_state_dir)/.${name}.json.tmp.XXXXXX")" \
    || die "Failed to create managed content marker temporary file"

  if ! printf '%s\n' "${entries[@]}" \
    | jq -R -s --arg name "${name}" '
        split("\n")
        | map(select(length > 0))
        | unique
        | {schema_version:1,name:$name,managed_entries:.}
      ' > "${tmp}"; then
    safe_rm_f "${tmp}" || true
    die "Failed to build managed content marker for ${name}"
  fi
  chmod 0644 "${tmp}" \
    || { safe_rm_f "${tmp}" || true; die "Failed to set managed content marker permissions for ${name}"; }

  CONTENT_STATE_MARKER_PATH="${marker}"
  CONTENT_STATE_MARKER_TMP="${tmp}"
}

activate_managed_content() {
  local src="$1"
  local dst="$2"
  local name="$3"
  local remove_extra="$4"
  local parent base staging backup marker

  [[ -d "${src}" ]] || {
    log INFO "No ${name} input directory found (${src}), skipping activation"
    return 0
  }

  if ! find "${src}" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    log INFO "${name} input directory is empty (${src}), skipping activation"
    return 0
  fi

  marker="$(content_state_marker "${name}")"
  collect_top_level_entries "${src}"
  local current_entries=("${CONTENT_STATE_ENTRIES[@]}")
  read_managed_content_entries "${marker}"
  local previous_entries=("${PREVIOUS_MANAGED_ENTRIES[@]}")
  local next_entries=("${current_entries[@]}")

  if ! is_true "${remove_extra}"; then
    local old_entry
    for old_entry in "${previous_entries[@]}"; do
      if ! entry_in_array "${old_entry}" "${next_entries[@]}"; then
        next_entries+=("${old_entry}")
      fi
    done
  fi

  parent="$(dirname "${dst}")"
  base="$(basename "${dst}")"
  mkdir -p "${parent}" "$(content_state_dir)"

  staging="$(mktemp -d "${parent}/.${base}.staging.XXXXXX")" \
    || die "Failed to create ${name} staging directory"
  backup="$(mktemp -d "${parent}/.${base}.old.XXXXXX")" \
    || { safe_rm_rf "${staging}"; die "Failed to create ${name} backup directory"; }
  safe_rm_rf "${backup}"

  if [[ -d "${dst}" ]]; then
    rsync -a "${dst}/" "${staging}/" \
      || { safe_rm_rf "${staging}" || true; die "Failed to seed ${name} staging directory"; }
  fi

  local entry
  for entry in "${current_entries[@]}"; do
    safe_rm_rf "${staging}/${entry}" || true
    if [[ -d "${src}/${entry}" ]]; then
      mkdir -p "${staging}/${entry}"
      rsync -a "${src}/${entry}/" "${staging}/${entry}/" \
        || { safe_rm_rf "${staging}" || true; die "Failed to stage ${name} entry: ${entry}"; }
    else
      cp -a -- "${src}/${entry}" "${staging}/${entry}" \
        || { safe_rm_rf "${staging}" || true; die "Failed to stage ${name} entry: ${entry}"; }
    fi
  done

  if is_true "${remove_extra}"; then
    for entry in "${previous_entries[@]}"; do
      if ! entry_in_array "${entry}" "${current_entries[@]}"; then
        log INFO "Removing stale managed ${name} entry: ${entry}"
        safe_rm_rf "${staging}/${entry}" \
          || { safe_rm_rf "${staging}" || true; die "Failed to remove stale managed ${name} entry: ${entry}"; }
      fi
    done
  fi

  prepare_content_state_marker "${name}" "${next_entries[@]}"

  log INFO "Activating managed ${name} (${src} -> ${dst}, remove_extra=${remove_extra})"
  if [[ -d "${dst}" ]]; then
    safe_mv "${dst}" "${backup}" \
      || { safe_rm_rf "${staging}" || true; safe_rm_f "${CONTENT_STATE_MARKER_TMP}" || true; die "Failed to preserve current ${name}"; }
  fi

  if ! safe_mv "${staging}" "${dst}"; then
    [[ ! -d "${backup}" ]] || safe_mv "${backup}" "${dst}" || true
    safe_rm_rf "${staging}" || true
    safe_rm_f "${CONTENT_STATE_MARKER_TMP}" || true
    die "Failed to activate managed ${name}"
  fi

  if ! safe_mv_f "${CONTENT_STATE_MARKER_TMP}" "${CONTENT_STATE_MARKER_PATH}"; then
    safe_rm_rf "${dst}" || true
    [[ ! -d "${backup}" ]] || safe_mv "${backup}" "${dst}" || true
    die "Failed to activate managed content marker for ${name}"
  fi

  [[ ! -d "${backup}" ]] || safe_rm_rf "${backup}"
}
