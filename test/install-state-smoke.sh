#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
FORCE_REINSTALL=false
initialize_config

touch "${DATA_DIR}/bedrock_server"
chmod +x "${DATA_DIR}/bedrock_server"
printf '1.21.130.4\n' > "${DATA_DIR}/.bds-version"

BDS_INSTALL_MODE="version"
BDS_REQUESTED_VERSION="1.21.130.4"
BDS_RESOLVED_VERSION="1.21.130.4"
BDS_RESOLVED_URL="https://example.invalid/bedrock-server-1.21.130.4.zip"
BDS_SOURCE_FINGERPRINT="fingerprint-a"
write_bds_install_marker

[[ "$(stat -c '%a' "$(bds_install_marker)")" == "644" ]] || {
  printf 'managed install marker permissions are not 0644\n' >&2
  exit 1
}

if prepare_bds_install_state; then
  printf 'matching managed install unexpectedly requested reinstall\n' >&2
  exit 1
fi

BDS_REQUESTED_VERSION="1.21.140.1"
BDS_RESOLVED_VERSION="1.21.140.1"
BDS_SOURCE_FINGERPRINT="fingerprint-b"
if (prepare_bds_install_state >/dev/null 2>&1); then
  printf 'pinned managed install mismatch was not rejected\n' >&2
  exit 1
fi

FORCE_REINSTALL=true
prepare_bds_install_state
FORCE_REINSTALL=false

safe_rm_f "$(bds_install_marker)"
BDS_REQUESTED_VERSION="1.21.130.4"
BDS_RESOLVED_VERSION="1.21.130.4"
BDS_SOURCE_FINGERPRINT="fingerprint-a"

if prepare_bds_install_state; then
  printf 'matching legacy install unexpectedly requested reinstall\n' >&2
  exit 1
fi
[[ -f "$(bds_install_marker)" ]] || {
  printf 'legacy state was not adopted into managed marker\n' >&2
  exit 1
}

printf 'install state smoke: ok\n'
