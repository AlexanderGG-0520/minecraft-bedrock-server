# shellcheck shell=bash

world_pack_state_dir() {
  local level_name="$1"
  printf '%s/.managed/world-packs/%s\n' "${DATA_DIR}" "${level_name}"
}

world_pack_state_marker() {
  local level_name="$1"
  local kind="$2"
  printf '%s/%s.json\n' "$(world_pack_state_dir "${level_name}")" "${kind}"
}

validate_world_pack_level_name() {
  local level_name="$1"
  [[ -n "${level_name}" ]] || return 1
  [[ "${level_name}" != "." && "${level_name}" != ".." ]] || return 1
  [[ "${level_name}" != */* && "${level_name}" != *\\* ]] || return 1
  [[ "${level_name}" != *$'\n'* && "${level_name}" != *$'\r'* ]] || return 1
}

resolve_world_pack_level_name() {
  local level_name
  if [[ -n "${WORLD_PACKS_LEVEL_NAME}" ]]; then
    level_name="${WORLD_PACKS_LEVEL_NAME}"
  else
    level_name="$(sed -n 's/^level-name=//p' "${DATA_DIR}/server.properties" | head -n1 | tr -d '\r')"
  fi

  validate_world_pack_level_name "${level_name}" \
    || die "Unable to resolve a safe world name for pack binding; set WORLD_PACKS_LEVEL_NAME explicitly"
  printf '%s\n' "${level_name}"
}

validate_world_pack_state_marker() {
  local marker="$1"
  local level_name="$2"
  local kind="$3"

  jq -e --arg level_name "${level_name}" --arg kind "${kind}" '
    type == "object"
    and .schema_version == 1
    and .level_name == $level_name
    and .kind == $kind
    and (.managed_pack_ids | type == "array")
    and all(.managed_pack_ids[]; type == "string" and length > 0)
  ' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt managed world-pack marker: ${marker}"
}

prepare_world_pack_previous_ids() {
  local level_name="$1"
  local kind="$2"
  local marker tmp

  marker="$(world_pack_state_marker "${level_name}" "${kind}")"
  tmp="$(mktemp "/tmp/world-${kind}.previous.XXXXXX.json")" \
    || die "Failed to create previous ${kind} pack-id temporary file"

  if [[ -f "${marker}" ]]; then
    validate_world_pack_state_marker "${marker}" "${level_name}" "${kind}"
    jq '.managed_pack_ids' "${marker}" > "${tmp}" \
      || { safe_rm_f "${tmp}" || true; die "Failed to read previous ${kind} pack ownership"; }
  else
    printf '[]\n' > "${tmp}"
  fi
  WORLD_PACK_PREVIOUS_IDS_TMP="${tmp}"
}

prepare_world_pack_marker() {
  local level_name="$1"
  local kind="$2"
  local ids_file="$3"
  local marker marker_dir tmp

  marker="$(world_pack_state_marker "${level_name}" "${kind}")"
  marker_dir="$(dirname "${marker}")"
  mkdir -p "${marker_dir}"
  tmp="$(mktemp "${marker_dir}/.${kind}.json.tmp.XXXXXX")" \
    || die "Failed to create ${kind} world-pack marker temporary file"

  if ! jq -n \
    --arg level_name "${level_name}" \
    --arg kind "${kind}" \
    --slurpfile ids "${ids_file}" \
    '{schema_version:1,level_name:$level_name,kind:$kind,managed_pack_ids:$ids[0]}' \
    > "${tmp}"; then
    safe_rm_f "${tmp}" || true
    die "Failed to build ${kind} world-pack marker"
  fi
  chmod 0644 "${tmp}" \
    || { safe_rm_f "${tmp}" || true; die "Failed to set ${kind} world-pack marker permissions"; }

  WORLD_PACK_MARKER_PATH="${marker}"
  WORLD_PACK_MARKER_TMP="${tmp}"
}

validate_pack_manifest() {
  local manifest="$1"
  local kind="$2"

  jq -e --arg kind "${kind}" '
    type == "object"
    and (.header | type == "object")
    and (.header.uuid | type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"))
    and (.header.version | type == "array" and length == 3)
    and all(.header.version[]; type == "number" and . >= 0 and floor == .)
    and (.modules | type == "array" and length > 0)
    and (
      if $kind == "behavior" then
        any(.modules[]; .type == "data" or .type == "script")
      else
        any(.modules[]; .type == "resources")
      end
    )
  ' "${manifest}" >/dev/null 2>&1 \
    || die "Invalid ${kind} pack manifest for world binding: ${manifest}"
}

collect_managed_pack_bindings() {
  local kind="$1"
  local content_name="$2"
  local pack_dir="$3"
  local content_marker entry manifest tmp

  tmp="$(mktemp "/tmp/world-${kind}.desired.XXXXXX.json")" \
    || die "Failed to create desired ${kind} binding temporary file"
  printf '[]\n' > "${tmp}"

  content_marker="$(content_state_marker "${content_name}")"
  if [[ ! -f "${content_marker}" ]]; then
    log INFO "No managed ${content_name} ownership marker; desired ${kind} world binding is empty"
    WORLD_PACK_DESIRED_TMP="${tmp}"
    return 0
  fi

  validate_content_state_marker "${content_marker}"
  while IFS= read -r entry; do
    manifest="${pack_dir}/${entry}/manifest.json"
    [[ -d "${pack_dir}/${entry}" && -f "${manifest}" ]] \
      || { safe_rm_f "${tmp}" || true; die "Managed ${content_name} entry cannot be bound because manifest.json is missing: ${entry}"; }
    validate_pack_manifest "${manifest}" "${kind}"

    local next
    next="$(mktemp "/tmp/world-${kind}.desired-next.XXXXXX.json")" \
      || { safe_rm_f "${tmp}" || true; die "Failed to extend desired ${kind} bindings"; }
    jq --argjson binding "$(jq -c '{pack_id:.header.uuid,version:.header.version}' "${manifest}")" \
      '. + [$binding]' "${tmp}" > "${next}" \
      || { safe_rm_f "${tmp}" || true; safe_rm_f "${next}" || true; die "Failed to collect ${kind} pack binding"; }
    safe_mv_f "${next}" "${tmp}" \
      || { safe_rm_f "${tmp}" || true; safe_rm_f "${next}" || true; die "Failed to update desired ${kind} bindings"; }
  done < <(jq -r '.managed_entries[]' "${content_marker}")

  jq -e '([.[].pack_id] | length) == ([.[].pack_id] | unique | length)' "${tmp}" >/dev/null \
    || { safe_rm_f "${tmp}" || true; die "Duplicate pack UUID detected in managed ${content_name}"; }
  WORLD_PACK_DESIRED_TMP="${tmp}"
}

validate_existing_world_binding() {
  local file="$1"
  local kind="$2"

  jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (.pack_id | type == "string" and length > 0)
      and (.version | type == "array" and length == 3)
      and all(.version[]; type == "number" and . >= 0 and floor == .)
    )
  ' "${file}" >/dev/null 2>&1 \
    || die "Current world_${kind}_packs.json is invalid/corrupt: ${file}"
}

activate_world_pack_binding_state() {
  local kind="$1"
  local target="$2"
  local data_tmp="$3"
  local marker_tmp="$4"
  local marker_path="$5"
  local parent base backup

  parent="$(dirname "${target}")"
  base="$(basename "${target}")"
  chmod 0644 "${data_tmp}" \
    || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to set ${kind} binding permissions"; }

  backup="$(mktemp "${parent}/.${base}.old.XXXXXX")" \
    || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to create ${kind} binding backup path"; }
  safe_rm_f "${backup}"

  if [[ -f "${target}" ]]; then
    safe_mv "${target}" "${backup}" \
      || { safe_rm_f "${data_tmp}" || true; safe_rm_f "${marker_tmp}" || true; die "Failed to preserve current ${kind} world binding"; }
  fi

  if ! safe_mv_f "${data_tmp}" "${target}"; then
    [[ ! -f "${backup}" ]] || safe_mv_f "${backup}" "${target}" || true
    safe_rm_f "${data_tmp}" || true
    safe_rm_f "${marker_tmp}" || true
    die "Failed to activate ${kind} world binding"
  fi

  if ! safe_mv_f "${marker_tmp}" "${marker_path}"; then
    safe_rm_f "${target}" || true
    [[ ! -f "${backup}" ]] || safe_mv_f "${backup}" "${target}" || true
    die "Failed to activate ${kind} world-pack ownership marker"
  fi

  [[ ! -f "${backup}" ]] || safe_rm_f "${backup}"
}

bind_managed_pack_kind() {
  local level_name="$1"
  local kind="$2"
  local content_name="$3"
  local pack_dir="$4"
  local target desired existing previous current_ids next_ids output marker

  collect_managed_pack_bindings "${kind}" "${content_name}" "${pack_dir}"
  desired="${WORLD_PACK_DESIRED_TMP}"
  target="${DATA_DIR}/worlds/${level_name}/world_${kind}_packs.json"

  existing="$(mktemp "/tmp/world-${kind}.existing.XXXXXX.json")" \
    || { safe_rm_f "${desired}" || true; die "Failed to create current ${kind} binding temporary file"; }
  if [[ -f "${target}" ]]; then
    cp -- "${target}" "${existing}" \
      || { safe_rm_f "${desired}" || true; safe_rm_f "${existing}" || true; die "Failed to stage current ${kind} world binding"; }
  else
    printf '[]\n' > "${existing}"
  fi
  validate_existing_world_binding "${existing}" "${kind}"

  prepare_world_pack_previous_ids "${level_name}" "${kind}"
  previous="${WORLD_PACK_PREVIOUS_IDS_TMP}"
  current_ids="$(mktemp "/tmp/world-${kind}.current-ids.XXXXXX.json")" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}"; die "Failed to create current ${kind} pack-id file"; }
  jq '[.[].pack_id] | unique' "${desired}" > "${current_ids}"

  next_ids="$(mktemp "/tmp/world-${kind}.next-ids.XXXXXX.json")" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_ids}"; die "Failed to create next ${kind} pack-id file"; }
  if is_true "${WORLD_PACKS_REMOVE_EXTRA}"; then
    cp -- "${current_ids}" "${next_ids}"
  else
    jq -n --slurpfile previous "${previous}" --slurpfile current "${current_ids}" \
      '($previous[0] + $current[0]) | unique' > "${next_ids}"
  fi

  output="$(mktemp "${DATA_DIR}/worlds/${level_name}/.world_${kind}_packs.json.tmp.XXXXXX")" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_ids}" "${next_ids}"; die "Failed to create ${kind} binding output file"; }
  jq -n \
    --slurpfile existing "${existing}" \
    --slurpfile desired "${desired}" \
    --slurpfile previous "${previous}" \
    --argjson remove_extra "$(is_true "${WORLD_PACKS_REMOVE_EXTRA}" && printf true || printf false)" '
      ($existing[0]) as $old
      | ($desired[0]) as $wanted
      | ($previous[0]) as $owned
      | [
          $old[] as $entry
          | ($wanted | map(select(.pack_id == $entry.pack_id)) | first) as $replacement
          | if $replacement != null then ($entry + $replacement)
            elif $remove_extra and (($owned | index($entry.pack_id)) != null) then empty
            else $entry
            end
        ]
        + [
            $wanted[] as $entry
            | select(($old | map(.pack_id) | index($entry.pack_id)) == null)
            | $entry
          ]
    ' > "${output}" \
    || { cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_ids}" "${next_ids}" "${output}"; die "Failed to merge ${kind} world bindings"; }

  prepare_world_pack_marker "${level_name}" "${kind}" "${next_ids}"
  marker="${WORLD_PACK_MARKER_PATH}"
  activate_world_pack_binding_state "${kind}" "${target}" "${output}" "${WORLD_PACK_MARKER_TMP}" "${marker}"
  cleanup_player_access_temps "${desired}" "${existing}" "${previous}" "${current_ids}" "${next_ids}"
  log INFO "Managed ${kind} packs bound to world '${level_name}' (remove_extra=${WORLD_PACKS_REMOVE_EXTRA})"
}

bind_managed_world_packs() {
  is_true "${WORLD_PACKS_BINDING_ENABLED}" || {
    log INFO "World pack binding disabled"
    return 0
  }

  local level_name world_dir
  level_name="$(resolve_world_pack_level_name)"
  world_dir="${DATA_DIR}/worlds/${level_name}"
  [[ -d "${world_dir}" ]] \
    || die "World pack binding requires an existing world directory: ${world_dir}"

  bind_managed_pack_kind "${level_name}" "behavior" "behavior_packs" "${DATA_DIR}/behavior_packs"
  bind_managed_pack_kind "${level_name}" "resource" "resource_packs" "${DATA_DIR}/resource_packs"
}
