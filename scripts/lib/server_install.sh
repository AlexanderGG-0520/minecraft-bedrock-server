# shellcheck shell=bash

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

current_installed_version() {
  if [[ -f "${DATA_DIR}/.bds-version" ]]; then
    cat "${DATA_DIR}/.bds-version"
  fi
}

install_bds() {
  log INFO "Resolving Bedrock Dedicated Server (VERSION=${VERSION})"

  local url want_version installed_version
  local tmp_zip tmp_dir
  url="$(resolve_bds_download_url)"

  want_version="${VERSION}"
  if [[ "${VERSION}" == "latest" ]]; then
    want_version="$(basename "${url}" \
      | sed -E 's/^bedrock-server-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.zip$/\1/')"
  fi

  installed_version="$(current_installed_version)"
  if [[ -x "${DATA_DIR}/bedrock_server" \
    && -n "${installed_version}" \
    && "${installed_version}" == "${want_version}" ]]; then
    log INFO "BDS already installed (version=${installed_version}), skipping"
    return 0
  fi

  log INFO "Downloading BDS: ${url}"
  tmp_zip="$(mktemp /tmp/bds.XXXXXX.zip)"
  tmp_dir="$(mktemp -d /tmp/bds.XXXXXX.dir)"
  rm -rf -- "${tmp_dir}"
  mkdir -p "${tmp_dir}"

  curl -fL "${url}" -o "${tmp_zip}" || die "Failed to download BDS zip"
  unzip -q "${tmp_zip}" -d "${tmp_dir}" || die "Failed to unzip BDS"

  log INFO "Installing BDS into ${DATA_DIR} (preserving worlds/ and key configs)"
  rsync -a \
    --exclude 'worlds/' \
    --exclude 'server.properties' \
    --exclude 'allowlist.json' \
    --exclude 'permissions.json' \
    "${tmp_dir}/" "${DATA_DIR}/"

  [[ -f "${DATA_DIR}/server.properties" ]] \
    || cp -a "${tmp_dir}/server.properties" "${DATA_DIR}/server.properties"
  [[ -f "${DATA_DIR}/allowlist.json" ]] \
    || cp -a "${tmp_dir}/allowlist.json" "${DATA_DIR}/allowlist.json" 2>/dev/null \
    || true
  [[ -f "${DATA_DIR}/permissions.json" ]] \
    || cp -a "${tmp_dir}/permissions.json" "${DATA_DIR}/permissions.json" 2>/dev/null \
    || true

  chmod +x "${DATA_DIR}/bedrock_server" || true
  printf '%s\n' "${want_version}" > "${DATA_DIR}/.bds-version"

  rm -f -- "${tmp_zip}"
  rm -rf -- "${tmp_dir}"

  log INFO "BDS installed (version=${want_version})"
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
