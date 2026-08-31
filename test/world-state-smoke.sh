#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}/data"
WORLD_S3_BUCKET="worlds"
WORLD_S3_KEY="prod/world.zip"
mkdir -p "${DATA_DIR}/worlds/Test World"
printf 'world\n' > "${DATA_DIR}/worlds/Test World/level.dat"

source_a="$(world_source_fingerprint)"
write_world_state_marker "${source_a}" "archive-sha-a"
marker="$(world_state_marker)"
validate_world_state_marker "${marker}"

[[ "$(jq -r '.source_fingerprint' "${marker}")" == "${source_a}" ]] || {
  printf 'world source fingerprint was not persisted\n' >&2
  exit 1
}

WORLD_S3_KEY="prod/world-v2.zip"
source_b="$(world_source_fingerprint)"
[[ "${source_a}" != "${source_b}" ]] || {
  printf 'world source fingerprint did not change with source identity\n' >&2
  exit 1
}

log_world_source_drift_if_managed

printf '{"schema_version":1,"source_type":"s3"}\n' > "${marker}"
if (validate_world_state_marker "${marker}" >/dev/null 2>&1); then
  printf 'incomplete world source marker was accepted\n' >&2
  exit 1
fi

printf 'world state smoke: ok\n'
