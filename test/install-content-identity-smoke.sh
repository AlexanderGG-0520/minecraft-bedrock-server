#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

DATA_DIR="${tmp_dir}/data"
mkdir -p "${DATA_DIR}"
initialize_config

python3 - "${tmp_dir}" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
fixed_time = (2026, 1, 1, 0, 0, 0)


def add_file(zf, name, content, mode=0o100644):
    info = zipfile.ZipInfo(name, fixed_time)
    info.create_system = 3
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, content)


for version, sentinel in (("1.0.0.1", b"artifact-a\n"), ("1.0.0.2", b"artifact-b\n")):
    archive = root / f"bedrock-server-{version}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        add_file(zf, "bedrock_server", b"#!/bin/sh\nexit 0\n", 0o100755)
        add_file(zf, "server.properties", b"server-name=identity-smoke\n")
        add_file(zf, "allowlist.json", b"[]\n")
        add_file(zf, "permissions.json", b"[]\n")
        add_file(zf, "fixture-version.txt", sentinel)
PY

VERSION="1.0.0.1"
BDS_DOWNLOAD_URL="file://${tmp_dir}/bedrock-server-1.0.0.1.zip"
FORCE_REINSTALL=false
install_bds >/dev/null

sentinel="${DATA_DIR}/fixture-version.txt"
[[ "$(cat "${sentinel}")" == "artifact-a" ]] || {
  printf 'initial BDS payload sentinel is incorrect\n' >&2
  exit 1
}

initial_size="$(stat -c '%s' "${sentinel}")"
initial_mtime="$(stat -c '%Y' "${sentinel}")"

VERSION="1.0.0.2"
BDS_DOWNLOAD_URL="file://${tmp_dir}/bedrock-server-1.0.0.2.zip"
FORCE_REINSTALL=true
install_bds >/dev/null

[[ "$(stat -c '%s' "${sentinel}")" == "${initial_size}" ]] || {
  printf 'replacement fixture no longer reproduces equal-size metadata\n' >&2
  exit 1
}
[[ "$(stat -c '%Y' "${sentinel}")" == "${initial_mtime}" ]] || {
  printf 'replacement fixture no longer reproduces equal-mtime metadata\n' >&2
  exit 1
}
[[ "$(cat "${sentinel}")" == "artifact-b" ]] || {
  printf 'BDS replacement retained stale content when size and mtime matched\n' >&2
  exit 1
}

[[ "$(jq -r '.resolved_version' "${DATA_DIR}/.bds-install.json")" == "1.0.0.2" ]] || {
  printf 'managed install marker did not advance with replacement content\n' >&2
  exit 1
}

printf 'install content identity smoke: ok\n'
