# shellcheck shell=bash

player_access_state_dir() {
  printf '%s/.managed/player-access\n' "${DATA_DIR}"
}

player_access_state_marker() {
  local kind="$1"
  printf '%s/%s.json\n' "$(player_access_state_dir)" "${kind}"
}

validate_player_access_state_marker() {
  local marker="$1"
  local kind="$2"

  jq -e --arg kind "${kind}" '
    type == "object"
    and .schema_version == 1
    and .kind == $kind
    and (.managed_keys | type == "array")
    and all(.managed_keys[]; type == "string" and length > 0)
  ' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt managed player-access marker: ${marker}"
}

load_player_access_source() {
  local kind="$1"
  local json_value="$2"
  local file_value="$3"
  local tmp

  PLAYER_ACCESS_SOURCE_TMP=""
  if [[ -z "${json_value}" && -z "${file_value}" ]]; then
    return 1
  fi

  tmp="$(mktemp "/tmp/${kind}.desired.XXXXXX.json")" \
    || die "Failed to create ${kind} desired-state temporary file"

  if [[ -n "${json_value}" ]]; then
    printf '%s\n' "${json_value}" > "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to stage ${kind} JSON"; }
  else
    cp -- "${file_value}" "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to read ${kind} source file: ${file_value}"; }
  fi

  PLAYER_ACCESS_SOURCE_TMP="${tmp}"
}

prepare_existing_json_array() {
  local target="$1"
  local kind="$2"
  local tmp

  tmp="$(mktemp "/tmp/${kind}.existing.XXXXXX.json")" \
    || die "Failed to create ${kind} existing-state temporary file"
  if [[ -f "${target}" ]]; then
    cp -- "${target}" "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to stage current ${kind} state"; }
  else
    printf '[]\n' > "${tmp}"
  fi
  PLAYER_ACCESS_EXISTING_TMP="${tmp}"
}

prepare_previous_managed_keys() {
  local kind="$1"
  local marker tmp

  marker="$(player_access_state_marker "${kind}")"
  tmp="$(mktemp "/tmp/${kind}.managed-keys.XXXXXX.json")" \
    || die "Failed to create ${kind} managed-key temporary file"

  if [[ -f "${marker}" ]]; then
    validate_player_access_state_marker "${marker}" "${kind}"
    jq '.managed_keys' "${marker}" > "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to read managed ${kind} keys"; }
  else
    printf '[]\n' > "${tmp}"
  fi
  PLAYER_ACCESS_PREVIOUS_KEYS_TMP="${tmp}"
}

prepare_next_managed_keys() {
  local current_keys="$1"
  local previous_keys="$2"
  local remove_extra="$3"
  local kind="$4"
  local tmp

  tmp="$(mktemp "/tmp/${kind}.next-keys.XXXXXX.json")" \
    || die "Failed to create ${kind} next-key temporary file"

  if is_true "${remove_extra}"; then
    jq 'unique' "${current_keys}" > "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to prepare managed ${kind} keys"; }
  else
    jq -n --slurpfile previous "${previous_keys}" --slurpfile current "${current_keys}" \
      '($previous[0] + $current[0]) | unique' > "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to merge managed ${kind} keys"; }
  fi
  PLAYER_ACCESS_NEXT_KEYS_TMP="${tmp}"
}

prepare_player_access_marker() {
  local kind="$1"
  local keys_file="$2"
  local marker marker_dir tmp

  marker="$(player_access_state_marker "${kind}")"
  marker_dir="$(dirname "${marker}")"
  mkdir -p "${marker_dir}"
  tmp="$(mktemp "${marker_dir}/.${kind}.json.tmp.XXXXXX")" \
    || die "Failed to create managed ${kind} marker temporary file"

  if ! jq -n --arg kind "${kind}" --slurpfile keys "${keys_file}" \
    '{schema_version:1,kind:$kind,managed_keys:$keys[0]}' > "${tmp}"; then
    safe_rm_f "${tmp}" || true
    die "Failed to build managed ${kind} marker"
  fi
  chmod 0644 "${tmp}" \
    || { safe_rm_f "${tmp}" || true; die "Failed to set managed ${kind} marker permissions"; }

  PLAYER_ACCESS_MARKER_PATH="${marker}"
  PLAYER_ACCESS_MARKER_TMP="${tmp}"
}

