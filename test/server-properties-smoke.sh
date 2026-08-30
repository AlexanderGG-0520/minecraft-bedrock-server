#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
ENABLE_RCON=false
SERVER_NAME="Refactor Smoke"
GAMEMODE="creative"
BDS_PROPERTIES="difficulty=hard,custom-key=custom-value"
initialize_config

printf 'server-name=Dedicated Server\ngamemode=survival\ndifficulty=easy\n' \
  > "${DATA_DIR}/server.properties"

apply_server_properties_from_env

grep -Fx 'server-name=Refactor Smoke' "${DATA_DIR}/server.properties" >/dev/null
grep -Fx 'gamemode=creative' "${DATA_DIR}/server.properties" >/dev/null
grep -Fx 'difficulty=hard' "${DATA_DIR}/server.properties" >/dev/null
grep -Fx 'custom-key=custom-value' "${DATA_DIR}/server.properties" >/dev/null
grep -Fx 'enable-rcon=false' "${DATA_DIR}/server.properties" >/dev/null

printf 'server properties smoke: ok\n'
