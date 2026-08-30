# shellcheck shell=bash

install_world_zip_from_s3() {
  [[ -n "${WORLD_S3_BUCKET}" && -n "${WORLD_S3_KEY}" ]] || {
    log INFO "WORLD_S3_BUCKET/KEY not set, skipping world import"
    return 0
  }

  if is_true "${WORLD_INSTALL_ONCE}"; then
    if find "${DATA_DIR}/worlds" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
      log INFO "Worlds already exist, skipping world import (WORLD_INSTALL_ONCE=true)"
      return 0
    fi
  fi

  mc_configure
  local tmp_zip="/tmp/worlds.zip"
  local tmp_dir="/tmp/worlds.extract.$$"

  rm -f -- "${tmp_zip}" || true
  rm -rf -- "${tmp_dir}" || true
  mkdir -p "${tmp_dir}"

  log INFO "Downloading worlds zip from s3://${WORLD_S3_BUCKET}/${WORLD_S3_KEY}"
  mc cp "s3/${WORLD_S3_BUCKET}/${WORLD_S3_KEY}" "${tmp_zip}" \
    || die "Failed to download worlds zip"

  log INFO "Extracting worlds zip"
  unzip -q "${tmp_zip}" -d "${tmp_dir}" || die "Failed to unzip worlds archive"

  if [[ -d "${tmp_dir}/worlds" ]]; then
    rsync -a --delete "${tmp_dir}/worlds/" "${DATA_DIR}/worlds/"
  else
    rsync -a --delete "${tmp_dir}/" "${DATA_DIR}/worlds/"
  fi

  rm -f -- "${tmp_zip}"
  rm -rf -- "${tmp_dir}"
}
