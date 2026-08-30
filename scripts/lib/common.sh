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

validate_nonnegative_int() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} must be a non-negative integer (got: ${value})"
}

validate_boolean() {
  local name="$1"
  local value="${2,,}"
  case "${value}" in
    1|0|true|false|yes|no|y|n|on|off) return 0 ;;
    *) die "${name} must be a boolean value (got: ${2})" ;;
  esac
}
