# shellcheck shell=bash

mc_configure() {
  [[ -n "${S3_ENDPOINT}" ]] || die "S3_ENDPOINT is required"
  [[ -n "${S3_ACCESS_KEY}" ]] || die "S3_ACCESS_KEY is required"
  [[ -n "${S3_SECRET_KEY}" ]] || die "S3_SECRET_KEY is required"

  mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" >/dev/null \
    || die "Failed to configure MinIO client"
}
