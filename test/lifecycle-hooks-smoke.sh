#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../entrypoint.sh
source "${ROOT_DIR}/entrypoint.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

HOOKS_ENABLED=true
HOOKS_DIR="${tmp_dir}/hooks"
HOOKS_STRICT=true
HOOKS_TIMEOUT_SEC=5
HOOK_OUTPUT="${tmp_dir}/hook-output"
export HOOK_OUTPUT

mkdir -p "${HOOKS_DIR}/pre-install.d"
cat > "${HOOKS_DIR}/pre-install.d/10-record" <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${HOOK_PHASE}" > "${HOOK_OUTPUT}"
HOOK
chmod +x "${HOOKS_DIR}/pre-install.d/10-record"

run_phase_hooks pre-install
[[ "$(cat "${HOOK_OUTPUT}")" == "pre-install" ]] || {
  printf 'hook phase was not exported correctly\n' >&2
  exit 1
}

cat > "${HOOKS_DIR}/pre-install.d/20-fail" <<'HOOK'
#!/usr/bin/env bash
exit 7
HOOK
chmod +x "${HOOKS_DIR}/pre-install.d/20-fail"

if (run_phase_hooks pre-install >/dev/null 2>&1); then
  printf 'strict hook failure did not fail the phase\n' >&2
  exit 1
fi

HOOKS_STRICT=false
run_phase_hooks pre-install >/dev/null

printf 'lifecycle hooks smoke: ok\n'
