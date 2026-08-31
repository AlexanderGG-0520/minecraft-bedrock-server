#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}/data"
src="${tmp_dir}/input"
dst="${DATA_DIR}/behavior_packs"
mkdir -p "${src}" "${dst}/operator-pack"
printf 'keep\n' > "${dst}/operator-pack/value.txt"

mkdir -p "${src}/managed-a"
printf 'v1\n' > "${src}/managed-a/value.txt"
activate_managed_content "${src}" "${dst}" behavior_packs false

[[ -f "${dst}/operator-pack/value.txt" ]] || {
  printf 'unowned operator pack was removed\n' >&2
  exit 1
}
[[ "$(cat "${dst}/managed-a/value.txt")" == "v1" ]] || {
  printf 'managed-a was not activated\n' >&2
  exit 1
}

rm -rf -- "${src}/managed-a"
mkdir -p "${src}/managed-b"
printf 'v2\n' > "${src}/managed-b/value.txt"
activate_managed_content "${src}" "${dst}" behavior_packs false

[[ -f "${dst}/managed-a/value.txt" ]] || {
  printf 'managed-a should remain when remove_extra=false\n' >&2
  exit 1
}
[[ -f "${dst}/managed-b/value.txt" ]] || {
  printf 'managed-b was not activated\n' >&2
  exit 1
}

activate_managed_content "${src}" "${dst}" behavior_packs true

[[ ! -e "${dst}/managed-a" ]] || {
  printf 'stale managed-a was not removed when remove_extra=true\n' >&2
  exit 1
}
[[ -f "${dst}/managed-b/value.txt" ]] || {
  printf 'managed-b disappeared during authoritative activation\n' >&2
  exit 1
}
[[ -f "${dst}/operator-pack/value.txt" ]] || {
  printf 'unowned operator pack was removed by remove_extra=true\n' >&2
  exit 1
}

marker="$(content_state_marker behavior_packs)"
[[ "$(jq -r '.managed_entries | join(",")' "${marker}")" == "managed-b" ]] || {
  printf 'managed content marker does not reflect current ownership\n' >&2
  exit 1
}

rm -rf -- "${src}"/*
activate_managed_content "${src}" "${dst}" behavior_packs true
[[ -f "${dst}/managed-b/value.txt" && -f "${dst}/operator-pack/value.txt" ]] || {
  printf 'empty input changed active content\n' >&2
  exit 1
}

printf 'content ownership smoke: ok\n'
