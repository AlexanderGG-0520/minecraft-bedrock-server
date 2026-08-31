#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:-minecraft-bedrock-server:ci-real-bds}"
requested_version="${2:-latest}"
server_port="${REAL_BDS_SERVER_PORT:-19132}"
server_port_v6="${REAL_BDS_SERVER_PORT_V6:-19133}"
level_name="${REAL_BDS_LEVEL_NAME:-CI Compatibility World}"
ready_timeout="${REAL_BDS_READY_TIMEOUT:-180}"
health_timeout="${REAL_BDS_HEALTH_TIMEOUT:-120}"
stop_timeout="${REAL_BDS_STOP_TIMEOUT:-60}"

suffix="${GITHUB_RUN_ID:-local}-$$-${RANDOM}"
volume="minecraft-bedrock-real-bds-${suffix}"
container=""
container_prefix="minecraft-bedrock-real-bds-${suffix}"
resolved_version=""
resolved_mode=""

cleanup() {
  local status=$?

  if [[ -n "${container}" ]] && docker inspect "${container}" >/dev/null 2>&1; then
    if (( status != 0 )); then
      printf '%s\n' '--- real BDS container logs (failure) ---' >&2
      docker logs "${container}" >&2 2>&1 || true
    fi
    docker rm -f "${container}" >/dev/null 2>&1 || true
  fi

  docker volume rm -f "${volume}" >/dev/null 2>&1 || true
  return "${status}"
}
trap cleanup EXIT

validate_positive_int() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || {
    printf '%s must be a positive integer (got: %s)\n' "${name}" "${value}" >&2
    exit 2
  }
}

validate_port() {
  local name="$1"
  local value="$2"
  validate_positive_int "${name}" "${value}"
  (( value <= 65535 )) || {
    printf '%s must be <= 65535 (got: %s)\n' "${name}" "${value}" >&2
    exit 2
  }
}

validate_positive_int REAL_BDS_READY_TIMEOUT "${ready_timeout}"
validate_positive_int REAL_BDS_HEALTH_TIMEOUT "${health_timeout}"
validate_positive_int REAL_BDS_STOP_TIMEOUT "${stop_timeout}"
validate_port REAL_BDS_SERVER_PORT "${server_port}"
validate_port REAL_BDS_SERVER_PORT_V6 "${server_port_v6}"

