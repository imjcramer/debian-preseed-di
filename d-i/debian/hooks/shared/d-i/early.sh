#!/bin/sh
# Shared d-i early hook implementation used by storage families.

early_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

early_bootstrap_fatal() {
  printf '[bootstrap] fatal: %s\n' "$*" >&2
  exit 1
}

early_load_bootstrap() {
  requested_seed_base=${1:-}
  runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}

  if [ ! -s "$bootstrap_lib" ]; then
    early_bootstrap_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
  fi

  # shellcheck disable=SC1090,SC1091
  . "$bootstrap_lib"
  bootstrap_source_common_lib "$requested_seed_base"
}

early_ensure_crypto_dm_modules() {
  kernel_release=$(uname -r 2>/dev/null || true)
  if [ -n "$kernel_release" ]; then
    hook_anna_install_optional "crypto-dm-modules-${kernel_release}-di" || true
  fi
  hook_anna_install_optional crypto-dm-modules || true
}

early_preload_f2fs_tooling() {
  hook_preload_installer_udeb partman-f2fs || true
  hook_preload_installer_command mkfs.f2fs f2fs-tools-udeb || true
  hook_preload_installer_command mkfs.ext4 e2fsprogs-udeb || true
  hook_preload_installer_command mkfs.fat dosfstools-udeb || true
}

family_d_i_early_main() {
  requested_seed_base=${1:-}
  requested_host_profile=${2:-}
  hook_family=${3:-}
  runtime_script_path=${4:-}
  capture_dualboot_sizes=${5:-false}
  preload_f2fs=${6:-false}

  [ -n "$hook_family" ] || early_bootstrap_fatal "d-i early hook family is required"
  [ -n "$runtime_script_path" ] || early_bootstrap_fatal "runtime script path is required"

  early_load_bootstrap "$requested_seed_base"

  LOG="$(installer_runtime_log_dir)/02-preseed.log"
  installer_init_log_file "$LOG" "" "${hook_family} d-i early hook" d-i-early preseed_loaded
  trap 'installer_finalize_log "$?"' EXIT
  installer_load_context_if_present || true

  SEED_BASE=$(installer_seed_base "$requested_seed_base")
  installer_persist_seed_source "$SEED_BASE"
  HOST_PROFILE=$(installer_resolve_host_profile "$requested_host_profile")
  installer_log_boot_context
  installer_log_network_context

  install -d -m 0755 \
    /usr/lib/apt-setup/generators \
    /usr/lib/base-installer.d \
    /usr/lib/finish-install.d \
    /lib/partman/finish.d

  TMP_ENV_DIR="/tmp/install-env"
  RUNTIME_DIR=$(installer_runtime_dir)
  STATE_DIR=$(installer_runtime_state_dir)
  CACHE_DIR=$(installer_runtime_cache_dir)
  RUNTIME_ACCOUNT_FILE="${STATE_DIR}/account.answers.cfg"
  RUNTIME_CRYPTO_FILE="${STATE_DIR}/crypto.answers.cfg"
  RUNTIME_PARTMAN_FILE="${STATE_DIR}/partman.answers.cfg"
  RUNTIME_ENV_FILE="${STATE_DIR}/runtime.env"
  RUNTIME_RECIPE_FILE="${CACHE_DIR}/expert_recipe"

  install -d -m 0700 "$TMP_ENV_DIR" "$RUNTIME_DIR"
  bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook

  fetch_hook_file "hooks/shared/apt-setup/generators/99-apt-preferences" "/usr/lib/apt-setup/generators/99-apt-preferences"
  chmod 0755 /usr/lib/apt-setup/generators/99-apt-preferences
  fetch_hook_file "hooks/shared/base-stage.d/20-fstab-guard" "/usr/lib/base-installer.d/20-fstab-guard"
  fetch_hook_file "hooks/shared/finish-install.d/99-normalize-finish" "/usr/lib/finish-install.d/99-normalize-finish"
  fetch_hook_file "scripts/runtime/common.sh" "$TMP_ENV_DIR/runtime-common.sh"
  fetch_hook_file "$runtime_script_path" "$TMP_ENV_DIR/runtime.sh"
  fetch_hook_file "scripts/runtime/account.sh" "$TMP_ENV_DIR/account.sh"
  fetch_hook_file "scripts/partman/detect-disk.sh" "$TMP_ENV_DIR/detect-disk.sh"
  installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$TMP_ENV_DIR/host.env" 0600
  installer_fetch_account_env "$SEED_BASE" "$TMP_ENV_DIR/account.env" 0600

  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/host.env"
  RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
  export RUNTIME_COMMON_LIB
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.sh"
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/account.sh"
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/account.env"

  write_crypto_answers=false
  if command -v runtime_crypto_answers_required >/dev/null 2>&1; then
    if runtime_crypto_answers_required; then
      write_crypto_answers=true
    fi
  fi

  hook_resolve_install_disk "$TMP_ENV_DIR/detect-disk.sh" "$HOST_PROFILE"
  installer_log_disk_context

  runtime_apply_ssh_from_classes
  runtime_apply_layout_from_cmdline
  runtime_apply_account_from_cmdline
  runtime_seed_identity_answers
  installer_log_preseed_context
  installer_info "seeded runtime identity fragment from generated hostname"

  # Partman crypto and later Secure Boot helpers need cryptsetup in d-i.
  hook_ensure_installer_command cryptsetup cryptsetup-udeb
  if early_bool_is_true "$write_crypto_answers"; then
    early_ensure_crypto_dm_modules
  fi
  hook_preload_partition_tooling
  if early_bool_is_true "$preload_f2fs"; then
    early_preload_f2fs_tooling
  fi

  runtime_write_account_answers "$RUNTIME_ACCOUNT_FILE"
  runtime_apply_answers_file "$RUNTIME_ACCOUNT_FILE"
  installer_info "seeded runtime account fragment from ${RUNTIME_ACCOUNT_FILE}"

  if early_bool_is_true "$write_crypto_answers"; then
    runtime_write_crypto_answers "$RUNTIME_CRYPTO_FILE"
    runtime_apply_answers_file "$RUNTIME_CRYPTO_FILE"
    installer_info "seeded runtime crypto fragment from ${RUNTIME_CRYPTO_FILE}"
  fi
  runtime_write_effective_account_env "$TMP_ENV_DIR/account.env"

  if early_bool_is_true "$capture_dualboot_sizes"; then
    runtime_capture_dualboot_partition_sizes
  fi
  runtime_write_runtime_env "$RUNTIME_ENV_FILE"
  cp "$RUNTIME_ENV_FILE" "${TMP_ENV_DIR}/runtime.env"
  runtime_write_expert_recipe "$RUNTIME_RECIPE_FILE"
  runtime_write_partman_fragment "$RUNTIME_PARTMAN_FILE" "$RUNTIME_RECIPE_FILE"
  runtime_apply_answers_file "$RUNTIME_PARTMAN_FILE"
  installer_info "seeded runtime partman fragment from ${RUNTIME_PARTMAN_FILE}"
  installer_info "hooks installed from $(installer_seed_source_type "$SEED_BASE") seed source $SEED_BASE"
}
