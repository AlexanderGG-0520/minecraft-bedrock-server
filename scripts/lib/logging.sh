# shellcheck shell=bash

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="$1"
  shift || true
  printf '[%s] [%s] %s\n' "$(ts)" "${level}" "$*" >&2
}

die() {
  log ERROR "$*"
  exit 1
}
