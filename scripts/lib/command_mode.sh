# shellcheck shell=bash

COMMAND_MODE_SHIFT=0

handle_command_mode() {
  COMMAND_MODE_SHIFT=0

  case "${1:-}" in
    rcon)
      shift
      rcon_exec "$@"
      exit $?
      ;;
    rcon-say)
      shift
      rcon_exec "say $*"
      exit $?
      ;;
    rcon-stop)
      rcon_stop_once || true
      exit 0
      ;;
    healthcheck)
      healthcheck
      exit 0
      ;;
    run)
      COMMAND_MODE_SHIFT=1
      ;;
    "")
      ;;
    *)
      exec "$@"
      ;;
  esac
}
