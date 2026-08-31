#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:-minecraft-bedrock-server:ci-latest}"
workspace="${2:-}"
phase="${3:-all}"
auto_workspace=false
current_case="${phase}"

if [[ -z "${workspace}" ]]; then
  if [[ "${phase}" != "all" ]]; then
    printf 'workspace is required when running phase %s\n' "${phase}" >&2
    exit 2
  fi
  workspace="$(mktemp -d)"
  auto_workspace=true
fi

data_dir="${workspace}/data"
fixture_dir="${workspace}/fixture"
pack_a_dir="${workspace}/behavior-a"
pack_b_dir="${workspace}/behavior-b"
artifact_a="${workspace}/bedrock-server-1.0.0.1.zip"
artifact_b="${workspace}/bedrock-server-1.0.0.2.zip"

report_error() {
  local status=$?
  printf 'persistent transition failed: phase=%s case=%s line=%s command=%s exit=%s\n' \
    "${phase}" "${current_case}" "${BASH_LINENO[0]:-${LINENO}}" "${BASH_COMMAND}" "${status}" >&2
  return "${status}"
}
trap report_error ERR

cleanup_workspace() {
  local target="${workspace}"
  [[ -e "${target}" ]] || return 0

  if ! rm -rf -- "${target}" 2>/dev/null; then
    docker run --rm \
      --user 0:0 \
      -e HOST_UID="$(id -u)" \
      -e HOST_GID="$(id -g)" \
      -v "${target}:/cleanup" \
      --entrypoint /bin/sh \
      "${image}" \
      -c 'chown -R "${HOST_UID}:${HOST_GID}" /cleanup' \
      >/dev/null 2>&1 || true
    rm -rf -- "${target}"
  fi
}

run_install() {
  local version="$1"
  local artifact="$2"
  local behavior_input="$3"
  shift 3

  local args=(
    --rm
    -e EULA=true
    -e "VERSION=${version}"
    -e "BDS_DOWNLOAD_URL=file:///fixture/bedrock-server-${version}.zip"
    -v "${data_dir}:/data"
  )

  if [[ -n "${artifact}" ]]; then
    args+=( -v "${artifact}:/fixture/bedrock-server-${version}.zip:ro" )
  fi
  if [[ -n "${behavior_input}" ]]; then
    args+=( -v "${behavior_input}:/behavior_packs:ro" )
  fi

  docker run "${args[@]}" "$@" "${image}" install-only
}

root_data() {
  local script="$1"
  docker run --rm \
    --user 0:0 \
    -v "${data_dir}:/data" \
    --entrypoint /bin/bash \
    "${image}" \
    -lc "${script}"
}

assert_jq() {
  local expression="$1"
  local file="$2"
  local message="$3"

  jq -e "${expression}" "${file}" >/dev/null || {
    printf '%s\n' "${message}" >&2
    return 1
  }
}

assert_artifact() {
  local expected="$1"
  [[ "$(cat "${data_dir}/fixture-version.txt")" == "${expected}" ]] || {
    printf 'expected artifact sentinel %s\n' "${expected}" >&2
    return 1
  }
}

common_state_env=(
  -e WORLD_PACKS_BINDING_ENABLED=true
)

state_a_env=(
  "${common_state_env[@]}"
  -e 'BDS_ALLOWLIST_JSON=[{"name":"ManagedA","ignoresPlayerLimit":false}]'
  -e 'BDS_PERMISSIONS_JSON=[{"xuid":"111","permission":"member"}]'
)

state_b_preserve_env=(
  "${common_state_env[@]}"
  -e 'BDS_ALLOWLIST_JSON=[{"name":"ManagedB","ignoresPlayerLimit":false}]'
  -e 'BDS_PERMISSIONS_JSON=[{"xuid":"222","permission":"operator"}]'
)

state_b_prune_env=(
  "${state_b_preserve_env[@]}"
  -e BDS_ALLOWLIST_REMOVE_EXTRA=true
  -e BDS_PERMISSIONS_REMOVE_EXTRA=true
  -e BEHAVIORPACKS_REMOVE_EXTRA=true
  -e WORLD_PACKS_REMOVE_EXTRA=true
)

