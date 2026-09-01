# shellcheck shell=bash

# Keep curl's ordinary behavior for API/stdout calls and non-HTTP sources.
# HTTP(S) downloads written to a file get bounded transport retries and a
# second pass forced to HTTP/1.1. This protects BDS artifact installation from
# transient HTTP/2/CDN failures without changing source-resolution semantics.
curl() {
  local curl_bin="${HTTP_CURL_BIN:-curl}"
  local -a args=("$@")
  local output=""
  local url=""
  local i arg

  for ((i = 0; i < ${#args[@]}; i++)); do
    arg="${args[i]}"
    case "${arg}" in
      -o|--output)
        if (( i + 1 < ${#args[@]} )); then
          output="${args[i + 1]}"
        fi
        ;;
      --output=*)
        output="${arg#--output=}"
        ;;
      -o?*)
        output="${arg#-o}"
        ;;
      http://*|https://*)
        url="${arg}"
        ;;
    esac
  done

  if [[ -z "${output}" || "${output}" == "-" || -z "${url}" ]]; then
    command "${curl_bin}" "${args[@]}"
    return
  fi

  : > "${output}" || return 1
  if command "${curl_bin}" \
    --retry 4 \
    --retry-delay 2 \
    --retry-all-errors \
    "${args[@]}"; then
    return 0
  fi

  log WARN "HTTP download failed after retries; retrying over HTTP/1.1: ${url}"
  : > "${output}" || return 1
  command "${curl_bin}" \
    --http1.1 \
    --retry 4 \
    --retry-delay 2 \
    --retry-all-errors \
    "${args[@]}"
}
