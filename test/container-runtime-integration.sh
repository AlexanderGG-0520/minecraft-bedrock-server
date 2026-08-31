#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:-minecraft-bedrock-server:ci-latest}"
tmp_dir="$(mktemp -d)"
container_name="bedrock-runtime-smoke-${RANDOM}-${RANDOM}"

cleanup() {
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

mkdir -p \
  "${tmp_dir}/fixture" \
  "${tmp_dir}/install-data" \
  "${tmp_dir}/root-install-data" \
  "${tmp_dir}/runtime-data/worlds/Test World" \
  "${tmp_dir}/behavior-input/managed_bp" \
  "${tmp_dir}/resource-input/managed_rp"
chmod 0777 \
  "${tmp_dir}/install-data" \
  "${tmp_dir}/root-install-data" \
  "${tmp_dir}/runtime-data" \
  "${tmp_dir}/runtime-data/worlds" \
  "${tmp_dir}/runtime-data/worlds/Test World"

cat > "${tmp_dir}/fake-bedrock.c" <<'EOF'
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

cc -O2 -o "${tmp_dir}/fixture/bedrock_server" "${tmp_dir}/fake-bedrock.c"
printf 'server-name=Fixture Server\nserver-port=19132\n' > "${tmp_dir}/fixture/server.properties"
printf '[]\n' > "${tmp_dir}/fixture/allowlist.json"
printf '[]\n' > "${tmp_dir}/fixture/permissions.json"

cat > "${tmp_dir}/behavior-input/managed_bp/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Integration BP",
    "description": "integration",
    "uuid": "33333333-3333-4333-8333-333333333333",
    "version": [1, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "data",
      "uuid": "33333333-3333-4333-8333-333333333334",
      "version": [1, 0, 0]
    }
  ]
}
JSON

cat > "${tmp_dir}/resource-input/managed_rp/manifest.json" <<'JSON'
{
  "format_version": 2,
  "header": {
    "name": "Integration RP",
    "description": "integration",
    "uuid": "44444444-4444-4444-8444-444444444444",
    "version": [2, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "type": "resources",
      "uuid": "44444444-4444-4444-8444-444444444445",
      "version": [2, 0, 0]
    }
  ]
}
JSON

python3 - "${tmp_dir}" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
fixture = root / "fixture"
with zipfile.ZipFile(root / "bedrock-server-9.9.9.9.zip", "w", zipfile.ZIP_DEFLATED) as zf:
    for path in fixture.iterdir():
        zf.write(path, path.name)
PY

common_args=(
  -e EULA=true
  -e VERSION=9.9.9.9
  -e BDS_DOWNLOAD_URL=file:///fixture/bedrock-server-9.9.9.9.zip
  -v "${tmp_dir}/bedrock-server-9.9.9.9.zip:/fixture/bedrock-server-9.9.9.9.zip:ro"
)

image_user="$(docker image inspect -f '{{.Config.User}}' "${image}")"
runtime_identity="$(docker run --rm --entrypoint /bin/bash "${image}" -lc 'printf "%s:%s" "$(id -u)" "$(id -g)"')"
printf 'image Config.User=%s\n' "${image_user}"
printf 'image default identity=%s\n' "${runtime_identity}"

[[ "${image_user}" == "minecraft" ]] || {
  printf 'unexpected image Config.User: %s\n' "${image_user}" >&2
  exit 1
}
[[ "${runtime_identity}" == "1000:1000" ]] || {
  printf 'unexpected default runtime identity: %s\n' "${runtime_identity}" >&2
  exit 1
}

docker run --rm --entrypoint /bin/bash "${image}" -lc '
  test -w /behavior_packs
  test -w /resource_packs
  printf "entrypoint sha256="
  sha256sum /usr/local/bin/docker-entrypoint.sh | awk "{print \$1}"
  printf "filesystem module sha256="
  sha256sum /usr/local/lib/minecraft-bedrock-server/filesystem.sh | awk "{print \$1}"
  grep -n -E "Entering non-root mode|Dropping privileges before lifecycle" \
    /usr/local/bin/docker-entrypoint.sh \
    /usr/local/lib/minecraft-bedrock-server/filesystem.sh || true
'

# Install-only must not depend on runtime-only RCON credentials.
docker run --rm \
  "${common_args[@]}" \
  -v "${tmp_dir}/install-data:/data" \
  "${image}" install-only >/dev/null

install_marker="${tmp_dir}/install-data/.bds-install.json"
[[ -f "${install_marker}" ]] || {
  printf 'install-only did not create managed BDS install marker\n' >&2
  exit 1
}
[[ ! -e "${tmp_dir}/install-data/.ready" ]] || {
  printf 'install-only created runtime readiness state\n' >&2
  exit 1
}