phase_setup() {
  current_case="create-fixtures"
  rm -rf -- "${workspace}"
  mkdir -p \
    "${fixture_dir}" \
    "${data_dir}/worlds/Transition World" \
    "${pack_a_dir}/managed_a" \
    "${pack_b_dir}/managed_b"
  chmod 0777 "${data_dir}" "${data_dir}/worlds" "${data_dir}/worlds/Transition World"
  printf 'operator world sentinel\n' > "${data_dir}/worlds/Transition World/operator-sentinel.txt"

  cat > "${workspace}/fake-bedrock.c" <<'EOF'
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void handle_signal(int signal_number) {
  (void)signal_number;
  running = 0;
}

int main(void) {
  signal(SIGTERM, handle_signal);
  signal(SIGINT, handle_signal);
  signal(SIGQUIT, handle_signal);
  while (running) {
    sleep(1);
  }
  return 0;
}
EOF

  cc -O2 -o "${fixture_dir}/bedrock_server" "${workspace}/fake-bedrock.c"
  printf 'server-name=Transition Fixture\nserver-port=19132\nlevel-name=Transition World\n' > "${fixture_dir}/server.properties"
  printf '[]\n' > "${fixture_dir}/allowlist.json"
  printf '[]\n' > "${fixture_dir}/permissions.json"

  cat > "${pack_a_dir}/managed_a/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Managed A",
    "description": "persistent transition fixture",
    "uuid": "11111111-1111-4111-8111-111111111111",
    "version": [1, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "data",
      "uuid": "11111111-1111-4111-8111-111111111112",
      "version": [1, 0, 0]
    }
  ]
}
JSON

  cat > "${pack_b_dir}/managed_b/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Managed B",
    "description": "persistent transition fixture",
    "uuid": "22222222-2222-4222-8222-222222222222",
    "version": [2, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "data",
      "uuid": "22222222-2222-4222-8222-222222222223",
      "version": [2, 0, 0]
    }
  ]
}
JSON

  python3 - "${workspace}" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
fixture = root / "fixture"
for version, sentinel in (("1.0.0.1", "artifact-a\n"), ("1.0.0.2", "artifact-b\n")):
    archive = root / f"bedrock-server-{version}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in fixture.iterdir():
            zf.write(path, path.name)
        info = zipfile.ZipInfo("fixture-version.txt")
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, sentinel)
PY

  printf 'persistent transition fixtures: ok\n'
}

phase_bootstrap() {
  current_case="initial-managed-install"
  printf '==> initial managed install\n'
  run_install \
    1.0.0.1 \
    "${artifact_a}" \
    "${pack_a_dir}" \
    "${state_a_env[@]}" \
    >/dev/null

  assert_artifact artifact-a
  assert_jq '.resolved_version == "1.0.0.1" and .mode == "custom-url"' \
    "${data_dir}/.bds-install.json" \
    'initial managed install marker is incorrect'
  assert_jq 'map(.name) == ["ManagedA"]' \
    "${data_dir}/allowlist.json" \
    'initial managed allowlist state is incorrect'
  assert_jq 'map(.xuid) == ["111"]' \
    "${data_dir}/permissions.json" \
    'initial managed permissions state is incorrect'
  assert_jq 'map(.pack_id) == ["11111111-1111-4111-8111-111111111111"]' \
    "${data_dir}/worlds/Transition World/world_behavior_packs.json" \
    'initial managed world pack binding is incorrect'

  current_case="idempotent-restart"
  printf '==> idempotent restart without artifact availability\n'
  run_install \
    1.0.0.1 \
    '' \
    "${pack_a_dir}" \
    "${state_a_env[@]}" \
    >/dev/null
  assert_artifact artifact-a

  printf 'persistent transition bootstrap: ok\n'
}

