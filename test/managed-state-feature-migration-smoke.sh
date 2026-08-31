#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}/data"
mkdir -p \
  "${DATA_DIR}/.managed/content-assets" \
  "${DATA_DIR}/.managed/player-access" \
  "${DATA_DIR}/.managed/world-packs/Test World"
initialize_config

assert_migrated() {
  local marker="$1"
  local state_type="$2"
  jq -e \
    --arg state_type "${state_type}" '
      .schema_version == 2
      and .state_type == $state_type
    ' "${marker}" >/dev/null \
    || { printf 'marker was not migrated to expected v2 envelope: %s\n' "${marker}" >&2; exit 1; }
  [[ "$(stat -c '%a' "${marker}")" == "644" ]] \
    || { printf 'migrated marker mode is not 0644: %s\n' "${marker}" >&2; exit 1; }
}

bds_marker="$(bds_install_marker)"
cat > "${bds_marker}" <<'JSON'
{"schema_version":1,"artifact":"bedrock_server","mode":"version","requested_version":"1.2.3.4","resolved_version":"1.2.3.4","source_fingerprint":"source-a"}
JSON
chmod 0600 "${bds_marker}"
validate_bds_install_marker "${bds_marker}"
assert_migrated "${bds_marker}" bds-install
jq -e '.artifact == "bedrock_server" and .resolved_version == "1.2.3.4"' "${bds_marker}" >/dev/null \
  || { printf 'BDS migration changed semantic state\n' >&2; exit 1; }

world_marker="$(world_state_marker)"
mkdir -p "$(dirname "${world_marker}")"
cat > "${world_marker}" <<'JSON'
{"schema_version":1,"source_type":"s3","source_fingerprint":"source-world","archive_sha256":"archive-world"}
JSON
chmod 0600 "${world_marker}"
validate_world_state_marker "${world_marker}"
assert_migrated "${world_marker}" world-source
jq -e '.source_type == "s3" and .archive_sha256 == "archive-world"' "${world_marker}" >/dev/null \
  || { printf 'world-source migration changed semantic state\n' >&2; exit 1; }

content_marker="$(content_state_marker behavior_packs)"
cat > "${content_marker}" <<'JSON'
{"schema_version":1,"name":"behavior_packs","managed_entries":["managed_a"]}
JSON
chmod 0600 "${content_marker}"
validate_content_state_marker "${content_marker}"
assert_migrated "${content_marker}" content-assets
jq -e '.name == "behavior_packs" and .managed_entries == ["managed_a"]' "${content_marker}" >/dev/null \
  || { printf 'content migration changed semantic state\n' >&2; exit 1; }

player_marker="$(player_access_state_marker allowlist)"
cat > "${player_marker}" <<'JSON'
{"schema_version":1,"kind":"allowlist","managed_keys":["PlayerA"]}
JSON
chmod 0600 "${player_marker}"
validate_player_access_state_marker "${player_marker}" allowlist
assert_migrated "${player_marker}" player-access
jq -e '.kind == "allowlist" and .managed_keys == ["PlayerA"]' "${player_marker}" >/dev/null \
  || { printf 'player-access migration changed semantic state\n' >&2; exit 1; }

world_pack_marker="$(world_pack_state_marker "Test World" behavior)"
cat > "${world_pack_marker}" <<'JSON'
{"schema_version":1,"level_name":"Test World","kind":"behavior","managed_pack_ids":["11111111-1111-4111-8111-111111111111"]}
JSON
chmod 0600 "${world_pack_marker}"
validate_world_pack_state_marker "${world_pack_marker}" "Test World" behavior
assert_migrated "${world_pack_marker}" world-pack-binding
jq -e '.level_name == "Test World" and .kind == "behavior" and (.managed_pack_ids | length) == 1' \
  "${world_pack_marker}" >/dev/null \
  || { printf 'world-pack migration changed semantic state\n' >&2; exit 1; }

wrong_type="${DATA_DIR}/wrong-type.json"
cat > "${wrong_type}" <<'JSON'
{"schema_version":2,"state_type":"world-source","artifact":"bedrock_server","mode":"version","requested_version":"1.2.3.4","resolved_version":"1.2.3.4","source_fingerprint":"source-a"}
JSON
if (validate_bds_install_marker "${wrong_type}" >/dev/null 2>&1); then
  printf 'v2 marker with the wrong state_type was accepted\n' >&2
  exit 1
fi
jq -e '.schema_version == 2 and .state_type == "world-source"' "${wrong_type}" >/dev/null \
  || { printf 'wrong-type v2 marker was mutated during rejection\n' >&2; exit 1; }

printf 'managed state feature migration smoke: ok\n'