activate_player_access_state() {
  local kind="$1"
  local target="$2"
  local data_tmp="$3"
  local marker_tmp="$4"
  local marker_path="$5"
  local parent base backup

  parent="$(dirname "${target}")"
  base="$(basename "${target}")"
  mkdir -p "${parent}"
  chmod 0644 "${data_tmp}" \
    || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to set ${kind} permissions"; }

  backup="$(mktemp "${parent}/.${base}.old.XXXXXX")" \
    || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to create ${kind} backup path"; }
  safe_rm_f "${backup}"

  if [[ -f "${target}" ]]; then
    safe_mv "${target}" "${backup}" \
      || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to preserve current ${kind}"; }
  fi

  if ! safe_mv_f "${data_tmp}" "${target}"; then
    [[ ! -f "${backup}" ]] || safe_mv_f "${backup}" "${target}" || true
    safe_rm_f "${data_tmp}" || true
    safe_rm_f "${marker_tmp}" || true
    die "Failed to activate managed ${kind} state"
  fi

  if ! safe_mv_f "${marker_tmp}" "${marker_path}"; then
    safe_rm_f "${target}" || true
    [[ ! -f "${backup}" ]] || safe_mv_f "${backup}" "${target}" || true
    die "Failed to activate managed ${kind} marker"
  fi

  [[ ! -f "${backup}" ]] || safe_rm_f "${backup}"
}

cleanup_player_access_temps() {
  local path
  for path in "$@"; do
    [[ -z "${path}" ]] || safe_rm_f "${path}" || true
  done
}

manage_allowlist() {
  local desired existing previous current_keys next_keys output target marker

  if ! load_player_access_source "allowlist" "${BDS_ALLOWLIST_JSON}" "${BDS_ALLOWLIST_FILE}"; then
    log INFO "No managed allowlist source configured, preserving BDS allowlist.json"
    return 0
  fi
  desired="${PLAYER_ACCESS_SOURCE_TMP}"
  target="${DATA_DIR}/allowlist.json"

  jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and ((keys - ["ignoresPlayerLimit","name","xuid"]) | length == 0)
      and (.name | type == "string" and length > 0)
      and (.name | contains("\n") | not)
      and (.name | contains("\r") | not)
      and ((has("xuid") | not) or (.xuid | type == "string" and length > 0))
      and ((has("ignoresPlayerLimit") | not) or (.ignoresPlayerLimit | type == "boolean"))
    )
    and ((map(.name) | length) == (map(.name) | unique | length))
  ' "${desired}" >/dev/null \
    || { cleanup_player_access_temps "${desired}"; die "Invalid managed allowlist JSON"; }

  local normalized
  normalized="$(mktemp /tmp/allowlist.normalized.XXXXXX.json)" \
    || { cleanup_player_access_temps "${desired}"; die "Failed to create normalized allowlist temporary file"; }
  jq 'map(if has("ignoresPlayerLimit") then . else . + {ignoresPlayerLimit:false} end)' \
    "${desired}" > "${normalized}" \
    || { cleanup_player_access_temps "${desired}" "${normalized}"; die "Failed to normalize managed allowlist"; }

  prepare_existing_json_array "${target}" "allowlist"
  existing="${PLAYER_ACCESS_EXISTING_TMP}"
  jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (.name | type == "string" and length > 0)
      and ((has("xuid") | not) or (.xuid | type == "string"))
      and ((has("ignoresPlayerLimit") | not) or (.ignoresPlayerLimit | type == "boolean"))
    )
  ' "${existing}" >/dev/null \
    || { cleanup_player_access_temps "${desired}" "${normalized}" "${existing}"; die "Current allowlist.json is invalid/corrupt"; }

  prepare_previous_managed_keys "allowlist"
  previous="${PLAYER_ACCESS_PREVIOUS_KEYS_TMP}"
  current_keys="$(mktemp /tmp/allowlist.current-keys.XXXXXX.json)" \
    || { cleanup_player_access_temps "${desired}" "${normalized}" "${existing}" "${previous}"; die "Failed to create allowlist key temporary file"; }
  jq '[.[].name] | unique' "${normalized}" > "${current_keys}"
  prepare_next_managed_keys "${current_keys}" "${previous}" "${BDS_ALLOWLIST_REMOVE_EXTRA}" "allowlist"
  next_keys="${PLAYER_ACCESS_NEXT_KEYS_TMP}"

  output="$(mktemp "${DATA_DIR}/.allowlist.json.tmp.XXXXXX")" \
    || { cleanup_player_access_temps "${desired}" "${normalized}" "${existing}" "${previous}" "${current_keys}" "${next_keys}"; die "Failed to create allowlist output temporary file"; }
  jq -n \
    --slurpfile existing "${existing}" \
    --slurpfile desired "${normalized}" \
    --slurpfile previous "${previous}" \
    --argjson remove_extra "$(is_true "${BDS_ALLOWLIST_REMOVE_EXTRA}" && printf true || printf false)" '
      ($existing[0]) as $old
      | ($desired[0]) as $wanted
      | ($previous[0]) as $owned
      | [
          $old[] as $entry
          | ($wanted | map(select(.name == $entry.name)) | first) as $replacement
          | if $replacement != null then ($entry + $replacement)
            elif $remove_extra and (($owned | index($entry.name)) != null) then empty
            else $entry
            end
        ]
        + [
            $wanted[] as $entry
            | select(($old | map(.name) | index($entry.name)) == null)
            | $entry
          ]
    ' > "${output}" \
    || { cleanup_player_access_temps "${desired}" "${normalized}" "${existing}" "${previous}" "${current_keys}" "${next_keys}" "${output}"; die "Failed to merge managed allowlist"; }

  prepare_player_access_marker "allowlist" "${next_keys}"
  marker="${PLAYER_ACCESS_MARKER_PATH}"
  activate_player_access_state "allowlist" "${target}" "${output}" "${PLAYER_ACCESS_MARKER_TMP}" "${marker}"
  cleanup_player_access_temps "${desired}" "${normalized}" "${existing}" "${previous}" "${current_keys}" "${next_keys}"
  log INFO "Managed allowlist applied (remove_extra=${BDS_ALLOWLIST_REMOVE_EXTRA})"
}

