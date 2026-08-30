# shellcheck shell=bash

set_prop() {
  local key="$1"
  local value="$2"
  local file="${DATA_DIR}/server.properties"

  touch "${file}"
  if grep -qE "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

apply_server_properties_from_env() {
  local file="${DATA_DIR}/server.properties"
  local env_key prop_key env_val

  [[ -f "${file}" ]] || die "server.properties not found at ${file}"

  log INFO "Applying server.properties overrides from ENV (only non-empty vars)"

  for env_key in "${!PROP_MAP[@]}"; do
    prop_key="${PROP_MAP[$env_key]}"
    env_val="${!env_key:-}"
    env_val="$(trim_ws "${env_val}")"
    [[ -z "${env_val}" ]] && continue
    set_prop "${prop_key}" "${env_val}"
  done

  if [[ -n "${BDS_PROPERTIES:-}" ]]; then
    local -a items
    local item key value
    IFS=',' read -ra items <<< "${BDS_PROPERTIES}"

    for item in "${items[@]}"; do
      item="$(trim_ws "${item}")"
      [[ -z "${item}" ]] && continue
      [[ "${item}" == *"="* ]] \
        || die "Invalid BDS_PROPERTIES item: '${item}' (expected key=value)"

      key="$(trim_ws "${item%%=*}")"
      value="$(trim_ws "${item#*=}")"
      [[ -n "${key}" ]] \
        || die "Invalid BDS_PROPERTIES item: '${item}' (empty key)"
      set_prop "${key}" "${value}"
    done
  fi

  if is_true "${ENABLE_RCON}"; then
    set_prop "enable-rcon" "true"
    set_prop "rcon.port" "${RCON_PORT}"
    set_prop "rcon.password" "${RCON_PASSWORD}"
  else
    set_prop "enable-rcon" "false"
  fi
}
