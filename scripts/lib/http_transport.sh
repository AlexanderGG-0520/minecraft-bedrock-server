# shellcheck shell=bash

HTTP_DOWNLOAD_ATTEMPTS="${HTTP_DOWNLOAD_ATTEMPTS:-2}"
HTTP_DOWNLOAD_CONNECT_TIMEOUT_SEC="${HTTP_DOWNLOAD_CONNECT_TIMEOUT_SEC:-15}"
HTTP_DOWNLOAD_MAX_TIME_SEC="${HTTP_DOWNLOAD_MAX_TIME_SEC:-120}"
HTTP_DOWNLOAD_STALL_TIME_SEC="${HTTP_DOWNLOAD_STALL_TIME_SEC:-60}"
HTTP_DOWNLOAD_RETRY_DELAY_SEC="${HTTP_DOWNLOAD_RETRY_DELAY_SEC:-2}"

http_download_with_transport() {
  local curl_bin="$1"
  local output="$2"
  local url="$3"
  local force_http1="$4"
  shift 4
  local -a args=("$@")
  local -a protocol_args=()
  local attempt

  if [[ "${force_http1}" == true ]]; then
    protocol_args+=(--http1.1)
  fi

  for ((attempt = 1; attempt <= HTTP_DOWNLOAD_ATTEMPTS; attempt++)); do
    # Never let a failed/partial transfer contaminate a later retry.
    : > "${output}" || return 1

    if command "${curl_bin}" \
      "${protocol_args[@]}" \
      --connect-timeout "${HTTP_DOWNLOAD_CONNECT_TIMEOUT_SEC}" \
      --max-time "${HTTP_DOWNLOAD_MAX_TIME_SEC}" \
      --speed-limit 1 \
      --speed-time "${HTTP_DOWNLOAD_STALL_TIME_SEC}" \
      "${args[@]}"; then
      return 0
    fi

    if (( attempt < HTTP_DOWNLOAD_ATTEMPTS )); then
      log WARN "HTTP download attempt ${attempt}/${HTTP_DOWNLOAD_ATTEMPTS} failed; retrying: ${url}"
      sleep "${HTTP_DOWNLOAD_RETRY_DELAY_SEC}"
    fi
  done

  return 1
}

# Keep curl's ordinary behavior for API/stdout calls and non-HTTP sources.
# HTTP(S) downloads written to a file use explicit bounded attempts and then a
# second set of bounded attempts over HTTP/1.1. This protects BDS artifact
# installation from transient HTTP/2/CDN failures and from connections that
# stay alive without transferring data.
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

  if http_download_with_transport \
    "${curl_bin}" "${output}" "${url}" false "${args[@]}"; then
    return 0
  fi

  log WARN "HTTP download failed with the default transport; retrying over HTTP/1.1: ${url}"
  http_download_with_transport \
    "${curl_bin}" "${output}" "${url}" true "${args[@]}"
}