phase_ownership() {
  current_case="inject-operator-owned-state"
  printf '==> add operator-owned state\n'
  root_data '
    set -Eeuo pipefail
    tmp=$(mktemp /data/.allowlist.operator.XXXXXX)
    jq '\''. + [{"name":"OperatorPlayer","ignoresPlayerLimit":false,"xuid":"999"}]'\'' /data/allowlist.json > "$tmp"
    mv "$tmp" /data/allowlist.json

    tmp=$(mktemp /data/.permissions.operator.XXXXXX)
    jq '\''. + [{"xuid":"999","permission":"custom"}]'\'' /data/permissions.json > "$tmp"
    mv "$tmp" /data/permissions.json

    tmp=$(mktemp "/data/worlds/Transition World/.binding.operator.XXXXXX")
    jq '\''. + [{"pack_id":"99999999-9999-4999-8999-999999999999","version":[9,9,9]}]'\'' "/data/worlds/Transition World/world_behavior_packs.json" > "$tmp"
    mv "$tmp" "/data/worlds/Transition World/world_behavior_packs.json"

    mkdir -p /data/behavior_packs/operator_pack
    printf "operator-owned\n" > /data/behavior_packs/operator_pack/operator.txt
    printf "operator-sentinel=keep\n" >> /data/server.properties
    chown -R 1000:1000 /data
    find /data -type f -name "*.json" -exec chmod 0644 {} +
  '

  current_case="preserve-with-remove-extra-disabled"
  printf '==> preserve stale managed state while remove-extra is disabled\n'
  run_install \
    1.0.0.1 \
    '' \
    "${pack_b_dir}" \
    "${state_b_preserve_env[@]}" \
    >/dev/null

  assert_jq '([.[].name] | sort) == ["ManagedA","ManagedB","OperatorPlayer"]' \
    "${data_dir}/allowlist.json" \
    'remove-extra=false did not preserve allowlist state'
  assert_jq '([.[].xuid] | sort) == ["111","222","999"]' \
    "${data_dir}/permissions.json" \
    'remove-extra=false did not preserve permissions state'
  assert_jq '(.managed_entries | sort) == ["managed_a","managed_b"]' \
    "${data_dir}/.managed/content-assets/behavior_packs.json" \
    'managed behavior-pack ownership did not retain stale managed entry'
  assert_jq '([.[].pack_id] | sort) == ["11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222","99999999-9999-4999-8999-999999999999"]' \
    "${data_dir}/worlds/Transition World/world_behavior_packs.json" \
    'remove-extra=false did not preserve world bindings'
  [[ -d "${data_dir}/behavior_packs/managed_a" ]] || {
    printf 'stale managed behavior pack disappeared while remove-extra=false\n' >&2
    return 1
  }
  [[ -d "${data_dir}/behavior_packs/operator_pack" ]] || {
    printf 'operator-owned behavior pack was removed\n' >&2
    return 1
  }

  current_case="prune-runtime-owned-state"
  printf '==> prune only stale runtime-owned state\n'
  run_install \
    1.0.0.1 \
    '' \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >/dev/null

  assert_jq '([.[].name] | sort) == ["ManagedB","OperatorPlayer"]' \
    "${data_dir}/allowlist.json" \
    'remove-extra=true removed or retained the wrong allowlist entries'
  assert_jq '([.[].xuid] | sort) == ["222","999"]' \
    "${data_dir}/permissions.json" \
    'remove-extra=true removed or retained the wrong permissions entries'
  assert_jq '.managed_entries == ["managed_b"]' \
    "${data_dir}/.managed/content-assets/behavior_packs.json" \
    'behavior-pack ownership did not converge after remove-extra=true'
  assert_jq '([.[].pack_id] | sort) == ["22222222-2222-4222-8222-222222222222","99999999-9999-4999-8999-999999999999"]' \
    "${data_dir}/worlds/Transition World/world_behavior_packs.json" \
    'remove-extra=true removed or retained the wrong world bindings'
  [[ ! -e "${data_dir}/behavior_packs/managed_a" ]] || {
    printf 'stale runtime-owned behavior pack was not removed\n' >&2
    return 1
  }
  [[ -d "${data_dir}/behavior_packs/managed_b" && -d "${data_dir}/behavior_packs/operator_pack" ]] || {
    printf 'current managed or operator-owned behavior pack disappeared\n' >&2
    return 1
  }

  printf 'persistent transition ownership: ok\n'
}

