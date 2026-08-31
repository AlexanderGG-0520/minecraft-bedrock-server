#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
initialize_config

version="1.26.0.2"
current_url="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-${version}.zip"
legacy_url="https://minecraft.azureedge.net/bin-linux/bedrock-server-${version}.zip"

[[ "$(official_bds_url_for_version "${version}")" == "${current_url}" ]] || {
  printf 'official version URL does not use the current minecraft.net endpoint\n' >&2
  exit 1
}

services_payload="$(jq -nc \
  --arg linux "${current_url}" \
  '{result:{links:[
    {downloadType:"serverBedrockWindows",downloadUrl:"https://example.invalid/windows.zip"},
    {downloadType:"serverBedrockLinux",downloadUrl:$linux}
  ]}}')"
[[ "$(extract_official_bds_url_from_links_json "${services_payload}")" == "${current_url}" ]] || {
  printf 'Minecraft Services Linux BDS URL was not detected\n' >&2
  exit 1
}
if extract_official_bds_url_from_links_json '{"result":{"links":[]}}' >/dev/null 2>&1; then
  printf 'Minecraft Services parser accepted a payload without serverBedrockLinux\n' >&2
  exit 1
fi

curl() {
  printf '%s' "${services_payload}"
}
[[ "$(resolve_latest_bds_url_from_services)" == "${current_url}" ]] || {
  printf 'latest BDS resolution did not use Minecraft Services response\n' >&2
  exit 1
}
unset -f curl

current_page="<a href=\"${current_url}\">Linux</a>"
[[ "$(extract_official_bds_url_from_page "${current_page}")" == "${current_url}" ]] || {
  printf 'current official download-page URL was not detected\n' >&2
  exit 1
}

legacy_page="<a href=\"${legacy_url}\">Linux</a>"
[[ "$(extract_official_bds_url_from_page "${legacy_page}")" == "${legacy_url}" ]] || {
  printf 'legacy AzureEdge download-page URL fallback was not detected\n' >&2
  exit 1
}

[[ "$(extract_bds_version_from_url "${current_url}?source=test")" == "${version}" ]] || {
  printf 'version extraction failed for current official URL\n' >&2
  exit 1
}

BDS_DOWNLOAD_URL=""
BDS_CHANNEL=latest
VERSION="${version}"
[[ "$(resolve_bds_download_url)" == "${current_url}" ]] || {
  printf 'explicit VERSION did not resolve to the current official endpoint\n' >&2
  exit 1
}

BDS_CHANNEL=stable
BDS_STABLE_VERSION="${version}"
[[ "$(resolve_bds_download_url)" == "${current_url}" ]] || {
  printf 'stable channel did not resolve to the current official endpoint\n' >&2
  exit 1
}

# Latest resolution falls back to the official download page when the
# Minecraft Services endpoint is unavailable.
BDS_CHANNEL=latest
BDS_STABLE_VERSION=""
VERSION=latest
curl() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      https://net.web.minecraft-services.net/*)
        return 22
        ;;
      https://www.minecraft.net/en-us/download/server/bedrock)
        printf '%s' "${current_page}"
        return 0
        ;;
    esac
  done
  return 22
}
[[ "$(resolve_bds_download_url)" == "${current_url}" ]] || {
  printf 'latest BDS resolution did not fall back to the official download page\n' >&2
  exit 1
}
unset -f curl

# An official CDN/URL move must not make an unchanged artifact incompatible.
touch "${DATA_DIR}/bedrock_server"
chmod +x "${DATA_DIR}/bedrock_server"
printf '%s\n' "${version}" > "${DATA_DIR}/.bds-version"

BDS_INSTALL_MODE="version"
BDS_REQUESTED_VERSION="${version}"
BDS_RESOLVED_VERSION="${version}"
BDS_RESOLVED_URL="${legacy_url}"
BDS_SOURCE_FINGERPRINT="$(printf '%s' "${legacy_url}" | sha256sum | awk '{print $1}')"
write_bds_install_marker
legacy_fingerprint="${BDS_SOURCE_FINGERPRINT}"

BDS_RESOLVED_URL="${current_url}"
BDS_SOURCE_FINGERPRINT="$(printf '%s' "${current_url}" | sha256sum | awk '{print $1}')"
current_fingerprint="${BDS_SOURCE_FINGERPRINT}"

if prepare_bds_install_state; then
  printf 'official URL migration unexpectedly requested payload reinstall\n' >&2
  exit 1
fi

[[ "$(read_bds_install_marker_field "$(bds_install_marker)" source_fingerprint)" == "${current_fingerprint}" ]] || {
  printf 'official URL migration did not refresh managed source metadata\n' >&2
  exit 1
}
[[ "${legacy_fingerprint}" != "${current_fingerprint}" ]] || {
  printf 'source migration fixture fingerprints unexpectedly match\n' >&2
  exit 1
}

# A custom URL remains source-strict even when the claimed version is unchanged.
BDS_INSTALL_MODE="custom-url"
BDS_REQUESTED_VERSION="${version}"
BDS_RESOLVED_VERSION="${version}"
BDS_RESOLVED_URL="https://example.invalid/a/bedrock-server-${version}.zip"
BDS_SOURCE_FINGERPRINT="$(printf '%s' "${BDS_RESOLVED_URL}" | sha256sum | awk '{print $1}')"
write_bds_install_marker

BDS_RESOLVED_URL="https://example.invalid/b/bedrock-server-${version}.zip"
BDS_SOURCE_FINGERPRINT="$(printf '%s' "${BDS_RESOLVED_URL}" | sha256sum | awk '{print $1}')"
if (prepare_bds_install_state >/dev/null 2>&1); then
  printf 'custom URL source mismatch was not rejected\n' >&2
  exit 1
fi

printf 'BDS source resolution smoke: ok\n'