[[ -n "${requested_version}" ]] || {
  printf 'requested BDS version must not be empty\n' >&2
  exit 2
}
[[ -n "${level_name}" && "${level_name}" != */* && "${level_name}" != *\\* ]] || {
  printf 'REAL_BDS_LEVEL_NAME must be a safe single directory name\n' >&2
  exit 2
}

docker volume create "${volume}" >/dev/null

common_args=(
  -e EULA=true
  -e ENABLE_RCON=false
  -e "VERSION=${requested_version}"
  -e READY_DELAY=10
  -e SHUTDOWN_WAIT_TIMEOUT=30
  -e SHUTDOWN_TERM_WAIT=10
  -e 'SERVER_NAME=Real BDS Compatibility'
  -e "SERVER_PORT=${server_port}"
  -e "SERVER_PORTV6=${server_port_v6}"
  -e "LEVEL_NAME=${level_name}"
  -e MAX_PLAYERS=1
  -e ONLINE_MODE=false
  -e VIEW_DISTANCE=5
  -e TICK_DISTANCE=4
  -v "${volume}:/data"
)

inspect_data() {
  local script="$1"
  docker run --rm \
    --user 0:0 \
    -v "${volume}:/data" \
    --entrypoint /bin/bash \
    "${image}" \
    -lc "${script}"
}

assert_install_state() {
  resolved_version="$(inspect_data 'jq -er '\'' .resolved_version '\'' /data/.bds-install.json')"
  resolved_mode="$(inspect_data 'jq -er '\'' .mode '\'' /data/.bds-install.json')"

  [[ -n "${resolved_version}" ]] || {
    printf 'managed install marker resolved_version is empty\n' >&2
    return 1
  }

  if [[ "${requested_version}" == "latest" ]]; then
    [[ "${resolved_mode}" == "latest" ]] || {
      printf 'expected latest managed mode, got %s\n' "${resolved_mode}" >&2
      return 1
    }
  else
    [[ "${resolved_mode}" == "version" ]] || {
      printf 'expected version managed mode, got %s\n' "${resolved_mode}" >&2
      return 1
    }
    [[ "${resolved_version}" == "${requested_version}" ]] || {
      printf 'requested BDS %s but resolved %s\n' "${requested_version}" "${resolved_version}" >&2
      return 1
    }
  fi

  inspect_data \
    "set -Eeuo pipefail; test -x /data/bedrock_server; test \"\$(cat /data/.bds-version)\" = '${resolved_version}'; test -f /data/server.properties"

  printf 'real BDS installed: requested=%s resolved=%s mode=%s\n' \
    "${requested_version}" "${resolved_version}" "${resolved_mode}"
}

wait_for_runtime_contract() {
  local elapsed=0
  local state

  while (( elapsed < ready_timeout )); do
    state="$(docker inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || true)"
    if [[ "${state}" != "running" ]]; then
      printf 'real BDS container exited before readiness (state=%s)\n' "${state:-missing}" >&2
      docker logs "${container}" >&2 2>&1 || true
      return 1
    fi

    if docker exec "${container}" /usr/local/bin/docker-entrypoint.sh healthcheck >/dev/null 2>&1 \
      && docker exec \
        -e "EXPECTED_PORT=${server_port}" \
        -e "EXPECTED_WORLD=${level_name}" \
        "${container}" \
        /bin/bash -lc '
          set -Eeuo pipefail
          port_hex="$(printf "%04X" "${EXPECTED_PORT}")"
          awk -v needle=":${port_hex}" '\''
            toupper($2) ~ toupper(needle) "$" { found=1 }
            END { exit(found ? 0 : 1) }
          '\'' /proc/net/udp /proc/net/udp6
          test -d "/data/worlds/${EXPECTED_WORLD}"
        ' >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  printf 'real BDS did not satisfy readiness + UDP + world contract within %ss\n' "${ready_timeout}" >&2
  docker logs "${container}" >&2 2>&1 || true
  return 1
}

wait_for_docker_health() {
  local elapsed=0
  local health

  while (( elapsed < health_timeout )); do
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}")"
    case "${health}" in
      healthy)
        return 0
        ;;
      unhealthy)
        printf 'Docker healthcheck reported unhealthy\n' >&2
        docker logs "${container}" >&2 2>&1 || true
        return 1
        ;;
    esac
    sleep 2
    elapsed=$((elapsed + 2))
  done

  printf 'Docker healthcheck did not become healthy within %ss\n' "${health_timeout}" >&2
  docker inspect --format '{{json .State.Health}}' "${container}" >&2 || true
  return 1
}

run_runtime_cycle() {
  local cycle="$1"
  local exit_code

  container="${container_prefix}-${cycle}"
  printf '==> real BDS runtime cycle %s\n' "${cycle}"

  docker run -d \
    --name "${container}" \
    "${common_args[@]}" \
    "${image}" \
    >/dev/null

  wait_for_runtime_contract
  wait_for_docker_health

  printf 'real BDS runtime cycle %s reached healthy state\n' "${cycle}"

  docker stop --time "${stop_timeout}" "${container}" >/dev/null
  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "${container}")"

  printf '%s\n' "--- real BDS runtime cycle ${cycle} logs ---"
  docker logs "${container}" 2>&1 | tail -n 160 || true

  [[ "${exit_code}" == "0" ]] || {
    printf 'real BDS container exited with code %s after docker stop\n' "${exit_code}" >&2
    return 1
  }

  inspect_data "set -Eeuo pipefail; test ! -e /data/.ready; test -f '/data/worlds/${level_name}/level.dat'"

  docker rm "${container}" >/dev/null
  container=""
}

printf '==> install official real BDS artifact\n'
docker run --rm \
  "${common_args[@]}" \
  "${image}" \
  install-only

assert_install_state
run_runtime_cycle 1
run_runtime_cycle 2

post_version="$(inspect_data 'jq -er '\'' .resolved_version '\'' /data/.bds-install.json')"
[[ "${post_version}" == "${resolved_version}" ]] || {
  printf 'managed BDS version drifted during compatibility run: %s -> %s\n' \
    "${resolved_version}" "${post_version}" >&2
  exit 1
}

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "${GITHUB_STEP_SUMMARY}" <<EOF
### Real Bedrock Dedicated Server compatibility

- Requested version: \`${requested_version}\`
- Resolved version: \`${resolved_version}\`
- Managed mode: \`${resolved_mode}\`
- Runtime cycles: 2
- Verified: install, native dependency check, world creation, UDP bind on \`${server_port}\`, container healthcheck, shutdown cleanup, persistent-volume restart
EOF
fi

printf 'real BDS compatibility: ok (requested=%s resolved=%s)\n' \
  "${requested_version}" "${resolved_version}"