phase_install_transitions() {
  current_case="reject-incompatible-replacement"
  printf '==> reject incompatible pinned/custom replacement without force\n'
  local rejection_log="${workspace}/rejection.log"
  if run_install \
    1.0.0.2 \
    "${artifact_b}" \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >"${rejection_log}" 2>&1; then
    printf 'incompatible managed install was replaced without FORCE_REINSTALL\n' >&2
    return 1
  fi
  grep -q 'Refusing implicit replacement' "${rejection_log}" || {
    cat "${rejection_log}" >&2
    printf 'incompatible replacement failed for an unexpected reason\n' >&2
    return 1
  }
  assert_artifact artifact-a
  assert_jq '.resolved_version == "1.0.0.1"' \
    "${data_dir}/.bds-install.json" \
    'rejected replacement mutated the managed install marker'

  current_case="force-intentional-replacement"
  printf '==> force intentional pinned/custom replacement\n'
  run_install \
    1.0.0.2 \
    "${artifact_b}" \
    "${pack_b_dir}" \
    -e FORCE_REINSTALL=true \
    "${state_b_prune_env[@]}" \
    >/dev/null

  assert_artifact artifact-b
  assert_jq '.resolved_version == "1.0.0.2"' \
    "${data_dir}/.bds-install.json" \
    'forced replacement did not update the managed install marker'
  [[ -f "${data_dir}/worlds/Transition World/operator-sentinel.txt" ]] || {
    printf 'forced BDS replacement destroyed persistent world state\n' >&2
    return 1
  }
  grep -q '^operator-sentinel=keep$' "${data_dir}/server.properties" || {
    printf 'forced BDS replacement overwrote operator server.properties state\n' >&2
    return 1
  }
  [[ -d "${data_dir}/behavior_packs/operator_pack" ]] || {
    printf 'forced BDS replacement destroyed operator-owned pack state\n' >&2
    return 1
  }

  current_case="recover-missing-executable"
  printf '==> recover when managed executable is missing\n'
  root_data 'rm -f /data/bedrock_server'
  run_install \
    1.0.0.2 \
    "${artifact_b}" \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >/dev/null
  [[ -x "${data_dir}/bedrock_server" ]] || {
    printf 'missing managed executable was not reinstalled\n' >&2
    return 1
  }

  current_case="legacy-version-adoption"
  printf '==> adopt legacy .bds-version state without redownload\n'
  root_data 'rm -f /data/.bds-install.json'
  run_install \
    1.0.0.2 \
    '' \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >/dev/null
  assert_jq '.resolved_version == "1.0.0.2" and .schema_version == 1' \
    "${data_dir}/.bds-install.json" \
    'legacy .bds-version state was not adopted'

  printf 'persistent transition install state: ok\n'
}

