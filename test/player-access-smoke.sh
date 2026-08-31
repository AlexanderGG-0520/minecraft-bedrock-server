#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}"
BDS_ALLOWLIST_JSON='[
  {"name":"ManagedPlayer","ignoresPlayerLimit":true},
  {"name":"NewPlayer"}
]'
BDS_ALLOWLIST_FILE=""
BDS_ALLOWLIST_REMOVE_EXTRA=false
BDS_PERMISSIONS_JSON='[
  {"xuid":"111","permission":"member"},
  {"xuid":"222","permission":"operator"}
]'
BDS_PERMISSIONS_FILE=""
BDS_PERMISSIONS_REMOVE_EXTRA=false
initialize_config

cat > "${DATA_DIR}/allowlist.json" <<'JSON'
[
  {"name":"ManualPlayer","xuid":"999","ignoresPlayerLimit":false},
  {"name":"ManagedPlayer","xuid":"123456789","ignoresPlayerLimit":false}
]
JSON

cat > "${DATA_DIR}/permissions.json" <<'JSON'
[
  {"xuid":"999","permission":"member"},
  {"xuid":"111","permission":"operator"}
]
JSON

manage_player_access

jq -e '
  length == 3
  and (map(select(.name == "ManualPlayer")) | length == 1)
  and (first(.[] | select(.name == "ManagedPlayer")) | .xuid == "123456789" and .ignoresPlayerLimit == true)
  and (first(.[] | select(.name == "NewPlayer")) | .ignoresPlayerLimit == false)
' "${DATA_DIR}/allowlist.json" >/dev/null \
  || { printf 'allowlist merge did not preserve unmanaged/BDS-owned fields\n' >&2; exit 1; }

jq -e '
  .kind == "allowlist"
  and .managed_keys == ["ManagedPlayer","NewPlayer"]
' "$(player_access_state_marker allowlist)" >/dev/null \
  || { printf 'allowlist ownership marker is incorrect\n' >&2; exit 1; }

[[ "$(stat -c '%a' "${DATA_DIR}/allowlist.json")" == "644" ]] \
  || { printf 'allowlist.json mode is not 0644\n' >&2; exit 1; }
[[ "$(stat -c '%a' "$(player_access_state_marker allowlist)")" == "644" ]] \
  || { printf 'allowlist marker mode is not 0644\n' >&2; exit 1; }

jq -e '
  length == 3
  and (first(.[] | select(.xuid == "999")) | .permission == "member")
  and (first(.[] | select(.xuid == "111")) | .permission == "member")
  and (first(.[] | select(.xuid == "222")) | .permission == "operator")
' "${DATA_DIR}/permissions.json" >/dev/null \
  || { printf 'permissions merge did not preserve unmanaged entries or update desired state\n' >&2; exit 1; }

BDS_ALLOWLIST_JSON='[{"name":"NewPlayer","ignoresPlayerLimit":true}]'
BDS_ALLOWLIST_REMOVE_EXTRA=true
BDS_PERMISSIONS_JSON='[{"xuid":"222","permission":"operator"}]'
BDS_PERMISSIONS_REMOVE_EXTRA=true
manage_player_access

jq -e '
  length == 2
  and (map(.name) | index("ManualPlayer") != null)
  and (map(.name) | index("ManagedPlayer") == null)
  and (first(.[] | select(.name == "NewPlayer")) | .ignoresPlayerLimit == true)
' "${DATA_DIR}/allowlist.json" >/dev/null \
  || { printf 'allowlist remove-extra removed unmanaged state or retained stale managed state\n' >&2; exit 1; }

jq -e '
  .managed_keys == ["NewPlayer"]
' "$(player_access_state_marker allowlist)" >/dev/null \
  || { printf 'allowlist ownership marker did not converge after remove-extra\n' >&2; exit 1; }

jq -e '
  length == 2
  and (map(.xuid) | index("999") != null)
  and (map(.xuid) | index("111") == null)
  and (map(.xuid) | index("222") != null)
' "${DATA_DIR}/permissions.json" >/dev/null \
  || { printf 'permissions remove-extra removed unmanaged state or retained stale managed state\n' >&2; exit 1; }

if (
  BDS_ALLOWLIST_JSON='[{"name":"Duplicate"},{"name":"Duplicate"}]'
  BDS_ALLOWLIST_REMOVE_EXTRA=false
  manage_allowlist >/dev/null 2>&1
); then
  printf 'duplicate managed allowlist names were accepted\n' >&2
  exit 1
fi

if (
  BDS_PERMISSIONS_JSON='[{"xuid":"123","permission":"owner"}]'
  BDS_PERMISSIONS_REMOVE_EXTRA=false
  manage_permissions >/dev/null 2>&1
); then
  printf 'invalid managed permission level was accepted\n' >&2
  exit 1
fi

printf 'player access smoke: ok\n'