manage_permissions() {
  local desired existing previous current_keys next_keys output target marker

  if ! load_player_access_source "permissions" "${BDS_PERMISSIONS_JSON}" "${BDS_PERMISSIONS_FILE}"; then
    log INFO "No managed permissions source configured, preserving BDS permissions.json"
    return 0
  fi
  desired="${PLAYER_ACCESS_SOURCE_TMP}"
  target="${DATA_DIR}/permissions.json"

  jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and ((keys - ["permission","xuid"]) | length == 0)
      and (.xuid | type == "string" and length > 0)
      and (.permission | type == "string" and (. == "visitor" or . == "member" or . == "operator"))
    )
    and ((map(.xuid) | length) == (map(.xuid) | unique | length))
  ' "${desired}" >/dev/null \
    || { cleanup_player_access_temps "${desired}"; die "Invalid managed permissions JSON"; }

  prepare_existing_json_array "${target}" "permissions"
  existing="${PLAYER_ACCESS_EXISTING_TMP}"
  jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (.xuid | type == "string" and length > 0)
      and (.permission | type == "string" and (. == "visitor" or . == "member" or . == "operator" or . == "custom"))
    )
  ' "${existing}" >/dev/null \
    || { cleanup_player_access_temps "${desired}" "${existing}"; die "Current permissions.json is invalid/corrupt"; }

  prepare_previous_managed_keys "permissions"
  previous="${PLAYER_ACCESS_PREVIOUS_KEYS_TMP}"
  current_keys="$(mktemp /tmp/permissions.current-keys.XXXXXX.json)" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}"; die "Failed to create permissions key temporary file"; }
  jq '[.[].xuid] | unique' "${desired}" > "${current_keys}"
  prepare_next_managed_keys "${current_keys}" "${previous}" "${BDS_PERMISSIONS_REMOVE_EXTRA}" "permissions"
  next_keys="${PLAYER_ACCESS_NEXT_KEYS_TMP}"

  output="$(mktemp "${DATA_DIR}/.permissions.json.tmp.XXXXXX")" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_keys}" "${next_keys}"; die "Failed to create permissions output temporary file"; }
  jq -n \
    --slurpfile existing "${existing}" \
    --slurpfile desired "${desired}" \
    --slurpfile previous "${previous}" \
    --argjson remove_extra "$(is_true "${BDS_PERMISSIONS_REMOVE_EXTRA}" && printf true || printf false)" '
      ($existing[0]) as $old
      | ($desired[0]) as $wanted
      | ($previous[0]) as $owned
      | [
          $old[] as $entry
          | ($wanted | map(select(.xuid == $entry.xuid)) | first) as $replacement
          | if $replacement != null then ($entry + $replacement)
            elif $remove_extra and (($owned | index($entry.xuid)) != null) then empty
            else $entry
            end
        ]
        + [
            $wanted[] as $entry
            | select(($old | map(.xuid) | index($entry.xuid)) == null)
            | $entry
          ]
    ' > "${output}" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_keys}" "${next_keys}" "${output}"; die "Failed to merge managed permissions"; }

  prepare_player_access_marker "permissions" "${next_keys}"
  marker="${PLAYER_ACCESS_MARKER_PATH}"
  activate_player_access_state "permissions" "${target}" "${output}" "${PLAYER_ACCESS_MARKER_TMP}" "${marker}"
  cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_keys}" "${next_keys}"
  log INFO "Managed permissions applied (remove_extra=${BDS_PERMISSIONS_REMOVE_EXTRA})"
}

manage_player_access() {
  manage_allowlist
  manage_permissions
}
