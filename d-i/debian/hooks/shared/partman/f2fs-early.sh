#!/bin/sh
# Shared F2FS-family partman early hook.
set -eu

LOG="${INSTALLER_LOG_DIR:-${INSTALLER_PRESEED_LOG_DIR:-/tmp/preseed-logs}}/05-partman.log"
HOOK_FAMILY=${HOOK_FAMILY:-f2fs}

fatal() {
  installer_fatal "$@"
}

ensure_partition_tooling() {
  hook_ensure_partition_tooling
}

ensure_f2fs_tooling() {
  hook_preload_installer_udeb partman-f2fs || true
  hook_ensure_installer_command mkfs.f2fs f2fs-tools-udeb
  hook_ensure_installer_command mkfs.ext4 e2fsprogs-udeb
  hook_ensure_installer_command mkfs.fat dosfstools-udeb
}

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  BOOTSTRAP_LIB="${SELF_DIR}/../../../../scripts/common/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
installer_init_log_file "$LOG" "" "${HOOK_FAMILY} partman early hook" partman-early partman_start
trap 'installer_finalize_log "$?"' EXIT
installer_load_context_if_present || true

SEED_BASE=$(installer_seed_base "${1:-}")
installer_persist_seed_source "$SEED_BASE"
HOST_PROFILE=$(installer_resolve_host_profile "${2:-}")

LAYOUT_HOOK=/lib/partman/finish.d/99-storage-layout
TMP_ENV_DIR=/tmp/install-env
RUNTIME_DIR=$(installer_runtime_dir)
STATE_DIR=$(installer_runtime_state_dir)
CACHE_DIR=$(installer_runtime_cache_dir)
RUNTIME_ENV_FILE="${STATE_DIR}/runtime.env"
RUNTIME_RECIPE_FILE="${CACHE_DIR}/expert_recipe"
RUNTIME_FRAGMENT_FILE="${STATE_DIR}/partman.answers.cfg"
install -d -m 0700 "$TMP_ENV_DIR" "$RUNTIME_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook
fetch_hook_file "hooks/shared/partman/early.sh" "$TMP_ENV_DIR/partman-early-common.sh"
fetch_hook_file "hooks/shared/partman/finish.d/99-storage-layout.sh" "$TMP_ENV_DIR/partman-layout-common.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/partman-early-common.sh"

fetch_env() {
  fetch_env_file "$1" "$2"
}

fetch_hook() {
  fetch_hook_file "$1" "$2"
}

install_storage_layout_hook() {
  fetch_hook_file "hooks/shared/partman/finish.d/99-storage-layout.sh" "$TMP_ENV_DIR/partman-layout-common.sh"
  cat >"$LAYOUT_HOOK" <<EOF
#!/bin/sh
set -eu
IFS=\$(printf ' \t\nX'); IFS=\${IFS%X}
umask 022
TMP_ENV_DIR=${TMP_ENV_DIR}
HOOK_FAMILY=${HOOK_FAMILY}
LAYOUT_COMMON="\${TMP_ENV_DIR}/partman-layout-common.sh"
[ -r "\$LAYOUT_COMMON" ] || {
  printf '[partman-layout] ERROR: missing shared finish helper %s\n' "\$LAYOUT_COMMON" >&2
  exit 1
}
# shellcheck disable=SC1090
. "\$LAYOUT_COMMON"
run_f2fs_storage_layout
EOF
  chmod 0755 "$LAYOUT_HOOK"
}

installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$TMP_ENV_DIR/host.env" 0600
installer_fetch_account_env "$SEED_BASE" "$TMP_ENV_DIR/account.env" 0600
fetch_hook "scripts/runtime/common.sh" "$TMP_ENV_DIR/runtime-common.sh"
fetch_hook "scripts/runtime/f2fs.sh" "$TMP_ENV_DIR/runtime.sh"
fetch_hook "scripts/runtime/account.sh" "$TMP_ENV_DIR/account.sh"
fetch_hook "scripts/partman/detect-disk.sh" "$TMP_ENV_DIR/detect-disk.sh"

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
runtime_apply_account_from_cmdline
runtime_write_effective_account_env "$TMP_ENV_DIR/account.env"

hook_resolve_install_disk "$TMP_ENV_DIR/detect-disk.sh" "$HOST_PROFILE"

ensure_partition_tooling
ensure_f2fs_tooling

if [ -r "$TMP_ENV_DIR/runtime.env" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.env"
else
  runtime_apply_layout_from_cmdline
  runtime_write_runtime_env "$RUNTIME_ENV_FILE"
  cp "$RUNTIME_ENV_FILE" "${TMP_ENV_DIR}/runtime.env"
  runtime_write_expert_recipe "$RUNTIME_RECIPE_FILE"
  runtime_write_partman_fragment "$RUNTIME_FRAGMENT_FILE" "$RUNTIME_RECIPE_FILE"
fi

[ -n "${DEV_INSTALL_DISK:-}" ] || fatal "DEV_INSTALL_DISK must be set"
[ -b "$DEV_INSTALL_DISK" ] || fatal "disk device not found: ${DEV_INSTALL_DISK}"

if command -v umount >/dev/null 2>&1; then
  for dev in "${DEV_INSTALL_DISK}" "${DEV_INSTALL_DISK}"*; do
    [ -b "$dev" ] || continue
    if grep -q "^$dev " /proc/mounts; then
      umount "$dev" || true
    fi
  done
fi

if command -v wipefs >/dev/null 2>&1; then
  wipefs -a -f "$DEV_INSTALL_DISK" || true
fi
if command -v sfdisk >/dev/null 2>&1; then
  sfdisk --delete "$DEV_INSTALL_DISK" >/dev/null 2>&1 || true
fi
if command -v parted >/dev/null 2>&1; then
  parted -s "$DEV_INSTALL_DISK" mklabel gpt || fatal "failed to create GPT label on ${DEV_INSTALL_DISK}"
fi
partman_early_settle_block_devices "$DEV_INSTALL_DISK"

install_storage_layout_hook
installer_info "partman layout hook installed"