# Root-start compatibility must repair ownership, drop privileges, and preserve install-only mode.
docker run --rm \
  --user 0:0 \
  "${common_args[@]}" \
  -e RUN_UID=1000 \
  -e RUN_GID=1000 \
  -e FIX_OWNERSHIP=true \
  -v "${tmp_dir}/root-install-data:/data" \
  "${image}" install-only >/dev/null

root_install_marker="${tmp_dir}/root-install-data/.bds-install.json"
[[ -f "${root_install_marker}" ]] || {
  printf 'root install-only did not create managed BDS install marker\n' >&2
  exit 1
}
[[ ! -e "${tmp_dir}/root-install-data/.ready" ]] || {
  printf 'root install-only lost command mode and entered runtime\n' >&2
  exit 1
}
[[ "$(stat -c '%u:%g' "${tmp_dir}/root-install-data")" == "1000:1000" ]] || {
  printf 'root ownership repair did not converge to 1000:1000\n' >&2
  exit 1
}

# Normal runtime lifecycle: install, apply Bedrock managed state, become ready, then terminate cleanly.
docker run -d \
  --name "${container_name}" \
  "${common_args[@]}" \
  -e ENABLE_RCON=false \
  -e READY_DELAY=1 \
  -e LEVEL_NAME='Test World' \
  -e BDS_ALLOWLIST_JSON='[{"name":"FixturePlayer","ignoresPlayerLimit":true}]' \
  -e BDS_PERMISSIONS_JSON='[{"xuid":"123456789","permission":"operator"}]' \
  -e WORLD_PACKS_BINDING_ENABLED=true \
  -v "${tmp_dir}/behavior-input:/behavior_packs:ro" \
  -v "${tmp_dir}/resource-input:/resource_packs:ro" \
  -v "${tmp_dir}/runtime-data:/data" \
  "${image}" >/dev/null

ready=0
for _ in $(seq 1 20); do
  if docker exec "${container_name}" /usr/local/bin/docker-entrypoint.sh healthcheck >/dev/null 2>&1; then
    ready=1
    break
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "${container_name}")" != "true" ]]; then
    docker logs "${container_name}" >&2 || true
    printf 'container exited before readiness\n' >&2
    exit 1
  fi
  sleep 1
done

if (( ready != 1 )); then
  docker logs "${container_name}" >&2 || true
  printf 'container did not become ready\n' >&2
  exit 1
fi

[[ -x "${tmp_dir}/runtime-data/bedrock_server" ]] || {
  printf 'bedrock_server was not installed\n' >&2
  exit 1
}

marker="${tmp_dir}/runtime-data/.bds-install.json"
[[ -f "${marker}" ]] || {
  printf 'managed BDS install marker was not created\n' >&2
  exit 1
}
[[ "$(jq -r '.resolved_version' "${marker}")" == "9.9.9.9" ]] || {
  printf 'managed BDS install marker has wrong resolved version\n' >&2
  exit 1
}

jq -e '
  length == 1
  and .[0].name == "FixturePlayer"
  and .[0].ignoresPlayerLimit == true
' "${tmp_dir}/runtime-data/allowlist.json" >/dev/null \
  || { printf 'managed allowlist was not applied in the real container lifecycle\n' >&2; exit 1; }

jq -e '
  length == 1
  and .[0].xuid == "123456789"
  and .[0].permission == "operator"
' "${tmp_dir}/runtime-data/permissions.json" >/dev/null \
  || { printf 'managed permissions were not applied in the real container lifecycle\n' >&2; exit 1; }

jq -e '
  length == 1
  and .[0].pack_id == "33333333-3333-4333-8333-333333333333"
  and .[0].version == [1,0,0]
' "${tmp_dir}/runtime-data/worlds/Test World/world_behavior_packs.json" >/dev/null \
  || { printf 'managed behavior pack was not bound in the real container lifecycle\n' >&2; exit 1; }

jq -e '
  length == 1
  and .[0].pack_id == "44444444-4444-4444-8444-444444444444"
  and .[0].version == [2,0,0]
' "${tmp_dir}/runtime-data/worlds/Test World/world_resource_packs.json" >/dev/null \
  || { printf 'managed resource pack was not bound in the real container lifecycle\n' >&2; exit 1; }

[[ -f "${tmp_dir}/runtime-data/.ready" ]] || {
  printf 'readiness file was not created\n' >&2
  exit 1
}
docker stop -t 10 "${container_name}" >/dev/null

exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${container_name}")"
[[ "${exit_code}" == "0" ]] || {
  docker logs "${container_name}" >&2 || true
  printf 'container exited with status %s\n' "${exit_code}" >&2
  exit 1
}

[[ ! -e "${tmp_dir}/runtime-data/.ready" ]] || {
  printf 'readiness file remained after shutdown\n' >&2
  exit 1
}

printf 'container runtime integration: ok\n'
