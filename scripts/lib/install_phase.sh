# shellcheck shell=bash

install() {
  log INFO "Install phase start"
  run_phase_hooks "pre-install"

  install_dirs
  install_eula
  install_bds
  ldd_check
  install_world_zip_from_s3
  install_behaviorpacks
  activate_behaviorpacks
  install_resourcepacks
  activate_resourcepacks
  apply_server_properties_from_env

  run_phase_hooks "post-install"
  log INFO "Install phase completed"
}