phase_invalid_metadata() {
  current_case="reject-corrupt-marker"
  printf '==> reject corrupt managed install metadata\n'
  root_data 'cp /data/.bds-install.json /data/.bds-install.good && printf "{invalid\n" > /data/.bds-install.json && chown 1000:1000 /data/.bds-install.json && chmod 0644 /data/.bds-install.json'
  local corrupt_log="${workspace}/corrupt.log"
  if run_install \
    1.0.0.2 \
    '' \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >"${corrupt_log}" 2>&1; then
    printf 'corrupt managed install marker was accepted\n' >&2
    return 1
  fi
  grep -q 'Invalid/corrupt BDS install marker' "${corrupt_log}" || {
    cat "${corrupt_log}" >&2
    printf 'corrupt marker failed for an unexpected reason\n' >&2
    return 1
  }
  root_data 'mv /data/.bds-install.good /data/.bds-install.json && chown 1000:1000 /data/.bds-install.json && chmod 0644 /data/.bds-install.json'

  current_case="reject-future-schema"
  printf '==> reject unsupported future managed-state schema\n'
  root_data 'cp /data/.bds-install.json /data/.bds-install.good && tmp=$(mktemp /data/.bds-install.future.XXXXXX) && jq ".schema_version = 2" /data/.bds-install.json > "$tmp" && mv "$tmp" /data/.bds-install.json && chown 1000:1000 /data/.bds-install.json && chmod 0644 /data/.bds-install.json'
  local future_log="${workspace}/future.log"
  if run_install \
    1.0.0.2 \
    '' \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >"${future_log}" 2>&1; then
    printf 'future managed install schema was accepted\n' >&2
    return 1
  fi
  grep -q 'Unsupported BDS install marker schema' "${future_log}" || {
    cat "${future_log}" >&2
    printf 'future marker failed for an unexpected reason\n' >&2
    return 1
  }
  root_data 'mv /data/.bds-install.good /data/.bds-install.json && chown 1000:1000 /data/.bds-install.json && chmod 0644 /data/.bds-install.json'

  current_case="reject-unmanaged-executable"
  printf '==> reject unmanaged executable without compatible metadata\n'
  root_data 'cp /data/.bds-install.json /data/.bds-install.good && cp /data/.bds-version /data/.bds-version.good && rm -f /data/.bds-install.json /data/.bds-version'
  local unmanaged_log="${workspace}/unmanaged.log"
  if run_install \
    1.0.0.2 \
    '' \
    "${pack_b_dir}" \
    "${state_b_prune_env[@]}" \
    >"${unmanaged_log}" 2>&1; then
    printf 'unmanaged executable was silently adopted or replaced\n' >&2
    return 1
  fi
  grep -q 'without compatible managed install metadata' "${unmanaged_log}" || {
    cat "${unmanaged_log}" >&2
    printf 'unmanaged executable failed for an unexpected reason\n' >&2
    return 1
  }
  root_data 'mv /data/.bds-install.good /data/.bds-install.json && mv /data/.bds-version.good /data/.bds-version && chown 1000:1000 /data/.bds-install.json /data/.bds-version && chmod 0644 /data/.bds-install.json /data/.bds-version'

  printf 'persistent transition invalid metadata: ok\n'
}

phase_verify() {
  current_case="final-persistent-state"
  assert_jq '([.[].name] | sort) == ["ManagedB","OperatorPlayer"]' \
    "${data_dir}/allowlist.json" \
    'player access drifted after BDS transition matrix'
  assert_jq '([.[].pack_id] | sort) == ["22222222-2222-4222-8222-222222222222","99999999-9999-4999-8999-999999999999"]' \
    "${data_dir}/worlds/Transition World/world_behavior_packs.json" \
    'world pack bindings drifted after BDS transition matrix'
  [[ -f "${data_dir}/worlds/Transition World/operator-sentinel.txt" ]] || {
    printf 'persistent world state disappeared during transition matrix\n' >&2
    return 1
  }
  [[ -d "${data_dir}/behavior_packs/managed_b" && -d "${data_dir}/behavior_packs/operator_pack" ]] || {
    printf 'managed or operator-owned pack state drifted after transition matrix\n' >&2
    return 1
  }
  grep -q '^operator-sentinel=keep$' "${data_dir}/server.properties" || {
    printf 'operator server.properties state drifted after transition matrix\n' >&2
    return 1
  }

  printf 'persistent state transition integration: ok\n'
}

run_phase() {
  local requested="$1"
  phase="${requested}"
  current_case="${requested}"

  case "${requested}" in
    setup)
      phase_setup
      ;;
    bootstrap)
      phase_bootstrap
      ;;
    ownership)
      phase_ownership
      ;;
    install-transitions)
      phase_install_transitions
      ;;
    invalid-metadata)
      phase_invalid_metadata
      ;;
    verify)
      phase_verify
      ;;
    cleanup)
      cleanup_workspace
      ;;
    *)
      printf 'unknown persistent transition phase: %s\n' "${requested}" >&2
      return 2
      ;;
  esac
}

if [[ "${phase}" == "all" ]]; then
  trap 'status=$?; cleanup_workspace || true; exit "${status}"' EXIT
  run_phase setup
  run_phase bootstrap
  run_phase ownership
  run_phase install-transitions
  run_phase invalid-metadata
  run_phase verify
else
  run_phase "${phase}"
fi
