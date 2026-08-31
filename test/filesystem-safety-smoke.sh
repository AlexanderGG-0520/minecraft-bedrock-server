#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

if safe_rm_rf "/" 2>/dev/null; then
  printf 'safe_rm_rf accepted root path\n' >&2
  exit 1
fi

src="${tmp_dir}/src"
dst="${tmp_dir}/dst"
mkdir -p "${src}" "${dst}"
printf 'operator\n' > "${dst}/operator.txt"

activate_dir_atomic "${src}" "${dst}" "empty-test" false
[[ -f "${dst}/operator.txt" ]] || {
  printf 'empty input removed existing destination content\n' >&2
  exit 1
}

printf 'managed\n' > "${src}/managed.txt"
activate_dir_atomic "${src}" "${dst}" "merge-test" false
[[ -f "${dst}/operator.txt" && -f "${dst}/managed.txt" ]] || {
  printf 'merge activation did not preserve operator content\n' >&2
  exit 1
}

activate_dir_atomic "${src}" "${dst}" "authoritative-test" true
[[ ! -e "${dst}/operator.txt" && -f "${dst}/managed.txt" ]] || {
  printf 'authoritative activation did not remove extra content\n' >&2
  exit 1
}

printf 'filesystem safety smoke: ok\n'
