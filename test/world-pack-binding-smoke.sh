#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
WORLD_PACKS_BINDING_ENABLED=true
WORLD_PACKS_REMOVE_EXTRA=false
WORLD_PACKS_LEVEL_NAME=""
initialize_config

mkdir -p \
  "${DATA_DIR}/worlds/Test World" \
  "${DATA_DIR}/behavior_packs/managed_bp" \
  "${DATA_DIR}/resource_packs/managed_rp" \
  "${DATA_DIR}/.managed/content-assets"

printf 'level-name=Test World\n' > "${DATA_DIR}/server.properties"

cat > "${DATA_DIR}/behavior_packs/managed_bp/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Managed BP",
    "description": "test",
    "uuid": "11111111-1111-4111-8111-111111111111",
    "version": [1, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "data",
      "uuid": "11111111-1111-4111-8111-111111111112",
      "version": [1, 0, 0]
    }
  ]
}
JSON

cat > "${DATA_DIR}/resource_packs/managed_rp/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Managed RP",
    "description": "test",
    "uuid": "22222222-2222-4222-8222-222222222222",
    "version": [2, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "resources",
      "uuid": "22222222-2222-4222-8222-222222222223",
      "version": [2, 0, 0]
    }
  ]
}
JSON

cat > "${DATA_DIR}/.managed/content-assets/behavior_packs.json" <<'JSON'
{"schema_version":1,"name":"behavior_packs","managed_entries":["managed_bp"]}
JSON
cat > "${DATA_DIR}/.managed/content-assets/resource_packs.json" <<'JSON'
{"schema_version":1,"name":"resource_packs","managed_entries":["managed_rp"]}
JSON

cat > "${DATA_DIR}/worlds/Test World/world_behavior_packs.json" <<'JSON'
[
  {"pack_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":[9,9,9]}
]
JSON
cat > "${DATA_DIR}/worlds/Test World/world_resource_packs.json" <<'JSON'
[
  {"pack_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","version":[9,9,9]}
]
JSON

bind_managed_world_packs

jq -e '
  length == 2
  and (map(.pack_id) | index("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") != null)
  and (first(.[] | select(.pack_id == "11111111-1111-4111-8111-111111111111")) | .version == [1,0,0])
' "${DATA_DIR}/worlds/Test World/world_behavior_packs.json" >/dev/null \
  || { printf 'behavior pack binding did not preserve unmanaged state and add managed pack\n' >&2; exit 1; }

jq -e '
  length == 2
  and (map(.pack_id) | index("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb") != null)
  and (first(.[] | select(.pack_id == "22222222-2222-4222-8222-222222222222")) | .version == [2,0,0])
' "${DATA_DIR}/worlds/Test World/world_resource_packs.json" >/dev/null \
  || { printf 'resource pack binding did not preserve unmanaged state and add managed pack\n' >&2; exit 1; }

jq -e '
  .level_name == "Test World"
  and .kind == "behavior"
  and .managed_pack_ids == ["11111111-1111-4111-8111-111111111111"]
' "$(world_pack_state_marker "Test World" behavior)" >/dev/null \
  || { printf 'behavior world-pack ownership marker is incorrect\n' >&2; exit 1; }

jq '.header.version = [1,2,0]' \
  "${DATA_DIR}/behavior_packs/managed_bp/manifest.json" \
  > "${DATA_DIR}/behavior_packs/managed_bp/manifest.json.tmp"
mv "${DATA_DIR}/behavior_packs/managed_bp/manifest.json.tmp" \
  "${DATA_DIR}/behavior_packs/managed_bp/manifest.json"
bind_managed_world_packs

jq -e '
  first(.[] | select(.pack_id == "11111111-1111-4111-8111-111111111111"))
  | .version == [1,2,0]
' "${DATA_DIR}/worlds/Test World/world_behavior_packs.json" >/dev/null \
  || { printf 'managed behavior pack version did not follow manifest update\n' >&2; exit 1; }

cat > "${DATA_DIR}/.managed/content-assets/behavior_packs.json" <<'JSON'
{"schema_version":1,"name":"behavior_packs","managed_entries":[]}
JSON
WORLD_PACKS_REMOVE_EXTRA=true
bind_managed_world_packs

jq -e '
  length == 1
  and .[0].pack_id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
' "${DATA_DIR}/worlds/Test World/world_behavior_packs.json" >/dev/null \
  || { printf 'remove-extra did not remove only the stale managed behavior binding\n' >&2; exit 1; }

jq -e '
  length == 2
  and (map(.pack_id) | index("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb") != null)
  and (map(.pack_id) | index("22222222-2222-4222-8222-222222222222") != null)
' "${DATA_DIR}/worlds/Test World/world_resource_packs.json" >/dev/null \
  || { printf 'remove-extra removed an unmanaged or still-managed resource binding\n' >&2; exit 1; }

mkdir -p "${DATA_DIR}/behavior_packs/duplicate_a" "${DATA_DIR}/behavior_packs/duplicate_b"
cp "${DATA_DIR}/behavior_packs/managed_bp/manifest.json" \
  "${DATA_DIR}/behavior_packs/duplicate_a/manifest.json"
cp "${DATA_DIR}/behavior_packs/managed_bp/manifest.json" \
  "${DATA_DIR}/behavior_packs/duplicate_b/manifest.json"
cat > "${DATA_DIR}/.managed/content-assets/behavior_packs.json" <<'JSON'
{"schema_version":1,"name":"behavior_packs","managed_entries":["duplicate_a","duplicate_b"]}
JSON

if (bind_managed_world_packs >/dev/null 2>&1); then
  printf 'duplicate managed pack UUIDs were accepted\n' >&2
  exit 1
fi

printf 'world pack binding smoke: ok\n'
