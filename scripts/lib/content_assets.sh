# shellcheck shell=bash

install_behaviorpacks() {
  is_true "${BEHAVIORPACKS_ENABLED}" || {
    log INFO "Behavior packs disabled"
    return 0
  }
  [[ -n "${BEHAVIORPACKS_S3_BUCKET}" ]] || {
    log INFO "BEHAVIORPACKS_S3_BUCKET not set, skipping"
    return 0
  }

  mc_configure
  local dst="${INPUT_BEHAVIORPACKS_DIR}"
  local remove=""
  mkdir -p "${dst}"

  if is_true "${BEHAVIORPACKS_SYNC_ONCE}" \
    && find "${dst}" -mindepth 1 -maxdepth 1 -print -quit | grep -q . \
    && ! is_true "${BEHAVIORPACKS_REMOVE_EXTRA}"; then
    log INFO "Behavior packs already present, skipping sync (SYNC_ONCE=true)"
    return 0
  fi

  log INFO "Syncing behavior packs from s3://${BEHAVIORPACKS_S3_BUCKET}/${BEHAVIORPACKS_S3_PREFIX}"
  is_true "${BEHAVIORPACKS_REMOVE_EXTRA}" && remove="--remove"
  mc mirror --overwrite ${remove} \
    "s3/${BEHAVIORPACKS_S3_BUCKET}/${BEHAVIORPACKS_S3_PREFIX}" "${dst}" \
    || die "Failed to sync behavior packs"
}

activate_behaviorpacks() {
  activate_dir_atomic \
    "${INPUT_BEHAVIORPACKS_DIR}" \
    "${DATA_DIR}/behavior_packs" \
    "behavior_packs"
}

install_resourcepacks() {
  is_true "${RESOURCEPACKS_ENABLED}" || {
    log INFO "Resource packs disabled"
    return 0
  }
  [[ -n "${RESOURCEPACKS_S3_BUCKET}" ]] || {
    log INFO "RESOURCEPACKS_S3_BUCKET not set, skipping"
    return 0
  }

  mc_configure
  local dst="${INPUT_RESOURCEPACKS_DIR}"
  local remove=""
  mkdir -p "${dst}"

  if is_true "${RESOURCEPACKS_SYNC_ONCE}" \
    && find "${dst}" -mindepth 1 -maxdepth 1 -print -quit | grep -q . \
    && ! is_true "${RESOURCEPACKS_REMOVE_EXTRA}"; then
    log INFO "Resource packs already present, skipping sync (SYNC_ONCE=true)"
    return 0
  fi

  log INFO "Syncing resource packs from s3://${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}"
  is_true "${RESOURCEPACKS_REMOVE_EXTRA}" && remove="--remove"
  mc mirror --overwrite ${remove} \
    "s3/${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}" "${dst}" \
    || die "Failed to sync resource packs"
}

activate_resourcepacks() {
  activate_dir_atomic \
    "${INPUT_RESOURCEPACKS_DIR}" \
    "${DATA_DIR}/resource_packs" \
    "resource_packs"
}
