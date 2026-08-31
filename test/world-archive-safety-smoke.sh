#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

python3 - "${tmp_dir}" <<'PY'
import pathlib
import stat
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(root / "safe.zip", "w") as zf:
    zf.writestr("worlds/Test World/level.dat", "ok")
with zipfile.ZipFile(root / "unsafe.zip", "w") as zf:
    zf.writestr("../escape.txt", "bad")
with zipfile.ZipFile(root / "symlink.zip", "w") as zf:
    info = zipfile.ZipInfo("worlds/link")
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    zf.writestr(info, "../../escape")
PY

validate_zip_entries_safe "${tmp_dir}/safe.zip"
if validate_zip_entries_safe "${tmp_dir}/unsafe.zip" >/dev/null 2>&1; then
  printf 'unsafe archive path was accepted\n' >&2
  exit 1
fi
if validate_zip_entries_safe "${tmp_dir}/symlink.zip" >/dev/null 2>&1; then
  printf 'symbolic-link archive entry was accepted\n' >&2
  exit 1
fi

printf 'world archive safety smoke: ok\n'
