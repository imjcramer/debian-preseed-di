#!/bin/sh
# Shared late_command storage maintenance helpers. This file is sourced, not executed.

verify_target_pkgsel_include_packages() {
  installer_info "skipping pkgsel/include package verification; package repair remains responsible for missing packages"
}

repair_target_pkgsel_include_packages() {
  require_in_target "pkgsel/include package repair"

  # shellcheck disable=SC2016
  missing_packages=$(capture_in_target "detect missing pkgsel/include packages" /bin/sh -c '
set -eu
packages=$1
[ -n "$packages" ] || exit 0
for pkg in $packages; do
  query_pkg=${pkg%%/*}
  [ -n "$query_pkg" ] || query_pkg=$pkg
  pkg_status=$(dpkg-query -W -f=\${Status} "$query_pkg" 2>/dev/null || true)
  if [ "$pkg_status" != "install ok installed" ]; then
    printf "%s\n" "$pkg"
  fi
done
' sh "${INSTALLER_PKGSEL_INCLUDE}")

  [ -n "$missing_packages" ] || return 0

  installer_warn "repairing missing pkgsel/include packages in target:${missing_packages:+ ${missing_packages}}"
  prepare_target_volatile_dirs_for_apt
  run_in_target "refresh apt metadata before pkgsel/include repair" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      update

  # shellcheck disable=SC2086
  set -- $missing_packages
  run_in_target "install missing pkgsel/include packages" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y install --no-install-recommends "$@"

  verify_target_pkgsel_include_packages
}

managed_target_policy_assets() {
  cat <<'EOF'
etc/apt/apt.conf.d/20auto-upgrades|/etc/apt/apt.conf.d/20auto-upgrades|0644
etc/apt/apt.conf.d/52unattended-upgrades|/etc/apt/apt.conf.d/52unattended-upgrades|0644
etc/apt/apt.conf.d/99noinstall-recommends|/etc/apt/apt.conf.d/99noinstall-recommends|0644
etc/login.defs|/etc/login.defs|0644
etc/systemd/system/unattended-upgrades.service.d/10-preseed-warning-policy.conf|/etc/systemd/system/unattended-upgrades.service.d/10-preseed-warning-policy.conf|0644
EOF
}

stage_target_apt_login_policy_assets() {
  while IFS='|' read -r repo_relpath target_path mode || [ -n "$repo_relpath" ]; do
    [ -n "$repo_relpath" ] || continue
    stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "$repo_relpath")" "$target_path" "$mode"
  done <<EOF
$(managed_target_policy_assets)
EOF
}

stage_target_conditional_apt_refresh_assets() {
  if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
    render_target_template "$TMP_ENV_DIR/apt-refresh-lists.tmpl" "/target${FILE_APT_REFRESH_LISTS_HELPER}" 0755
    render_target_template "$TMP_ENV_DIR/apt-refresh-lists.service.tmpl" "/target${FILE_APT_REFRESH_LISTS_SERVICE}" 0644
  else
    remove_target_asset "${FILE_APT_REFRESH_LISTS_HELPER}"
    remove_target_asset "${FILE_APT_REFRESH_LISTS_SERVICE}"
    remove_target_asset "/etc/systemd/system/multi-user.target.wants/apt-refresh-lists.service"
  fi
}

validate_target_tmpfiles_policy_path() {
  case "${1:-}" in
    /*) ;;
    *) installer_fatal "managed tmpfiles policy path must be absolute: ${1:-unset}" ;;
  esac
  case "$1" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "managed tmpfiles policy path contains unsupported syntax: ${1}"
      ;;
  esac
}

normalize_target_tmpfiles_directory_policy() {
  tmpfiles_policy_path=$1
  tmpfiles_policy_label=${2:-managed tmpfiles directory policy}

  validate_target_tmpfiles_policy_path "$tmpfiles_policy_path"
  [ -r "/target${tmpfiles_policy_path}" ] ||
    installer_fatal "managed tmpfiles policy is missing before normalization: ${tmpfiles_policy_path}"

  # Apply only directory entries from the rendered tmpfiles policy so the target
  # file remains the single source of truth for shared storage permissions.
  # shellcheck disable=SC2016
  run_in_target_quiet "normalize ${tmpfiles_policy_label}" /bin/sh -eu -c '
conf_path=$1
conf_label=$2

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  line=$(printf "%s" "$raw_line" | sed "s/^[[:space:]]*//; s/[[:space:]]*$//")
  case "$line" in
    ""|"#"*) continue ;;
  esac

  # shellcheck disable=SC2086
  set -- $line
  entry_type=${1:-}
  entry_path=${2:-}
  entry_mode=${3:-}
  entry_owner=${4:--}
  entry_group=${5:--}

  case "$entry_type" in
    d) ;;
    *) continue ;;
  esac
  case "$entry_path" in
    /*) ;;
    *)
      printf "fatal: %s has a non-absolute directory path: %s\n" "$conf_label" "${entry_path:-unset}" >&2
      exit 1
      ;;
  esac
  case "$entry_path" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      printf "fatal: %s has unsupported directory path syntax: %s\n" "$conf_label" "$entry_path" >&2
      exit 1
      ;;
  esac
  case "$entry_mode" in
    0[0-7][0-7][0-7][0-7])
      entry_mode=${entry_mode#0}
      ;;
    [0-7][0-7][0-7][0-7]|[0-7][0-7][0-7]) ;;
    *)
      printf "fatal: %s has invalid directory mode %s for %s\n" "$conf_label" "${entry_mode:-unset}" "$entry_path" >&2
      exit 1
      ;;
  esac

  install -d -m "$entry_mode" -- "$entry_path"

  if [ "$entry_owner" = "-" ]; then
    resolved_owner=$(stat -c "%u" -- "$entry_path")
  else
    resolved_owner=$entry_owner
  fi
  if [ "$entry_group" = "-" ]; then
    resolved_group=$(stat -c "%g" -- "$entry_path")
  else
    resolved_group=$entry_group
  fi

  chown "${resolved_owner}:${resolved_group}" -- "$entry_path"
  chmod "$entry_mode" -- "$entry_path"
done < "$conf_path"
' sh "$tmpfiles_policy_path" "$tmpfiles_policy_label"
}

stage_target_runtime_storage_root_policy() {
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/10-runtime-storage-roots.conf)" "/etc/tmpfiles.d/10-runtime-storage-roots.conf" 0644
}

ensure_target_managed_runtime_storage_roots() {
  run_in_target_quiet "ensure shared devops group" /bin/sh -eu -c '
getent group devops >/dev/null 2>&1 || groupadd --system devops
' sh
  stage_target_runtime_storage_root_policy
  normalize_target_tmpfiles_directory_policy "/etc/tmpfiles.d/10-runtime-storage-roots.conf" "shared runtime storage roots"
}

stage_target_common_storage_maintenance_assets() {
  stage_target_runtime_storage_root_policy
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/libexec/install-tools/preseed-log.sh)" "/usr/libexec/install-tools/preseed-log.sh" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/journald.conf.d/10-storage.conf)" "${FILE_JOURNALD_STORAGE_CONF}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/timesyncd.conf)" "${FILE_TIMESYNCD_CONF}" 0644
  install_target_tmpfs_pre_clean_assets
  install_target_tmpfs_tmpfiles_assets
  stage_target_conditional_apt_refresh_assets
  stage_target_apt_login_policy_assets
  render_target_template "$TMP_ENV_DIR/apt-daily.override.conf.tmpl" "/target${FILE_APT_DAILY_SERVICE_OVERRIDE}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/apt/listchanges.conf)" "${FILE_APT_LISTCHANGES_CONF}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/fstrim.service.d/override.conf)" "${FILE_FSTRIM_SERVICE_OVERRIDE}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/fstrim.timer.d/override.conf)" "${FILE_FSTRIM_TIMER_OVERRIDE}" 0644
}

target_xfs_scrub_cpuaccounting_units() {
  printf '%s\n' \
    xfs_scrub@.service \
    xfs_scrub_all.service \
    xfs_scrub_media@.service \
    system-xfs_scrub.slice
}

sanitize_target_xfs_scrub_systemd_units() {
  sanitized_count=0

  for xfs_unit in $(target_xfs_scrub_cpuaccounting_units); do
    xfs_unit_path=$(target_systemd_unit_path "$xfs_unit" system 2>/dev/null || true)
    [ -n "$xfs_unit_path" ] || continue
    [ -r "/target${xfs_unit_path}" ] || continue
    grep -q '^[[:space:]]*CPUAccounting[[:space:]]*=' "/target${xfs_unit_path}" || continue

    xfs_unit_dest="/target${DIR_SYSTEMD_SYSTEM}/${xfs_unit}"
    xfs_unit_tmp="${xfs_unit_dest}.tmp.$$"
    install -d -m 0755 "/target${DIR_SYSTEMD_SYSTEM}"
    if ! sed '/^[[:space:]]*CPUAccounting[[:space:]]*=/d' "/target${xfs_unit_path}" >"$xfs_unit_tmp"; then
      rm -f "$xfs_unit_tmp"
      installer_fatal "failed to sanitize xfs scrub unit: ${xfs_unit_path}"
    fi
    [ -s "$xfs_unit_tmp" ] || {
      rm -f "$xfs_unit_tmp"
      installer_fatal "sanitized xfs scrub unit is empty: ${xfs_unit_path}"
    }
    install -m 0644 "$xfs_unit_tmp" "$xfs_unit_dest"
    rm -f "$xfs_unit_tmp"
    grep -q '^[[:space:]]*CPUAccounting[[:space:]]*=' "$xfs_unit_dest" &&
      installer_fatal "sanitized xfs scrub unit still contains CPUAccounting=: ${xfs_unit_dest#/target}"

    for xfs_unit_link in "/target${DIR_SYSTEMD_SYSTEM}"/*.wants/"$xfs_unit" "/target${DIR_SYSTEMD_SYSTEM}"/*.requires/"$xfs_unit"; do
      [ -L "$xfs_unit_link" ] || continue
      ln -sf "${DIR_SYSTEMD_SYSTEM}/${xfs_unit}" "$xfs_unit_link"
    done
    sanitized_count=$((sanitized_count + 1))
  done

  [ "$sanitized_count" -eq 0 ] ||
    installer_info "sanitized xfs scrub systemd units with removed CPUAccounting directives: ${sanitized_count}"
}

verify_target_xfs_scrub_systemd_units() {
  for xfs_unit in $(target_xfs_scrub_cpuaccounting_units); do
    xfs_unit_path=$(target_systemd_unit_path "$xfs_unit" system 2>/dev/null || true)
    [ -n "$xfs_unit_path" ] || continue
    [ -r "/target${xfs_unit_path}" ] || continue
    if grep -q '^[[:space:]]*CPUAccounting[[:space:]]*=' "/target${xfs_unit_path}"; then
      installer_fatal "target xfs scrub unit still contains removed CPUAccounting= directive: ${xfs_unit_path}"
    fi
  done
}

verify_target_tmpfs_pre_clean_and_apt_refresh_staging() {
  require_in_target "tmpfs pre-clean and apt refresh verification"

  # shellcheck disable=SC2016
  run_in_target "verify staged tmpfs pre-clean and apt refresh payload" /bin/sh -c '
set -eu
fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}
tmpfs_var_log=$1
tmpfs_var_cache=$2
tmpfs_apt_lists=$3
tmpfs_coredump=$4
tmpfs_data_run=$5
dir_data_run=$6
fstrim_service_override=$7
fstrim_timer_override=$8
var_log_tmpfiles=$9
apt_lists_tmpfiles=${10}
var_cache_tmpfiles=${11}
data_run_tmpfiles=${12}
tmpfs_pre_clean_helper=${13}
tmpfs_pre_clean_service=${14}
var_log_mount_override=${15}
var_cache_mount_override=${16}
apt_lists_mount_override=${17}
coredump_mount_override=${18}
data_run_mount_override=${19}
apt_refresh_helper=${20}
apt_refresh_service=${21}
apt_daily_override=${22}

is_true() {
  [ "$1" = true ]
}
any_tmpfs_pre_clean_enabled() {
  is_true "$tmpfs_var_log" ||
    is_true "$tmpfs_var_cache" ||
    is_true "$tmpfs_apt_lists" ||
    is_true "$tmpfs_coredump" ||
    is_true "$tmpfs_data_run"
}
check_path_state() {
  enabled=$1
  path=$2
  if is_true "$enabled"; then
    [ -r "$path" ]
  else
    [ ! -e "$path" ]
  fi
}
check_policy_line() {
  path=$1
  pattern=$2
  [ -r "$path" ] || fatal "managed policy file is missing: $path"
  grep -q "$pattern" "$path"
}

[ -r "$fstrim_service_override" ]
[ -r "$fstrim_timer_override" ]
check_policy_line /etc/apt/apt.conf.d/20auto-upgrades "^APT::Periodic::Update-Package-Lists \"1\";"
check_policy_line /etc/apt/apt.conf.d/20auto-upgrades "^APT::Periodic::Unattended-Upgrade \"1\";"
check_policy_line /etc/apt/apt.conf.d/52unattended-upgrades "^Unattended-Upgrade::MailReport \"on-change\";"
check_policy_line /etc/apt/apt.conf.d/52unattended-upgrades "^Unattended-Upgrade::Remove-New-Unused-Dependencies \"true\";"
check_policy_line /etc/apt/apt.conf.d/52unattended-upgrades "^Unattended-Upgrade::Remove-Unused-Dependencies \"true\";"
check_policy_line /etc/apt/apt.conf.d/52unattended-upgrades "^Unattended-Upgrade::Automatic-Reboot \"false\";"
check_policy_line /etc/apt/apt.conf.d/99noinstall-recommends "^APT::Install-Recommends \"false\";"
check_policy_line /etc/apt/apt.conf.d/99noinstall-recommends "^APT::Install-Suggests \"false\";"
check_policy_line /etc/login.defs "^ENCRYPT_METHOD[[:space:]]\\+YESCRYPT$"
check_policy_line /etc/systemd/system/unattended-upgrades.service.d/10-preseed-warning-policy.conf "^Environment=PYTHONWARNINGS=ignore::DeprecationWarning$"
check_path_state "$tmpfs_var_log" "$var_log_tmpfiles"
check_path_state "$tmpfs_var_cache" "$var_cache_tmpfiles"
check_path_state "$tmpfs_apt_lists" "$apt_lists_tmpfiles"
check_path_state "$tmpfs_data_run" "$data_run_tmpfiles"
check_path_state "$tmpfs_var_log" "$var_log_mount_override"
check_path_state "$tmpfs_var_cache" "$var_cache_mount_override"
check_path_state "$tmpfs_apt_lists" "$apt_lists_mount_override"
check_path_state "$tmpfs_coredump" "$coredump_mount_override"
check_path_state "$tmpfs_data_run" "$data_run_mount_override"
if any_tmpfs_pre_clean_enabled; then
  [ -x "$tmpfs_pre_clean_helper" ]
  [ -r "$tmpfs_pre_clean_service" ]
  dir_data_parent=${dir_data_run%/run}
  [ "$dir_data_parent" != "$dir_data_run" ] || fatal "DIR_DATA_RUN must end with /run for tmpfs-pre-clean verification: ${dir_data_run}"
else
  [ ! -e "$tmpfs_pre_clean_helper" ]
  [ ! -e "$tmpfs_pre_clean_service" ]
fi
[ ! -e /usr/local/sbin/storage-tmpfiles-refresh ]
[ ! -e /usr/local/sbin/tmpfs-clean ]
[ ! -e /etc/systemd/system/storage-tmpfs-clean.service ]
[ ! -e /etc/systemd/system/storage-tmpfiles-watch.service ]
[ ! -e /etc/systemd/system/tmpfs-clean.service ]
[ -L /etc/systemd/system/timers.target.wants/fstrim.timer ]
[ -r "$apt_daily_override" ]
if is_true "$tmpfs_apt_lists"; then
  [ -x "$apt_refresh_helper" ]
  [ -r "$apt_refresh_service" ]
  [ -L /etc/systemd/system/multi-user.target.wants/apt-refresh-lists.service ]
else
  [ ! -e "$apt_refresh_helper" ]
  [ ! -e "$apt_refresh_service" ]
  [ ! -L /etc/systemd/system/multi-user.target.wants/apt-refresh-lists.service ]
fi
' sh \
    "${TMPFS_VAR_LOG}" \
    "${TMPFS_VAR_CACHE}" \
    "${TMPFS_VAR_LIB_APT_LISTS}" \
    "${TMPFS_SYSTEMD_COREDUMP}" \
    "${TMPFS_DATA_RUN}" \
    "${DIR_DATA_RUN}" \
    "${FILE_FSTRIM_SERVICE_OVERRIDE}" \
    "${FILE_FSTRIM_TIMER_OVERRIDE}" \
    "${FILE_TMPFILES_VAR_LOG_GENERATED}" \
    "${FILE_TMPFILES_APT_LISTS_GENERATED}" \
    "${FILE_TMPFILES_VAR_CACHE_GENERATED}" \
    "${FILE_DATA_RUN_TMPFILES}" \
    "${FILE_TMPFS_PRE_CLEAN_HELPER}" \
    "${FILE_TMPFS_PRE_CLEAN_SERVICE}" \
    "${FILE_TMPFS_PRE_CLEAN_VAR_LOG_MOUNT_OVERRIDE}" \
    "${FILE_TMPFS_PRE_CLEAN_VAR_CACHE_MOUNT_OVERRIDE}" \
    "${FILE_TMPFS_PRE_CLEAN_APT_LISTS_MOUNT_OVERRIDE}" \
    "${FILE_TMPFS_PRE_CLEAN_COREDUMP_MOUNT_OVERRIDE}" \
    "${FILE_TMPFS_PRE_CLEAN_DATA_RUN_MOUNT_OVERRIDE}" \
    "${FILE_APT_REFRESH_LISTS_HELPER}" \
    "${FILE_APT_REFRESH_LISTS_SERVICE}" \
    "${FILE_APT_DAILY_SERVICE_OVERRIDE}"
}

apply_apt_refresh_placeholders() {
  target_path=$1
  installer_apply_scalar_placeholders "$target_path" "$target_path.apt-refresh.$$" \
    APT_REFRESH_LISTS_TIMEOUT "$APT_REFRESH_LISTS_TIMEOUT" \
    APT_REFRESH_LISTS_CONNECTIVITY_URL "$APT_REFRESH_LISTS_CONNECTIVITY_URL"
  mv "$target_path.apt-refresh.$$" "$target_path"
}
