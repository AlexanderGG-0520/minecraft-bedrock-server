# shellcheck shell=bash

BDS_INSTALL_MODE=""
BDS_REQUESTED_VERSION=""
BDS_RESOLVED_VERSION=""
BDS_RESOLVED_URL=""
BDS_SOURCE_FINGERPRINT=""

bds_install_marker() {
  printf '%s/.bds-install.json\n' "${DATA_DIR}"
}

bds_install_mode() {
  if [[ -n "${BDS_DOWNLOAD_URL}" ]]; then
    printf 'custom-url\n'
  elif [[ "${BDS_CHANNEL}" == "stable" ]]; then
    printf 'stable\n'
  elif [[ "${VERSION}" != "latest" ]]; then
    printf 'version\n'
  else
    printf 'latest\n'
  fi
}

bds_requested_version() {
  case "$1" in
    stable) printf '%s\n' "${BDS_STABLE_VERSION}" ;;
    version) printf '%s\n' "${VERSION}" ;;
    latest) printf 'latest\n' ;;
    custom-url)
      if [[ "${VERSION}" != "latest" ]]; then
        printf '%s\n' "${VERSION}"
      else
        printf 'custom\n'
      fi
      ;;
    *) return 1 ;;
  esac
}

extract_bds_version_from_url() {
  local filename
  filename="$(basename "${1%%\?*}")"
  if [[ "${filename}" =~ ^bedrock-server-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.zip$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

resolve_bds_download_url() {
  if [[ -n "${BDS_DOWNLOAD_URL}" ]]; then
    printf '%s\n' "${BDS_DOWNLOAD_URL}"
    return 0
  fi

  if [[ "${BDS_CHANNEL}" == "stable" ]]; then
    [[ -n "${BDS_STABLE_VERSION}" ]] || die "BDS_CHANNEL=stable requires BDS_STABLE_VERSION"
    printf 'https://minecraft.azureedge.net/bin-linux/bedrock-server-%s.zip\n' "${BDS_STABLE_VERSION}"
    return 0
  fi

  if [[ "${VERSION}" != "latest" ]]; then
    printf 'https://minecraft.azureedge.net/bin-linux/bedrock-server-%s.zip\n' "${VERSION}"
    return 0
  fi

  local page url
  page="$(curl -fsSL "https://www.minecraft.net/en-us/download/server/bedrock")" \
    || die "Failed to fetch official Bedrock server download page"
  url="$(printf '%s' "${page}" \
    | grep -Eo 'https://minecraft\.azureedge\.net/bin-linux/bedrock-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' \
    | head -n1 || true)"
  [[ -n "${url}" ]] || die "Failed to find Linux bedrock-server zip URL on the download page"
  printf '%s\n' "${url}"
}

resolve_bds_install_request() {
  BDS_INSTALL_MODE="$(bds_install_mode)"
  BDS_REQUESTED_VERSION="$(bds_requested_version "${BDS_INSTALL_MODE}")" \
    || die "Failed to resolve requested BDS version"
  BDS_RESOLVED_URL="$(resolve_bds_download_url)"

  if ! BDS_RESOLVED_VERSION="$(extract_bds_version_from_url "${BDS_RESOLVED_URL}")"; then
    if [[ "${BDS_INSTALL_MODE}" == "custom-url" ]]; then
      BDS_RESOLVED_VERSION="${BDS_REQUESTED_VERSION}"
    else
      die "Failed to resolve BDS version from download URL"
    fi
  fi

  BDS_SOURCE_FINGERPRINT="$(printf '%s' "${BDS_RESOLVED_URL}" | sha256sum | awk '{print $1}')"
  [[ -n "${BDS_SOURCE_FINGERPRINT}" ]] || die "Failed to fingerprint BDS source"
}

current_installed_version() {
  if [[ -f "${DATA_DIR}/.bds-version" ]]; then
    cat "${DATA_DIR}/.bds-version"
  fi
}

validate_bds_install_marker() {
  local marker="$1"
  local field

  jq -e 'type == "object"' "${marker}" >/dev/null 2>&1 \
    || die "Invalid/corrupt BDS install marker: ${marker}"

  for field in schema_version artifact mode requested_version resolved_version source_fingerprint; do
    jq -e --arg field "${field}" \
      'has($field) and .[$field] != null' "${marker}" >/dev/null 2>&1 \
      || die "Incomplete BDS install marker: ${marker} missing ${field}"
  done

  jq -e '.schema_version == 1' "${marker}" >/dev/null 2>&1 \
    || die "Unsupported BDS install marker schema: ${marker}"
  jq -e '.artifact == "bedrock_server"' "${marker}" >/dev/null 2>&1 \
    || die "Invalid BDS install marker artifact: ${marker}"
}

read_bds_install_marker_field() {
  local marker="$1"
  local field="$2"
  validate_bds_install_marker "${marker}"
  jq -er --arg field "${field}" '.[$field] | tostring' "${marker}" \
    || die "Failed to read ${field} from BDS install marker"
}

write_bds_install_marker() {
  local marker tmp
  marker="$(bds_install_marker)"
  tmp="$(mktemp "${DATA_DIR}/.bds-install.json.tmp.XXXXXX")" \
    || die "Failed to create BDS install marker temporary file"

  if ! jq -n \
    --argjson schema_version 1 \
    --arg artifact "bedrock_server" \
    --arg mode "${BDS_INSTALL_MODE}" \
    --arg requested_version "${BDS_REQUESTED_VERSION}" \
    --arg resolved_version "${BDS_RESOLVED_VERSION}" \
    --arg source_fingerprint "${BDS_SOURCE_FINGERPRINT}" \
    '{schema_version:$schema_version,artifact:$artifact,mode:$mode,requested_version:$requested_version,resolved_version:$resolved_version,source_fingerprint:$source_fingerprint}' \
    > "${tmp}"; then
    safe_rm_f "${tmp}" || true
    die "Failed to build BDS install marker"
  fi

  chmod 0644 "${tmp}" || {
    safe_rm_f "${tmp}" || true
    die "Failed to set BDS install marker permissions"
  }
  safe_mv_f "${tmp}" "${marker}" || die "Failed to activate BDS install marker"
}

bds_marker_matches_request() {
  local marker="$1"
  [[ "$(read_bds_install_marker_field "${marker}" mode)" == "${BDS_INSTALL_MODE}" ]] \
    && [[ "$(read_bds_install_marker_field "${marker}" requested_version)" == "${BDS_REQUESTED_VERSION}" ]] \
    && [[ "$(read_bds_install_marker_field "${marker}" resolved_version)" == "${BDS_RESOLVED_VERSION}" ]] \
    && [[ "$(read_bds_install_marker_field "${marker}" source_fingerprint)" == "${BDS_SOURCE_FINGERPRINT}" ]]
}

bds_request_allows_managed_upgrade() {
  local marker="$1"
  local installed_mode
  installed_mode="$(read_bds_install_marker_field "${marker}" mode)"

  [[ "${installed_mode}" == "${BDS_INSTALL_MODE}" ]] || return 1
  case "${BDS_INSTALL_MODE}" in
    latest|stable) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_bds_install_state() {
  local marker legacy_version
  marker="$(bds_install_marker)"

  if [[ -f "${marker}" ]]; then
    validate_bds_install_marker "${marker}"

    if [[ -x "${DATA_DIR}/bedrock_server" ]] && bds_marker_matches_request "${marker}"; then
      log INFO "BDS managed install already matches requested state (version=${BDS_RESOLVED_VERSION})"
      return 1
    fi

    if [[ ! -x "${DATA_DIR}/bedrock_server" ]]; then
      log WARN "BDS install marker exists but bedrock_server is missing; reinstalling managed artifact"
      return 0
    fi

    if bds_request_allows_managed_upgrade "${marker}"; then
      log INFO "Managed ${BDS_INSTALL_MODE} BDS update detected; replacing managed server files"
      return 0
    fi

    if is_true "${FORCE_REINSTALL}"; then
      log WARN "BDS install state differs from requested state; FORCE_REINSTALL=true"
      return 0
    fi

    die "BDS install state differs from requested state. Refusing implicit replacement; set FORCE_REINSTALL=true only for an intentional reinstall"
  fi

  if [[ -x "${DATA_DIR}/bedrock_server" ]]; then
    legacy_version="$(current_installed_version)"

    if [[ -n "${legacy_version}" && "${legacy_version}" == "${BDS_RESOLVED_VERSION}" ]]; then
      log INFO "Adopting legacy .bds-version state into managed install marker"
      write_bds_install_marker
      return 1
    fi

    if [[ "${BDS_INSTALL_MODE}" == "latest" || "${BDS_INSTALL_MODE}" == "stable" ]]; then
      if [[ -n "${legacy_version}" ]]; then
        log WARN "Legacy managed BDS version ${legacy_version} differs from ${BDS_RESOLVED_VERSION}; allowing floating-channel upgrade"
        return 0
      fi
    fi

    if is_true "${FORCE_REINSTALL}"; then
      log WARN "bedrock_server exists without compatible managed metadata; FORCE_REINSTALL=true"
      return 0
    fi

    die "bedrock_server exists without compatible managed install metadata. Refusing replacement; set FORCE_REINSTALL=true only if this installation may be replaced"
  fi

  return 0
}

install_bds() {
  log INFO "Resolving Bedrock Dedicated Server"
  resolve_bds_install_request

  if ! prepare_bds_install_state; then
    return 0
  fi

  local tmp_zip tmp_dir
  log INFO "Downloading BDS: mode=${BDS_INSTALL_MODE}, version=${BDS_RESOLVED_VERSION}"
  tmp_zip="$(mktemp /tmp/bds.XXXXXX.zip)" || die "Failed to create BDS download temporary file"
  tmp_dir="$(mktemp -d /tmp/bds.XXXXXX.dir)" || {
    safe_rm_f "${tmp_zip}" || true
    die "Failed to create BDS extraction directory"
  }

  if ! curl -fL "${BDS_RESOLVED_URL}" -o "${tmp_zip}"; then
    safe_rm_f "${tmp_zip}" || true
    safe_rm_rf "${tmp_dir}" || true
    die "Failed to download BDS zip"
  fi
  if ! unzip -q "${tmp_zip}" -d "${tmp_dir}"; then
    safe_rm_f "${tmp_zip}" || true
    safe_rm_rf "${tmp_dir}" || true
    die "Failed to unzip BDS"
  fi

  [[ -x "${tmp_dir}/bedrock_server" ]] \
    || { safe_rm_f "${tmp_zip}" || true; safe_rm_rf "${tmp_dir}" || true; die "Downloaded archive does not contain an executable bedrock_server"; }

  log INFO "Installing BDS into ${DATA_DIR} (preserving worlds/ and key configs)"
  rsync -a \
    --no-owner \
    --no-group \
    --no-perms \
    --omit-dir-times \
    --exclude 'worlds/' \
    --exclude 'server.properties' \
    --exclude 'allowlist.json' \
    --exclude 'permissions.json' \
    "${tmp_dir}/" "${DATA_DIR}/" \
    || { safe_rm_f "${tmp_zip}" || true; safe_rm_rf "${tmp_dir}" || true; die "Failed to install BDS files"; }

  [[ -f "${DATA_DIR}/server.properties" ]] \
    || cp -a "${tmp_dir}/server.properties" "${DATA_DIR}/server.properties"
  [[ -f "${DATA_DIR}/allowlist.json" ]] \
    || cp -a "${tmp_dir}/allowlist.json" "${DATA_DIR}/allowlist.json" 2>/dev/null \
    || true
  [[ -f "${DATA_DIR}/permissions.json" ]] \
    || cp -a "${tmp_dir}/permissions.json" "${DATA_DIR}/permissions.json" 2>/dev/null \
    || true

  chmod +x "${DATA_DIR}/bedrock_server" || true
  printf '%s\n' "${BDS_RESOLVED_VERSION}" > "${DATA_DIR}/.bds-version"
  write_bds_install_marker

  safe_rm_f "${tmp_zip}" || true
  safe_rm_rf "${tmp_dir}" || true

  log INFO "BDS installed (version=${BDS_RESOLVED_VERSION}, mode=${BDS_INSTALL_MODE})"
}

ldd_check() {
  local bin="${DATA_DIR}/bedrock_server"
  local missing

  [[ -x "${bin}" ]] || die "bedrock_server not found/executable at ${bin}"
  missing="$(ldd "${bin}" 2>/dev/null \
    | awk '/not found/ {print $1}' \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]*$//')"
  if [[ -n "${missing}" ]]; then
    die "Missing shared libraries for bedrock_server: ${missing}"
  fi
}
