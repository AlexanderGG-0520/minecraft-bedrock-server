#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

fake_curl="${tmp_dir}/fake-curl"
log_file="${tmp_dir}/calls.log"
output_file="${tmp_dir}/payload.zip"

cat > "${fake_curl}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >> "${HTTP_TEST_LOG}"

output=""
http1=false
for ((i = 1; i <= $#; i++)); do
  arg="${!i}"
  case "${arg}" in
    --http1.1)
      http1=true
      ;;
    -o|--output)
      next=$((i + 1))
      output="${!next}"
      ;;
    --output=*)
      output="${arg#--output=}"
      ;;
    -o?*)
      output="${arg#-o}"
      ;;
  esac
done

[[ -n "${output}" ]] || exit 2

if [[ "${http1}" == true ]]; then
  # Append deliberately: the wrapper must truncate a previous partial payload
  # before switching transports or this assertion will expose contamination.
  printf 'complete-payload\n' >> "${output}"
  exit 0
fi

printf 'partial-payload\n' >> "${output}"
exit 92
EOF
chmod +x "${fake_curl}"

HTTP_CURL_BIN="${fake_curl}"
HTTP_TEST_LOG="${log_file}"
HTTP_DOWNLOAD_RETRY_DELAY_SEC=0
export HTTP_CURL_BIN HTTP_TEST_LOG

curl -fL 'https://example.invalid/bedrock-server.zip' -o "${output_file}"

[[ "$(cat "${output_file}")" == 'complete-payload' ]] || {
  printf 'HTTP/1.1 fallback did not replace partial download state\n' >&2
  cat "${output_file}" >&2 || true
  exit 1
}
[[ "$(wc -l < "${log_file}")" == "3" ]] || {
  printf 'expected two primary attempts and one successful HTTP/1.1 fallback\n' >&2
  cat "${log_file}" >&2
  exit 1
}

head -n2 "${log_file}" | grep -q -- '--http1.1' && {
  printf 'primary attempts unexpectedly forced HTTP/1.1\n' >&2
  exit 1
}
tail -n1 "${log_file}" | grep -q -- '--http1.1' || {
  printf 'fallback attempt did not force HTTP/1.1\n' >&2
  exit 1
}

while IFS= read -r call; do
  grep -q -- '--connect-timeout 15' <<<"${call}" || {
    printf 'HTTP attempt is missing the connect timeout\n' >&2
    exit 1
  }
  grep -q -- '--max-time 120' <<<"${call}" || {
    printf 'HTTP attempt is missing the hard transfer timeout\n' >&2
    exit 1
  }
  grep -q -- '--speed-limit 1' <<<"${call}" || {
    printf 'HTTP attempt is missing the stalled-transfer speed limit\n' >&2
    exit 1
  }
  grep -q -- '--speed-time 60' <<<"${call}" || {
    printf 'HTTP attempt is missing the stalled-transfer timeout\n' >&2
    exit 1
  }
done < "${log_file}"

: > "${log_file}"
if curl -fL 'file:///fixture/missing.zip' -o "${output_file}" >/dev/null 2>&1; then
  printf 'non-HTTP fixture unexpectedly succeeded\n' >&2
  exit 1
fi
[[ "$(wc -l < "${log_file}")" == "1" ]] || {
  printf 'non-HTTP curl call was retried or transport-fallback wrapped\n' >&2
  cat "${log_file}" >&2
  exit 1
}
if grep -q -- '--connect-timeout\|--max-time\|--speed-limit\|--speed-time\|--http1.1' "${log_file}"; then
  printf 'non-HTTP curl call received HTTP transport controls\n' >&2
  cat "${log_file}" >&2
  exit 1
fi

printf 'http transport smoke: ok\n'
