# shellcheck shell=bash

# Internal transport policy. These are intentionally not user configuration.
# A transfer that stops making meaningful progress must fail quickly enough for
# another transport to be tried, while a legitimately slow but progressing BDS
# download is not constrained by an arbitrary total wall-clock deadline.
HTTP_DOWNLOAD_ATTEMPTS=2
HTTP_DOWNLOAD_CONNECT_TIMEOUT_SEC=15
HTTP_DOWNLOAD_STALL_LIMIT_BPS=1024
HTTP_DOWNLOAD_STALL_TIME_SEC=60
HTTP_DOWNLOAD_RETRY_DELAY_SEC=2

http_download_prefers_http1() {
  local url="$1"

  case "${url}" in
    https://www.minecraft.net/bedrockdedicatedserver/*|https://minecraft.net/bedrockdedicatedserver/*|https://minecraft.azureedge.net/bin-linux/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

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
      --speed-limit "${HTTP_DOWNLOAD_STALL_LIMIT_BPS}" \
      --speed-time "${HTTP_DOWNLOAD_STALL_TIME_SEC}" \
      "${args[@]}"; then
      return 0
    fi

    if (( attempt < HTTP_DOWNLOAD_ATTEMPTS )); then
      log WARN "HTTP download attempt ${attempt}/${HTTP_DOWNLOAD_ATTEMPTS} failed or stalled; retrying: ${url}"
      sleep "${HTTP_DOWNLOAD_RETRY_DELAY_SEC}"
    fi
  done

  return 1
}

# Keep curl's ordinary behavior for API/stdout calls and non-HTTP sources.
# HTTP(S) downloads written to a file use two progress-bounded transport
# passes. Known official BDS hosts prefer HTTP/1.1 because their HTTP/2 path has
# produced INTERNAL_ERROR/stalled transfers in real compatibility CI. Other
# sources retain curl's default transport first and use HTTP/1.1 as fallback.
curl() {
  local curl_bin="${HTTP_CURL_BIN:-curl}"
  local -a args=("$@")
  local output=""
  local url=""
  local primary_http1=false
  local secondary_http1=true
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

  if http_download_prefers_http1 "${url}"; then
    primary_http1=true
    secondary_http1=false
  fi

  if http_download_with_transport \
    "${curl_bin}" "${output}" "${url}" "${primary_http1}" "${args[@]}"; then
    return 0
  fi

  if [[ "${secondary_http1}" == true ]]; then
    log WARN "HTTP download failed with the default transport; retrying over HTTP/1.1: ${url}"
  else
    log WARN "HTTP/1.1 download failed for official BDS artifact; retrying with curl's default transport: ${url}"
  fi

  http_download_with_transport \
    "${curl_bin}" "${output}" "${url}" "${secondary_http1}" "${args[@]}"
}
