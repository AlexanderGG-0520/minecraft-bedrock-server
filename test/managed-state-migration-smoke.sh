#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

validate_fixture_state() {
  local marker="$1"
  jq -e '
    .schema_version == 2
    and .state_type == "fixture"
    and .value == "expected"
  ' "${marker}" >/dev/null 2>&1
}

marker="${tmp_dir}/state.json"
printf '%s\n' '{"schema_version":1,"value":"expected"}' > "${marker}"
chmod 0600 "${marker}"
managed_state_ensure_current \
  "${marker}" \
  fixture \
  validate_fixture_state \
  managed_state_migrate_envelope \
  'fixture marker'

jq -e '.schema_version == 2 and .state_type == "fixture" and .value == "expected"' \
  "${marker}" >/dev/null \
  || { printf 'v1 fixture marker was not migrated to v2\n' >&2; exit 1; }
[[ "$(stat -c '%a' "${marker}")" == "644" ]] \
  || { printf 'migrated fixture marker permissions are not 0644\n' >&2; exit 1; }

future="${tmp_dir}/future.json"
printf '%s\n' '{"schema_version":3,"state_type":"fixture","value":"expected"}' > "${future}"
if (managed_state_ensure_current \
  "${future}" fixture validate_fixture_state managed_state_migrate_envelope 'fixture marker' \
  >/dev/null 2>&1); then
  printf 'future fixture schema was not rejected\n' >&2
  exit 1
fi
jq -e '.schema_version == 3 and .state_type == "fixture"' "${future}" >/dev/null \
  || { printf 'future fixture marker was mutated during rejection\n' >&2; exit 1; }

invalid="${tmp_dir}/invalid.json"
printf '%s\n' '{"schema_version":1,"value":"wrong"}' > "${invalid}"
if (managed_state_ensure_current \
  "${invalid}" fixture validate_fixture_state managed_state_migrate_envelope 'fixture marker' \
  >/dev/null 2>&1); then
  printf 'semantically invalid migrated fixture was accepted\n' >&2
  exit 1
fi
jq -e '.schema_version == 1 and (has("state_type") | not) and .value == "wrong"' \
  "${invalid}" >/dev/null \
  || { printf 'invalid v1 fixture was mutated after failed migration\n' >&2; exit 1; }

missing_path="${tmp_dir}/missing.json"
managed_state_ensure_current \
  "${missing_path}" fixture validate_fixture_state managed_state_migrate_envelope 'fixture marker'
[[ ! -e "${missing_path}" ]] || {
  printf 'missing marker was unexpectedly created by migration framework\n' >&2
  exit 1
}

printf 'managed state migration smoke: ok\n'
