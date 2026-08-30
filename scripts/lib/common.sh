# shellcheck shell=bash

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

validate_port() {
  local name="$1"
  local value="$2"

  [[ -n "${value}" ]] || return 0
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} must be a number (got: ${value})"
  (( value >= 1 && value <= 65535 )) || die "${name} must be 1-65535 (got: ${value})"
}
