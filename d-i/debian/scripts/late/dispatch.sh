#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  BOOTSTRAP_LIB="${SELF_DIR}/../common/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || {
  echo "fatal: installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}" >&2
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
installer_init_log_file "$(installer_runtime_log_dir)/09-late.log" "" "late dispatch" late-dispatch late_command
trap 'installer_finalize_log "$?"' EXIT

seed_base=$(installer_seed_base "${1:-}")
installer_ensure_context_loaded "$seed_base"
host_profile=$(installer_resolve_host_profile "")
hook_family=${INSTALLER_HOOK_FAMILY:-${INSTALLER_HOST_FAMILY}}
shared_hook_path=$(installer_repo_resolve_path hooks/shared/late_command.sh)
shared_hook_dest="${RUNTIME_DIR}/bootstrap/shared-late.sh"
role_hook_relpath="${INSTALLER_HOST_VARIANT}/late_command.sh"
installer_validate_repo_dir_value role_hook_relpath "$role_hook_relpath"
case "${INSTALLER_HOST_VARIANT:-}" in
  desktop)
    role_hook_path=$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP late_command.sh)
    ;;
  server)
    role_hook_path=$(installer_repo_join_var DIR_HOOKS_ROLE_SERVER late_command.sh)
    ;;
  *)
    role_hook_path=$(installer_repo_resolve_path "hooks/role/${role_hook_relpath}")
    ;;
esac
role_hook_dest="${RUNTIME_DIR}/bootstrap/role-late.sh"
helper_dir="${RUNTIME_DIR}/bootstrap/late-helpers"
shared_module_dir="${RUNTIME_DIR}/bootstrap/late-modules"
shared_modules="core target-assets volatile-storage storage-maintenance templates network grub security dbus-broker podman gitlab-runner zram-swap btrfs-family f2fs-family account"

installer_fetch_file "$seed_base" "$shared_hook_path" "$shared_hook_dest" 0644
install -d -m 0700 "$shared_module_dir"
for shared_module in $shared_modules; do
  installer_fetch_file \
    "$seed_base" \
    "$(installer_repo_join_var DIR_SCRIPTS_LATE "${shared_module}.sh")" \
    "${shared_module_dir}/${shared_module}.sh" \
    0644
done
install -d -m 0700 "$helper_dir"
case "$hook_family" in
  btrfs|vm)
    INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
    INSTALLER_LATE_MODULE_DIR=$shared_module_dir \
    SHARED_LATE_COMMAND=$shared_hook_dest \
      /bin/sh -c '. "$SHARED_LATE_COMMAND"; run_btrfs_family_late_command "$@"' sh \
      "$hook_family" "$seed_base" "$host_profile"
    ;;
  f2fs)
    INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
    INSTALLER_LATE_MODULE_DIR=$shared_module_dir \
    SHARED_LATE_COMMAND=$shared_hook_dest \
      /bin/sh -c '. "$SHARED_LATE_COMMAND"; run_f2fs_family_late_command "$@"' sh \
      "$seed_base" "$host_profile"
    ;;
  *)
    installer_fatal "unsupported shared late storage family: ${hook_family}"
    ;;
esac
run_helper_script() {
  helper_path=$1
  helper_dest=$2
  shift 2

  installer_fetch_file "$seed_base" "$helper_path" "$helper_dest" 0755
  "$helper_dest" "$@"
}

run_selected_class_helpers() {
  while IFS='|' read -r group_name class_name _class_relpath || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    helper_name=$(installer_class_meta_value "$seed_base" "$group_name" "$class_name" late_helper)
    [ -n "$helper_name" ] || continue
    helper_path=$(installer_repo_join_var DIR_SCRIPTS_LATE "${helper_name}.sh")
    helper_dest="${helper_dir}/${helper_name}.sh"
    run_helper_script "$helper_path" "$helper_dest" /target
  done <<EOF
$(cat "$(installer_selected_class_records_path)")
EOF
}

run_selected_class_helpers

if installer_fetch_seed_path "$seed_base" "$role_hook_path" "$role_hook_dest" 0755; then
  INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
  INSTALLER_LATE_MODULE_DIR=$shared_module_dir \
    "$role_hook_dest" "$seed_base" "$host_profile"
fi
