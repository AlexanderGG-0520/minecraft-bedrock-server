#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
initialize_config

mkdir -p "${DATA_DIR}/source" "${DATA_DIR}/target"
printf 'managed\n' > "${DATA_DIR}/source/example"
activate_managed_content "${DATA_DIR}/source" "${DATA_DIR}/target" "permission_test" false

content_marker="$(content_state_marker permission_test)"
[[ "$(stat -c '%a' "${content_marker}")" == "644" ]] \
  || { printf 'managed content marker mode is not 0644\n' >&2; exit 1; }

write_world_state_marker "source-fingerprint" "archive-sha256"
world_marker="$(world_state_marker)"
[[ "$(stat -c '%a' "${world_marker}")" == "644" ]] \
  || { printf 'world source marker mode is not 0644\n' >&2; exit 1; }

printf 'managed metadata permissions smoke: ok\n'
