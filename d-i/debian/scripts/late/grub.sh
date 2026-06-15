#!/bin/sh
# Shared late_command grub helpers. This file is sourced, not executed.

set_optional_path() {
  var_name=$1
  enabled=$2

  case "$var_name" in
    [A-Z_][A-Z0-9_]*) ;;
    *) installer_fatal "invalid optional path variable name: ${var_name}" ;;
  esac

  if [ "$enabled" = true ]; then
    quoted_value=$(shell_single_quote "$3")
    eval "$var_name=$quoted_value"
  else
    eval "$var_name="
  fi
}

grub_profile_label() {
  case "$1" in
    "${BOOTPROFILE_DEFAULT}") printf 'Balanced\n' ;;
    "${BOOTPROFILE_HARDENED}") printf 'Hardened\n' ;;
    "${BOOTPROFILE_PERFORMANCE}") printf 'Performance\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

grub_cmdline_has_token_prefix() {
  grub_cmdline=$1
  grub_prefix=$2

  for grub_token in $grub_cmdline; do
    case "$grub_token" in
      "${grub_prefix}"*)
        return 0
        ;;
    esac
  done
  return 1
}

grub_root_uses_btrfs() {
  grub_cmdline_has_token_prefix "${GRUB_ROOT_FLAGS:-}" "rootfstype=btrfs"
}

apply_btrfs_root_initramfs_fsck_policy() {
  # Do not inject global fsck.mode=skip for Btrfs roots. That flag also skips
  # non-root filesystems such as the VFAT ESP, leaving dirty FAT volumes to be
  # mounted without repair on the next boot.
  grub_root_uses_btrfs || return 0
}

grub_os_prober_placeholder_map() {
  write_shell_config_var GRUB_DISABLE_OS_PROBER "${GRUB_OS_PROBER_DISABLED:-true}"
}

grub_display_placeholder_map() {
  write_shell_config_var GRUB_TERMINAL_INPUT "${GRUB_DISPLAY_TERMINAL_INPUT}"
  write_shell_config_var GRUB_TERMINAL_OUTPUT "${GRUB_DISPLAY_TERMINAL_OUTPUT}"
  write_shell_config_var GRUB_GFXMODE "${GRUB_DISPLAY_GFXMODE}"
  write_shell_config_var GRUB_GFXPAYLOAD_LINUX "${GRUB_DISPLAY_GFXPAYLOAD_LINUX}"
  write_shell_config_var GRUB_PRELOAD_MODULES "${GRUB_DISPLAY_PRELOAD_MODULES}"
}

grub_shared_target_path() {
  installer_repo_join_var DIR_HOOKS_SHARED_TARGET "$1"
}

render_target_grub_dropin() {
  template_name=$1
  target_path=$2

  render_target_asset "$(grub_shared_target_path "etc/default/grub.d/${template_name}")" "$target_path" 0644
}

render_target_grub_dropin_with_placeholder_map() {
  template_name=$1
  target_path=$2
  placeholder_map=$3

  render_target_asset_with_placeholder_map \
    "$(grub_shared_target_path "etc/default/grub.d/${template_name}")" \
    "$target_path" \
    0644 \
    "$placeholder_map"
}

sync_optional_target_grub_dropin() {
  flag_value=$1
  template_name=$2
  target_path=$3

  if [ -n "$flag_value" ]; then
    render_target_grub_dropin "$template_name" "$target_path"
  else
    remove_target_asset "$target_path"
  fi
}

path_mounted_fat_device_uuid() {
  path_value=$1
  best_source=
  best_mount=

  [ -n "$path_value" ] || return 1
  [ -e "$path_value" ] || return 1
  while IFS=' ' read -r mount_source mount_point _mount_fstype _mount_options _mount_rest || [ -n "${mount_source:-}" ]; do
    mount_point=$(printf '%s' "$mount_point" | sed 's/\\040/ /g')
    case "$path_value" in
      "$mount_point"|"$mount_point"/*)
        if [ "${#mount_point}" -gt "${#best_mount}" ]; then
          best_source=$mount_source
          best_mount=$mount_point
        fi
        ;;
    esac
  done </proc/mounts

  case "$best_source" in
    /dev/*) ;;
    *) return 1 ;;
  esac
  case "$(blkid -s TYPE -o value "$best_source" 2>/dev/null || true)" in
    vfat|fat|fat12|fat16|fat32) ;;
    *) return 1 ;;
  esac
  blkid -s UUID -o value "$best_source" 2>/dev/null
}

installer_rescue_usb_search_uuid() {
  if [ -n "${INSTALLER_RESCUE_USB_SEARCH_UUID:-}" ]; then
    printf '%s\n' "$INSTALLER_RESCUE_USB_SEARCH_UUID"
    return 0
  fi

  for candidate_path in \
    "${INSTALLER_SEED_FILE_BASE:-}" \
    "${SEED_FILE_BASE:-}" \
    "${INSTALLER_SEED_BASE:-}" \
    "${SEED_BASE:-}" \
    /media/usb \
    /cdrom
  do
    [ -n "$candidate_path" ] || continue
    case "$candidate_path" in
      /*) ;;
      *) continue ;;
    esac
    rescue_uuid=$(path_mounted_fat_device_uuid "$candidate_path" 2>/dev/null || true)
    [ -n "$rescue_uuid" ] || continue
    INSTALLER_RESCUE_USB_SEARCH_UUID=$rescue_uuid
    printf '%s\n' "$rescue_uuid"
    return 0
  done

  INSTALLER_RESCUE_USB_SEARCH_UUID=
  printf '\n'
}

secure_boot_config_placeholder_map() {
  write_shell_config_var SECURE_BOOT_STATE_MODE "$secure_boot_state_mode"
  write_shell_config_var SECURE_BOOT_STATE_MOUNTPOINT "${DIR_VAR_LIB_SHSIGNED}"
  write_shell_config_var SECURE_BOOT_STATE_DIR "${DIR_SECURE_BOOT_STATE}"
  write_shell_config_var SECURE_BOOT_LUKS_DEVICE "$secure_boot_luks_device"
  write_shell_config_var SECURE_BOOT_LUKS_NAME "$secure_boot_luks_name"
  write_shell_config_var SECURE_BOOT_LUKS_MAPPER "$secure_boot_luks_mapper"
  write_shell_config_var SECURE_BOOT_STATE_MOUNT_OPTS "$secure_boot_state_mount_opts"
  write_shell_config_var SECURE_BOOT_MOK_KEY "${FILE_SECURE_BOOT_MOK_KEY}"
  write_shell_config_var SECURE_BOOT_MOK_CERT_PEM "${FILE_SECURE_BOOT_MOK_CERT_PEM}"
  write_shell_config_var SECURE_BOOT_MOK_CERT_DER "${FILE_SECURE_BOOT_MOK_CERT_DER}"
  write_shell_config_var SECURE_BOOT_MOK_ENROLLMENT_DIR "${DIR_SECURE_BOOT_ENROLLMENT_ESP}"
  write_shell_config_var SECURE_BOOT_MOK_ENROLLMENT_CERT "${FILE_SECURE_BOOT_MOK_CERT_DER_ESP}"
  write_shell_config_var SECURE_BOOT_OPENSSL_CONFIG "${FILE_SECURE_BOOT_OPENSSL_CONFIG}"
  write_shell_config_var SECURE_BOOT_MOK_COMMON_NAME "${SECURE_BOOT_MOK_COMMON_NAME}"
  write_shell_config_var SECURE_BOOT_MOK_COUNTRY "${SECURE_BOOT_MOK_COUNTRY}"
  write_shell_config_var SECURE_BOOT_MOK_STATE "${SECURE_BOOT_MOK_STATE}"
  write_shell_config_var SECURE_BOOT_MOK_LOCALITY "${SECURE_BOOT_MOK_LOCALITY}"
  write_shell_config_var SECURE_BOOT_MOK_ORGANIZATION "${SECURE_BOOT_MOK_ORGANIZATION}"
  write_shell_config_var SECURE_BOOT_MOK_ORG_UNIT "${SECURE_BOOT_MOK_ORG_UNIT}"
  write_shell_config_var SECURE_BOOT_MOK_EMAIL "${SECURE_BOOT_MOK_EMAIL}"
  write_shell_config_var SECURE_BOOT_MOK_RSA_BITS "${SECURE_BOOT_MOK_RSA_BITS}"
  write_shell_config_var SECURE_BOOT_MOK_VALID_DAYS "${SECURE_BOOT_MOK_VALID_DAYS}"
  write_shell_config_var ACCOUNT_USERNAME "${ACCOUNT_USERNAME}"
  write_shell_config_var SECURE_BOOT_DKMS_CONF "${FILE_DKMS_FRAMEWORK_SECURE_BOOT}"
  write_shell_config_var SECURE_BOOT_SIGN_MODULE_HELPER "${FILE_SIGN_MODULE_HELPER}"
}

write_target_grub_dropins() {
  apply_btrfs_root_initramfs_fsck_policy
  render_target_grub_dropin 05-bootprofiles.cfg.tmpl "${DIR_GRUB_DEFAULT}/05-bootprofiles.cfg"
  render_target_grub_dropin_with_placeholder_map 07-display.cfg.tmpl "${FILE_GRUB_DISPLAY_CFG}" grub_display_placeholder_map
  if [ "${DUALBOOT_ENABLED:-false}" = "true" ]; then
    GRUB_OS_PROBER_DISABLED=false
  else
    GRUB_OS_PROBER_DISABLED=true
  fi
  render_target_grub_dropin_with_placeholder_map 50-os-prober.cfg.tmpl "${DIR_GRUB_DEFAULT}/50-os-prober.cfg" grub_os_prober_placeholder_map
  unset GRUB_OS_PROBER_DISABLED
  render_target_grub_dropin 10-rootfs.cfg.tmpl "${DIR_GRUB_DEFAULT}/10-rootfs.cfg"
  render_target_grub_dropin 15-initramfs.cfg.tmpl "${DIR_GRUB_DEFAULT}/15-initramfs.cfg"
  sync_optional_target_grub_dropin "${GRUB_NVME_FLAGS:-}" 20-nvme.cfg.tmpl "${DIR_GRUB_DEFAULT}/20-nvme.cfg"
  sync_optional_target_grub_dropin "${GRUB_SYSTEMD_MASK_FLAGS:-}" 25-systemd-mask.cfg.tmpl "${DIR_GRUB_DEFAULT}/25-systemd-mask.cfg"
  render_target_grub_dropin 30-cgroup.cfg.tmpl "${DIR_GRUB_DEFAULT}/30-cgroup.cfg"
  render_target_grub_dropin 35-security-core.cfg.tmpl "${DIR_GRUB_DEFAULT}/35-security-core.cfg"
  sync_optional_target_grub_dropin "${GRUB_BLACKLIST_FLAGS:-}" 40-blacklist.cfg.tmpl "${DIR_GRUB_DEFAULT}/40-blacklist.cfg"
  sync_optional_target_grub_dropin "${GRUB_VFIO_FLAGS:-}" 42-vfio.cfg.tmpl "${DIR_GRUB_DEFAULT}/42-vfio.cfg"
  render_target_grub_dropin 45-memory-core.cfg.tmpl "${DIR_GRUB_DEFAULT}/45-memory-core.cfg"
  render_target_grub_dropin 60-hardening.cfg.tmpl "${DIR_GRUB_DEFAULT}/60-hardening.cfg"
  sync_optional_target_grub_dropin "${GRUB_ASPM_FLAGS:-}" 70-aspm.cfg.tmpl "${DIR_GRUB_DEFAULT}/70-aspm.cfg"
}

install_target_bootprofile_assets() {
  render_target_template "$TMP_ENV_DIR/bootprofile-apply.tmpl" "/target${FILE_BOOTPROFILE_APPLY}" 0755
  render_target_template "$TMP_ENV_DIR/bootprofile-apply.service.tmpl" "/target${FILE_BOOTPROFILE_SERVICE}" 0644

  install -d -m 0755 "/target${DIR_SYSTEMD_SYSTEM}/sysinit.target.wants"
  ln -sf "../$(basename "${FILE_BOOTPROFILE_SERVICE}")" \
    "/target${DIR_SYSTEMD_SYSTEM}/sysinit.target.wants/$(basename "${FILE_BOOTPROFILE_SERVICE}")"
}

verify_target_bootprofile_core_staging() {
  require_in_target "bootprofile verification"

  # shellcheck disable=SC2016
  run_in_target "verify staged core bootprofile and GRUB payload" /bin/sh -c '
set -eu
bootprofile_apply=$1
bootprofile_service=$2
grub_defaults_dir=$3
grub_defaults_file=$4
grub_display_cfg=$5

[ -x "$bootprofile_apply" ]
[ -r "$bootprofile_service" ]
[ -r "$grub_defaults_dir/05-bootprofiles.cfg" ]
[ -r "$grub_display_cfg" ]
[ -r "$grub_defaults_dir/10-rootfs.cfg" ]
[ -r "$grub_defaults_dir/15-initramfs.cfg" ]
[ -r "$grub_defaults_dir/30-cgroup.cfg" ]
[ -r "$grub_defaults_dir/35-security-core.cfg" ]
[ -r "$grub_defaults_dir/45-memory-core.cfg" ]
[ -r "$grub_defaults_dir/50-os-prober.cfg" ]
[ -r "$grub_defaults_dir/60-hardening.cfg" ]
[ -r "$grub_defaults_file" ]
[ -L /etc/systemd/system/sysinit.target.wants/bootprofile-apply.service ]
' sh \
    "${FILE_BOOTPROFILE_APPLY}" \
    "${FILE_BOOTPROFILE_SERVICE}" \
    "${DIR_GRUB_DEFAULT}" \
    /etc/default/grub \
    "${FILE_GRUB_DISPLAY_CFG}"
}

set_target_grub_default_entry() {
  # shellcheck disable=SC2016
  run_in_target "set GRUB defaults in /etc/default/grub" /bin/sh -c '
set -eu
file=/etc/default/grub
grub_default=$1
tmp=$(mktemp)
trap "rm -f \"$tmp\"" EXIT HUP INT TERM

if [ -f "$file" ]; then
  default_updated=0
  timeout_style_updated=0
  timeout_updated=0
  recordfail_timeout_updated=0
  disable_recovery_updated=0
  disable_submenu_updated=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      GRUB_DEFAULT=*)
        [ "$default_updated" -eq 0 ] && printf 'GRUB_DEFAULT="%s"\n' "$grub_default"
        default_updated=1
        continue
        ;;
      GRUB_TIMEOUT_STYLE=*)
        [ "$timeout_style_updated" -eq 0 ] && printf 'GRUB_TIMEOUT_STYLE=menu\n'
        timeout_style_updated=1
        continue
        ;;
      GRUB_TIMEOUT=*)
        [ "$timeout_updated" -eq 0 ] && printf 'GRUB_TIMEOUT=-1\n'
        timeout_updated=1
        continue
        ;;
      GRUB_RECORDFAIL_TIMEOUT=*)
        [ "$recordfail_timeout_updated" -eq 0 ] && printf 'GRUB_RECORDFAIL_TIMEOUT=-1\n'
        recordfail_timeout_updated=1
        continue
        ;;
      GRUB_DISABLE_RECOVERY=*)
        [ "$disable_recovery_updated" -eq 0 ] && printf 'GRUB_DISABLE_RECOVERY=true\n'
        disable_recovery_updated=1
        continue
        ;;
      GRUB_DISABLE_SUBMENU=*)
        [ "$disable_submenu_updated" -eq 0 ] && printf 'GRUB_DISABLE_SUBMENU=y\n'
        disable_submenu_updated=1
        continue
        ;;
    esac
    printf '%s\n' "$line"
  done <"$file" >"$tmp"
  [ "$default_updated" -eq 1 ] || printf 'GRUB_DEFAULT="%s"\n' "$grub_default" >>"$tmp"
  [ "$timeout_style_updated" -eq 1 ] || printf 'GRUB_TIMEOUT_STYLE=menu\n' >>"$tmp"
  [ "$timeout_updated" -eq 1 ] || printf 'GRUB_TIMEOUT=-1\n' >>"$tmp"
  [ "$recordfail_timeout_updated" -eq 1 ] || printf 'GRUB_RECORDFAIL_TIMEOUT=-1\n' >>"$tmp"
  [ "$disable_recovery_updated" -eq 1 ] || printf 'GRUB_DISABLE_RECOVERY=true\n' >>"$tmp"
  [ "$disable_submenu_updated" -eq 1 ] || printf 'GRUB_DISABLE_SUBMENU=y\n' >>"$tmp"
else
  {
    printf "GRUB_DEFAULT=\"%s\"\n" "$grub_default"
    printf "GRUB_TIMEOUT_STYLE=menu\n"
    printf "GRUB_TIMEOUT=-1\n"
    printf "GRUB_RECORDFAIL_TIMEOUT=-1\n"
    printf "GRUB_DISABLE_RECOVERY=true\n"
    printf "GRUB_DISABLE_SUBMENU=y\n"
  } >"$tmp"
fi

install -m 0644 "$tmp" "$file"
' sh "${GRUB_DEFAULT_ENTRY}"
}

disable_stock_kernel_menu() {
  target_grub_dir="/target${DIR_GRUB_SCRIPTS}"
  [ -d "$target_grub_dir" ] || return 0

  for path in "$target_grub_dir"/*; do
    [ -e "$path" ] || continue
    script_name=${path##*/}
    case "$script_name" in
      00_header|40_custom|README)
        continue
        ;;
    esac
    if [ -f "$path" ] && [ -x "$path" ]; then
      chmod 0644 "$path"
    fi
  done

  if [ -e "${target_grub_dir}/40_custom" ] && [ ! -x "${target_grub_dir}/40_custom" ]; then
    installer_fatal "managed GRUB 40_custom generator is not executable"
  fi
  for script_name in 05_debian_theme 10_linux 20_linux_xen 25_bli 30_os-prober 30_uefi-firmware 41_custom 41_snapshots-btrfs; do
    if [ -e "${target_grub_dir}/${script_name}" ] && [ -x "${target_grub_dir}/${script_name}" ]; then
      installer_fatal "unmanaged GRUB generator is still executable: ${DIR_GRUB_SCRIPTS}/${script_name}"
    fi
  done
}

target_efivars_are_available() {
  test_in_target /bin/sh -c '
set -eu
[ -d /sys/firmware/efi/efivars ]
grep -qs " /sys/firmware/efi/efivars " /proc/mounts
' sh
}

target_pending_mok_request_exists() {
  # shellcheck disable=SC2016
  test_in_target /bin/sh -c '
set -eu
new_list=$(mokutil --list-new 2>/dev/null || true)
delete_list=$(mokutil --list-delete 2>/dev/null || true)
printf "%s\n%s\n" "$new_list" "$delete_list" | grep -F -q "Fingerprint:"
' sh
}

queue_target_secure_boot_mok_import_strict() {
  efivars_bind_mounted=false

  if ! target_efivars_are_available; then
    [ -d /sys/firmware/efi/efivars ] || installer_fatal "EFI variable access is unavailable in the installer; cannot queue Secure Boot MOK import"
    install -d -m 0755 /target/sys/firmware/efi/efivars
    info "binding installer efivars into target for mokutil"
    if ! mount --bind /sys/firmware/efi/efivars /target/sys/firmware/efi/efivars; then
      installer_fatal "failed to bind installer efivars into target for Secure Boot MOK import"
    fi
    efivars_bind_mounted=true
    target_efivars_are_available || installer_fatal "bound efivars are not visible inside the target; cannot queue Secure Boot MOK import"
  fi

  if ! attempt_in_target "queue Secure Boot MOK import without installer prompt" "${FILE_SECURE_BOOT_TOOL}" install-mok; then
    if [ "$efivars_bind_mounted" = "true" ] && ! umount /target/sys/firmware/efi/efivars; then
      installer_error "failed to unmount temporary target efivars bind after failed MOK import"
    fi
    installer_fatal "failed to queue Secure Boot MOK import automatically"
  fi

  if target_pending_mok_request_exists; then
    queue_target_grub_mok_enrollment_boot
  fi

  if [ "$efivars_bind_mounted" = "true" ]; then
    if ! umount /target/sys/firmware/efi/efivars; then
      installer_fatal "failed to unmount temporary target efivars bind after MOK import"
    fi
  fi
}

repair_target_secure_boot_removable_loader() {
  # shellcheck disable=SC2016
  run_in_target "ensure removable Secure Boot fallback loader uses shim" /bin/sh -c '
set -eu
esp_dir=${1%/}
shim_path=$2
removable_path=$3
shim_loader="${esp_dir}${shim_path}"
removable_loader="${esp_dir}${removable_path}"

[ -f "$shim_loader" ] || {
  printf "missing signed shim loader: %s\n" "$shim_loader" >&2
  exit 1
}
install -d -m 0755 "$(dirname "$removable_loader")"
if [ ! -f "$removable_loader" ] || ! cmp -s "$shim_loader" "$removable_loader"; then
  install -m 0644 "$shim_loader" "$removable_loader"
fi
cmp -s "$shim_loader" "$removable_loader" || {
  printf "removable Secure Boot loader does not match shim: %s\n" "$removable_loader" >&2
  exit 1
}
' sh \
    "${DIR_BOOT_EFI}" \
    "${INSTALLER_GRUB_SHIM_EFI_PATH}" \
    "${INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH}"
}

repair_target_secure_boot_nvram_entry() {
  # shellcheck disable=SC2016
  run_in_target "ensure firmware boot entry uses shim" /bin/sh -c '
set -eu
disk=$1
efi_part=$2
shim_path=$3
label=debian

find_shim_boot_entry() {
  loader_lower=$1
  efibootmgr -v | while IFS= read -r line; do
    lower_line=$(printf "%s\n" "$line" | tr "[:upper:]" "[:lower:]")
    case "$lower_line" in
      *"file(${loader_lower})"*)
        entry=$(printf "%s\n" "$line" | sed -n "s/^Boot\\([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]\\).*/\\1/p")
        [ -n "$entry" ] || continue
        printf "%s\n" "$entry"
        return 0
        ;;
    esac
  done
}

command -v efibootmgr >/dev/null 2>&1 || {
  printf "efibootmgr is unavailable; cannot force firmware boot through shim\n" >&2
  exit 1
}
[ -d /sys/firmware/efi/efivars ] || {
  printf "target efivars are unavailable; cannot force firmware boot through shim\n" >&2
  exit 1
}
grep -qs " /sys/firmware/efi/efivars " /proc/mounts || {
  printf "target efivars are not mounted; cannot force firmware boot through shim\n" >&2
  exit 1
}
[ -b "$disk" ] || {
  printf "install disk is missing inside target: %s\n" "$disk" >&2
  exit 1
}
[ -b "$efi_part" ] || {
  printf "EFI partition is missing inside target: %s\n" "$efi_part" >&2
  exit 1
}

part_num=$(lsblk -n -o PARTN -- "$efi_part" 2>/dev/null | sed -n '/./{p;q;}')
[ -n "$part_num" ] || {
  printf "unable to resolve EFI partition number for %s\n" "$efi_part" >&2
  exit 1
}
loader=$(printf "%s\n" "$shim_path" | sed "s#/#\\\\#g")
loader_lower=$(printf "%s\n" "$loader" | tr "[:upper:]" "[:lower:]")

entry_id=$(find_shim_boot_entry "$loader_lower" | head -n 1 || true)
if [ -z "$entry_id" ]; then
  efibootmgr --create --disk "$disk" --part "$part_num" --label "$label" --loader "$loader" >/dev/null
  entry_id=$(find_shim_boot_entry "$loader_lower" | head -n 1 || true)
fi
[ -n "$entry_id" ] || {
  printf "failed to create or find shim firmware boot entry for %s\n" "$loader" >&2
  exit 1
}

boot_order=$(efibootmgr | sed -n "s/^BootOrder:[[:space:]]*//p" | head -n 1)
entry_lower=$(printf "%s\n" "$entry_id" | tr "[:upper:]" "[:lower:]")
new_order=$entry_id
old_ifs=$IFS
IFS=,
for existing_entry in $boot_order; do
  existing_entry=$(printf "%s\n" "$existing_entry" | tr -d "[:space:]")
  [ -n "$existing_entry" ] || continue
  existing_lower=$(printf "%s\n" "$existing_entry" | tr "[:upper:]" "[:lower:]")
  [ "$existing_lower" = "$entry_lower" ] && continue
  new_order="${new_order},${existing_entry}"
done
IFS=$old_ifs
efibootmgr --bootorder "$new_order" >/dev/null
efibootmgr --bootnext "$entry_id" >/dev/null
efibootmgr | grep -E -i -q "^BootNext:[[:space:]]*${entry_id}$"
' sh \
    "${DEV_INSTALL_DISK}" \
    "${DEV_PART_EFI}" \
    "${INSTALLER_GRUB_SHIM_EFI_PATH}"
}

queue_target_grub_mok_enrollment_boot() {
  # shellcheck disable=SC2016
  run_in_target "queue one-shot GRUB boot into MokManager" /bin/sh -c '
set -eu
mok_entry_id=$1

command -v grub-reboot >/dev/null 2>&1 || {
  printf "grub-reboot is unavailable; cannot force first boot into MokManager\n" >&2
  exit 1
}
[ -s /boot/grub/grubenv ] || {
  grub-editenv /boot/grub/grubenv create
}
grub-reboot "$mok_entry_id"
grub-editenv /boot/grub/grubenv list | grep -F -q "next_entry=${mok_entry_id}"
' sh installer-mok-enrollment
}

require_target_grub_installed() {
  # shellcheck disable=SC2016
  if ! test_in_target /bin/sh -c '
set -eu
packages=$1
test -x /usr/sbin/grub-install
[ -x /usr/sbin/update-grub ] || [ -x /usr/sbin/grub-mkconfig ]
for pkg in $packages; do
  dpkg-query -W "$pkg" >/dev/null 2>&1
done
' sh "${INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES}"; then
    installer_fatal "target Secure Boot GRUB and shim packages are not fully installed before profile installation"
  fi
}

prepare_target_secure_boot_runtime() {
  if [ "${TARGET_SECURE_BOOT_RUNTIME_PREPARED:-0}" = 1 ]; then
    return 0
  fi
  run_in_target "prepare Secure Boot keypair and DKMS config" "${FILE_SECURE_BOOT_TOOL}" prepare
  TARGET_SECURE_BOOT_RUNTIME_PREPARED=1
}

load_target_boot_tool_state() {
  if [ "${TARGET_BOOT_TOOL_STATE_LOADED:-0}" = 1 ]; then
    return 0
  fi

  require_in_target "target boot tool availability detection"
  TARGET_HAS_UPDATE_INITRAMFS=0

  target_boot_tool_state=$(
    capture_in_target "detect target boot tool availability" /bin/sh -c '
set -eu

check_tool() {
  tool_path=$1
  if [ -x "$tool_path" ]; then
    printf "1\n"
  else
    printf "0\n"
  fi
}

printf "TARGET_HAS_UPDATE_INITRAMFS=%s\n" "$(check_tool /usr/sbin/update-initramfs)"
' sh
  )

  while IFS='=' read -r state_name state_value || [ -n "${state_name:-}" ]; do
    [ -n "${state_name:-}" ] || continue
    case "$state_name:$state_value" in
      TARGET_HAS_UPDATE_INITRAMFS:0|TARGET_HAS_UPDATE_INITRAMFS:1)
        eval "$state_name=$state_value"
        ;;
      *)
        installer_fatal "invalid target boot tool state: ${state_name}=${state_value}"
        ;;
    esac
  done <<EOF
$target_boot_tool_state
EOF

  TARGET_BOOT_TOOL_STATE_LOADED=1
}

ensure_target_dualboot_os_prober_package() {
  [ "${DUALBOOT_ENABLED:-false}" = "true" ] || return 0

  if ! installer_word_list_contains "${INSTALLER_PKGSEL_INCLUDE:-}" os-prober; then
    INSTALLER_PKGSEL_INCLUDE="${INSTALLER_PKGSEL_INCLUDE:+${INSTALLER_PKGSEL_INCLUDE} }os-prober"
  fi

  if test_in_target test -x /usr/bin/os-prober; then
    return 0
  fi

  installer_warn "addon/dualboot selected but /usr/bin/os-prober is missing in target; repairing package state"
  prepare_target_volatile_dirs_for_apt
  run_in_target "refresh apt metadata before dualboot os-prober repair" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      update
  run_in_target "install dualboot os-prober package" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y install --no-install-recommends os-prober

  TARGET_BOOT_TOOL_STATE_LOADED=0
}

require_target_dualboot_os_prober_package() {
  [ "${DUALBOOT_ENABLED:-false}" = "true" ] || return 0
  ensure_target_dualboot_os_prober_package
  test_in_target test -x /usr/bin/os-prober || \
    installer_fatal "/usr/bin/os-prober is missing in target after repair; GRUB cannot probe other operating systems automatically"
}

resolve_target_grub_config_command() {
  if test_in_target test -x /usr/sbin/update-grub; then
    printf '%s\n' update-grub
    return 0
  fi
  if test_in_target test -x /usr/sbin/grub-mkconfig; then
    printf '%s\n' grub-mkconfig
    return 0
  fi
  return 1
}

run_target_grub_config_update() {
  grub_config_command=$(resolve_target_grub_config_command) || \
    installer_fatal "neither /usr/sbin/update-grub nor /usr/sbin/grub-mkconfig is available in target"
  case "$grub_config_command" in
    update-grub)
      run_in_target "update GRUB configuration" /usr/sbin/update-grub
      ;;
    grub-mkconfig)
      run_in_target "generate GRUB configuration" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
      ;;
    *)
      installer_fatal "unsupported target GRUB config command: ${grub_config_command}"
      ;;
  esac
}

install_target_secure_boot_target_packages() {
  # shellcheck disable=SC2086
  set -- $INSTALLER_SECURE_BOOT_TARGET_PACKAGES
  [ "$#" -ge 1 ] || installer_fatal "selected Secure Boot target package set is empty"
  prepare_target_volatile_dirs_for_apt
  run_in_target "install selected Secure Boot target packages" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y install --no-install-recommends "$@"
}

verify_target_secure_boot_target_packages() {
  installer_info "skipping Secure Boot package verification; package installation remains responsible for missing packages"
}

reinstall_target_grub_boot_chain_packages() {
  # shellcheck disable=SC2086
  set -- $INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES
  [ "$#" -ge 1 ] || installer_fatal "selected GRUB EFI boot chain package set is empty"
  prepare_target_volatile_dirs_for_apt
  run_in_target "reinstall selected GRUB EFI boot chain packages on the restored ESP" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y install --reinstall --no-install-recommends "$@"
}

installer_canonical_device_path() {
  readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"
}

installer_same_device_path() {
  installer_left=$(installer_canonical_device_path "$1")
  installer_right=$(installer_canonical_device_path "$2")
  [ "$installer_left" = "$installer_right" ]
}

installer_device_fs_type() {
  command -v blkid >/dev/null 2>&1 || return 1
  blkid -s TYPE -o value "$1" 2>/dev/null || true
}

installer_device_fs_label() {
  command -v blkid >/dev/null 2>&1 || return 1
  blkid -s LABEL -o value "$1" 2>/dev/null || true
}

installer_udev_settle() {
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || warn "udevadm settle failed while refreshing device state"
  fi
}

installer_wipe_block_device() {
  if command -v swapoff >/dev/null 2>&1; then
    swapoff "$1" >/dev/null 2>&1 || true
  fi
  if command -v wipefs >/dev/null 2>&1; then
    wipefs -a -f "$1" >/dev/null 2>&1 || true
  fi
}

installer_log_command_failure() {
  failure_prefix=$1
  failure_file=$2

  [ -s "$failure_file" ] || return 0
  sed "s/^/[${failure_prefix}] /" "$failure_file" >&2 || true
}

installer_ensure_ext4_filesystem() {
  dev=$1
  opts=$2
  label=$3

  ensure_installer_command_logged blkid util-linux-udeb
  ensure_installer_command_logged mkfs.ext4 e2fsprogs-udeb

  current_type=$(installer_device_fs_type "$dev")
  current_label=$(installer_device_fs_label "$dev")
  if [ "$current_type" = "ext4" ] && [ "$current_label" = "$label" ]; then
    return 0
  fi

  installer_wipe_block_device "$dev"
  mkfs_err=$(installer_runtime_temp_log_path secure-boot-mkfs-ext4.log)
  info "formatting Secure Boot state mapper ${dev} as ext4"
  # shellcheck disable=SC2086
  if ! mkfs.ext4 $opts "$dev" >"$mkfs_err" 2>&1; then
    installer_log_command_failure "mkfs.ext4" "$mkfs_err"
    rm -f "$mkfs_err"
    fatal "failed to format Secure Boot state mapper ${dev} as ext4"
  fi
  rm -f "$mkfs_err"
  installer_udev_settle
}

installer_find_open_luks_mapping_for_device() {
  installer_dev=$1

  command -v cryptsetup >/dev/null 2>&1 || return 1

  for installer_mapper_path in /dev/mapper/*; do
    [ -b "$installer_mapper_path" ] || continue
    installer_mapper_name=${installer_mapper_path##*/}
    installer_real_dev=$(cryptsetup status "$installer_mapper_name" 2>/dev/null |
      sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | sed -n '1p')
    [ -n "$installer_real_dev" ] || continue
    if installer_same_device_path "$installer_dev" "$installer_real_dev"; then
      printf '%s\n' "$installer_mapper_path"
      return 0
    fi
  done

  return 1
}

installer_active_secure_boot_luks_mapper() {
  if [ -b "$LUKS_MAPPER_VAR_LIB_SHSIGNED" ]; then
    printf '%s\n' "$LUKS_MAPPER_VAR_LIB_SHSIGNED"
    return 0
  fi

  installer_find_open_luks_mapping_for_device "$DEV_PART_VAR_LIB_SHSIGNED"
}

open_luks_mapping_with_passphrase() {
  dev=$1
  mapper_name=$2
  passphrase=$3

  ensure_installer_command_logged cryptsetup cryptsetup-udeb
  if command -v modprobe >/dev/null 2>&1; then
    modprobe dm_mod >/dev/null 2>&1 || true
    modprobe dm_crypt >/dev/null 2>&1 || true
  fi

  ACTIVE_TARGET_SECURE_BOOT_MAPPER=$(installer_active_secure_boot_luks_mapper || true)
  if [ -n "$ACTIVE_TARGET_SECURE_BOOT_MAPPER" ]; then
    installer_ensure_ext4_filesystem "$ACTIVE_TARGET_SECURE_BOOT_MAPPER" "$MKFS_EXT4_VAR_LIB_SHSIGNED_OPTS" "$FS_LABEL_VAR_LIB_SHSIGNED"
    return 0
  fi

  if ! cryptsetup isLuks "$dev" >/dev/null 2>&1; then
    installer_wipe_block_device "$dev"
    luks_format_err=$(installer_runtime_temp_log_path secure-boot-luks-format.log)
    info "formatting Secure Boot state partition ${dev} as LUKS2"
    # shellcheck disable=SC2086
    if ! printf '%s' "$passphrase" | cryptsetup luksFormat --batch-mode --key-file - $CRYPTSETUP_LUKS_VAR_LIB_SHSIGNED_OPTS "$dev" >"$luks_format_err" 2>&1; then
      installer_log_command_failure "cryptsetup:luksFormat" "$luks_format_err"
      rm -f "$luks_format_err"
      fatal "failed to format Secure Boot state partition ${dev} as LUKS2"
    fi
    rm -f "$luks_format_err"
    installer_udev_settle
  fi

  luks_open_err=$(installer_runtime_temp_log_path secure-boot-luks-open.log)
  info "opening Secure Boot LUKS mapper ${mapper_name}"
  if ! printf '%s' "$passphrase" | cryptsetup luksOpen --batch-mode --key-file - "$dev" "$mapper_name" >"$luks_open_err" 2>&1; then
    installer_log_command_failure "cryptsetup:luksOpen" "$luks_open_err"
    rm -f "$luks_open_err"
    fatal "failed to open Secure Boot LUKS mapper ${mapper_name}"
  fi
  rm -f "$luks_open_err"
  installer_udev_settle
  ACTIVE_TARGET_SECURE_BOOT_MAPPER="$LUKS_MAPPER_VAR_LIB_SHSIGNED"
  installer_ensure_ext4_filesystem "$ACTIVE_TARGET_SECURE_BOOT_MAPPER" "$MKFS_EXT4_VAR_LIB_SHSIGNED_OPTS" "$FS_LABEL_VAR_LIB_SHSIGNED"
}

ensure_target_secure_boot_state_mount() {
  secure_boot_state_mode=$(target_secure_boot_state_mode)
  mountpoint="/target${DIR_VAR_LIB_SHSIGNED}"
  mapper_path=

  target_is_mounted || fatal "/target is not mounted before Secure Boot state activation"

  case "$secure_boot_state_mode" in
    direct)
      install -d -m 0700 "$mountpoint"
      install -d -m 0700 "/target${DIR_SECURE_BOOT_STATE}"
      return 0
      ;;
    luks)
      validate_target_secure_boot_luks_contract
      ;;
    *)
      fatal "unsupported Secure Boot state mode: ${secure_boot_state_mode}"
      ;;
  esac

  [ -b "${DEV_PART_VAR_LIB_SHSIGNED}" ] || fatal "Secure Boot state partition is missing: ${DEV_PART_VAR_LIB_SHSIGNED}"

  install -d -m 0700 "$mountpoint"
  open_luks_mapping_with_passphrase "${DEV_PART_VAR_LIB_SHSIGNED}" "${LUKS_NAME_VAR_LIB_SHSIGNED}" "${ACCOUNT_USERNAME}"
  mapper_path=${ACTIVE_TARGET_SECURE_BOOT_MAPPER:-$LUKS_MAPPER_VAR_LIB_SHSIGNED}
  ensure_target_mount "$mapper_path" "$mountpoint" ext4 "${MNT_VAR_LIB_SHSIGNED_OPTS}" "/var/lib/shim-signed"
  chmod 0700 "$mountpoint"
}

close_target_secure_boot_state() {
  secure_boot_state_mode=$(target_secure_boot_state_mode)
  mountpoint="/target${DIR_VAR_LIB_SHSIGNED}"
  active_mapper=

  case "$secure_boot_state_mode" in
    direct)
      install -d -m 0700 "$mountpoint"
      return 0
      ;;
    luks)
      validate_target_secure_boot_luks_contract
      ;;
    *)
      fatal "unsupported Secure Boot state mode: ${secure_boot_state_mode}"
      ;;
  esac

  active_mapper=$(installer_active_secure_boot_luks_mapper || true)
  if mounted_src=$(target_mount_source "$mountpoint"); then
    if [ -n "$active_mapper" ] && ! installer_same_device_path "$mounted_src" "$active_mapper"; then
      fatal "${mountpoint} is mounted from ${mounted_src}, expected ${active_mapper}"
    fi
    info "unmounting Secure Boot state partition"
    if ! umount "$mountpoint"; then
      fatal "failed to unmount ${mountpoint}"
    fi
    install -d -m 0700 "$mountpoint"
  fi

  active_mapper=${active_mapper:-$(installer_active_secure_boot_luks_mapper || true)}
  if [ -n "$active_mapper" ]; then
    active_mapper_name=${active_mapper##*/}
    ensure_installer_command_logged cryptsetup cryptsetup-udeb
    info "closing Secure Boot LUKS mapper ${active_mapper_name}"
    if ! cryptsetup close "$active_mapper_name"; then
      fatal "failed to close Secure Boot LUKS mapper ${active_mapper_name}"
    fi
  fi
}

remove_target_secure_boot_crypttab_entry() {
  secure_boot_state_mode=$(target_secure_boot_state_mode)
  crypttab="/target/etc/crypttab"

  [ "$secure_boot_state_mode" = "luks" ] || return 0
  validate_target_secure_boot_luks_contract

  outer_uuid=$(blkid -s UUID -o value "${DEV_PART_VAR_LIB_SHSIGNED}" 2>/dev/null || true)

  [ -f "$crypttab" ] || return 0

  tmp=$(mktemp) || fatal "unable to create temporary crypttab file"

  uuid_ref=
  [ -n "$outer_uuid" ] && uuid_ref="UUID=${outer_uuid}"
  : >"$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed_line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$trimmed_line" in
      ''|'#'*)
        printf '%s\n' "$line" >>"$tmp"
        continue
        ;;
    esac
    # shellcheck disable=SC2086
    set -- $trimmed_line
    [ "${1:-}" = "$LUKS_NAME_VAR_LIB_SHSIGNED" ] && continue
    [ "${2:-}" = "${DEV_PART_VAR_LIB_SHSIGNED}" ] && continue
    [ -n "$uuid_ref" ] && [ "${2:-}" = "$uuid_ref" ] && continue
    printf '%s\n' "$line" >>"$tmp"
  done <"$crypttab" || {
    rm -f "$tmp"
    fatal "failed to rewrite ${crypttab} while pruning Secure Boot auto-open entries"
  }

  if ! cmp -s "$tmp" "$crypttab"; then
    info "removing Secure Boot state crypttab auto-open entry"
    mv "$tmp" "$crypttab" || {
      rm -f "$tmp"
      fatal "failed to replace ${crypttab} after pruning Secure Boot auto-open entries"
    }
    chmod 0644 "$crypttab"
  else
    rm -f "$tmp"
  fi
}

install_target_mok_profile_aliases() {
  [ "$(target_secure_boot_state_mode)" = "luks" ] || return 0
  [ "${INSTALLER_HOST_VARIANT:-}" = desktop ] && return 0
  validate_target_ssh_user

  # shellcheck disable=SC2016
  run_in_target "install MOK LUKS aliases in target profile" /bin/sh -c '
set -eu
account_user=$1
account_home=$2
open_helper=$3
close_helper=$4
passwd_helper=$5
profile_path="${account_home}/.profile"
marker_begin="# Managed installer MOK LUKS aliases"
marker_end="# End managed installer MOK LUKS aliases"
tmp=$(mktemp)
trap "rm -f \"$tmp\"" EXIT HUP INT TERM

uid=$(id -u "$account_user")
gid=$(id -g "$account_user")

if [ ! -d "$account_home" ]; then
  install -d -m 0755 "$account_home"
fi
if [ ! -f "$profile_path" ]; then
  if [ -r /etc/skel/.profile ]; then
    install -m 0644 /etc/skel/.profile "$profile_path"
  else
    : >"$profile_path"
    chmod 0644 "$profile_path"
  fi
fi

skip=false
: >"$tmp"
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$line" = "$marker_begin" ]; then
    skip=true
    continue
  fi
  if [ "$line" = "$marker_end" ]; then
    skip=false
    continue
  fi
  [ "$skip" = true ] && continue
  printf '%s\n' "$line" >>"$tmp"
done <"$profile_path"

{
  cat "$tmp"
  printf "\n%s\n" "$marker_begin"
  printf "alias luks-mok-open='\''sudo %s'\''\n" "$open_helper"
  printf "alias luks-mok-close='\''sudo %s'\''\n" "$close_helper"
  printf "alias luks-mok-passwd='\''sudo %s'\''\n" "$passwd_helper"
  printf "%s\n" "$marker_end"
} >"$profile_path"

chown "$uid:$gid" "$profile_path"
chmod 0644 "$profile_path"
' sh \
    "$ACCOUNT_USERNAME" \
    "$ACCOUNT_HOME" \
    "${FILE_LUKS_MOK_OPEN_HELPER}" \
    "${FILE_LUKS_MOK_CLOSE_HELPER}" \
    "${FILE_LUKS_MOK_PASSWD_HELPER}"
}

target_secure_boot_state_mode() {
  if [ -n "${SECURE_BOOT_STATE_MODE:-}" ]; then
    printf '%s\n' "$SECURE_BOOT_STATE_MODE"
    return 0
  fi

  case "${HOOK_FAMILY:-}" in
    btrfs|vm) printf '%s\n' luks ;;
    *) printf '%s\n' direct ;;
  esac
}

validate_target_secure_boot_luks_contract() {
  [ -n "${DEV_PART_VAR_LIB_SHSIGNED:-}" ] || installer_fatal "SECURE_BOOT_STATE_MODE=luks requires DEV_PART_VAR_LIB_SHSIGNED to be defined"
  [ -n "${LUKS_NAME_VAR_LIB_SHSIGNED:-}" ] || installer_fatal "SECURE_BOOT_STATE_MODE=luks requires LUKS_NAME_VAR_LIB_SHSIGNED to be defined"
  [ -n "${LUKS_MAPPER_VAR_LIB_SHSIGNED:-}" ] || installer_fatal "SECURE_BOOT_STATE_MODE=luks requires LUKS_MAPPER_VAR_LIB_SHSIGNED to be defined"
  [ -n "${MNT_VAR_LIB_SHSIGNED_OPTS:-}" ] || installer_fatal "SECURE_BOOT_STATE_MODE=luks requires MNT_VAR_LIB_SHSIGNED_OPTS to be defined"
}

ensure_target_secure_boot_state_dirs() {
  install -d -m 0700 "/target${DIR_VAR_LIB_SHSIGNED}"
  install -d -m 0700 "/target${DIR_SECURE_BOOT_STATE}"
}

write_target_secure_boot_payloads() {
  secure_boot_state_mode=$(target_secure_boot_state_mode)
  case "$secure_boot_state_mode" in
    luks)
      validate_target_secure_boot_luks_contract
      secure_boot_luks_device=${DEV_PART_VAR_LIB_SHSIGNED}
      secure_boot_luks_name=${LUKS_NAME_VAR_LIB_SHSIGNED}
      secure_boot_luks_mapper=${LUKS_MAPPER_VAR_LIB_SHSIGNED}
      secure_boot_state_mount_opts=${MNT_VAR_LIB_SHSIGNED_OPTS}
      ;;
    direct)
      secure_boot_luks_device=${SECURE_BOOT_LUKS_DEVICE:-}
      secure_boot_luks_name=${SECURE_BOOT_LUKS_NAME:-}
      secure_boot_luks_mapper=${SECURE_BOOT_LUKS_MAPPER:-}
      secure_boot_state_mount_opts=${SECURE_BOOT_STATE_MOUNT_OPTS:-}
      ;;
    *)
      installer_fatal "unsupported Secure Boot state mode: ${secure_boot_state_mode}"
      ;;
  esac

  ensure_target_secure_boot_state_dirs
  render_target_asset_with_placeholder_map \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/default/secure-boot.conf.tmpl)" \
    "${FILE_SECURE_BOOT_CONFIG}" \
    0600 \
    secure_boot_config_placeholder_map

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/libexec/install-tools/secure-boot-tool.tmpl)" "${FILE_SECURE_BOOT_TOOL}" 0755
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/sign-module.tmpl)" "${FILE_SIGN_MODULE_HELPER}" 0755
  if [ "$secure_boot_state_mode" = luks ]; then
    render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/luks-mok-open.tmpl)" "${FILE_LUKS_MOK_OPEN_HELPER}" 0755
    render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/luks-mok-close.tmpl)" "${FILE_LUKS_MOK_CLOSE_HELPER}" 0755
    render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/luks-mok-passwd.tmpl)" "${FILE_LUKS_MOK_PASSWD_HELPER}" 0755
  fi
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/dkms/framework.conf.d/90-secure-boot.conf.tmpl)" "${FILE_DKMS_FRAMEWORK_SECURE_BOOT}" 0644
}

install_target_secure_boot_kernel_hooks() {
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/kernel/postinst.d/zz-sign-kernel.tmpl)" "${FILE_KERNEL_POSTINST_SIGN}" 0755
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/kernel/postrm.d/zz-sign-kernel-cleanup.tmpl)" "${FILE_KERNEL_POSTRM_SIGN}" 0755
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/kernel/header_postinst.d/zz-sign-kernel-headers.tmpl)" "${FILE_KERNEL_HEADER_POSTINST_SIGN}" 0755
}

ensure_target_secure_boot_packages() {
  require_in_target "Secure Boot package installation"
  install_target_secure_boot_target_packages
  verify_target_secure_boot_target_packages
  reinstall_target_grub_boot_chain_packages
  require_target_grub_installed
  efivars_bind_mounted=false
  set -- /usr/sbin/grub-install \
    "--target=${INSTALLER_GRUB_EFI_TARGET}" \
    --efi-directory=/boot/efi \
    --bootloader-id=debian \
    --uefi-secure-boot \
    --force-extra-removable
  if ! target_mount_source "/target/sys/firmware/efi/efivars" >/dev/null 2>&1; then
    if [ -d /sys/firmware/efi/efivars ]; then
      install -d -m 0755 /target/sys/firmware/efi/efivars
      info "binding installer efivars into target for grub-install"
      if ! mount --bind /sys/firmware/efi/efivars /target/sys/firmware/efi/efivars; then
        warn "failed to bind installer efivars into target for grub-install; retrying without NVRAM updates"
        set -- "$@" --no-nvram
      else
        efivars_bind_mounted=true
      fi
    else
      set -- "$@" --no-nvram
    fi
  fi
  if ! attempt_in_target "refresh signed GRUB EFI payload on the mounted ESP" "$@"; then
    case " $* " in
      *" --no-nvram "*)
        fatal "grub-install failed even after disabling NVRAM updates"
        ;;
      *)
        warn "grub-install with NVRAM updates failed; retrying with --no-nvram"
        set -- "$@" --no-nvram
        run_in_target "refresh signed GRUB EFI payload on the mounted ESP without NVRAM updates" "$@"
        ;;
    esac
  fi
  if [ "$efivars_bind_mounted" = true ]; then
    if ! umount /target/sys/firmware/efi/efivars; then
      warn "failed to unmount temporary target efivars bind after grub-install"
    fi
  fi
  repair_target_secure_boot_removable_loader
}

queue_target_secure_boot_mok_import() {
  queue_target_secure_boot_mok_import_strict
}

sign_target_installed_kernel_modules() {
  run_in_target "sign installed kernel modules before final initramfs refresh" "${FILE_SECURE_BOOT_TOOL}" sign-installed-modules
  TARGET_SECURE_BOOT_RUNTIME_PREPARED=1
}

repair_target_installed_kernels() {
  run_in_target "repair installed kernel signatures and initrds" "${FILE_SECURE_BOOT_TOOL}" repair-installed-kernels
  TARGET_SECURE_BOOT_RUNTIME_PREPARED=1
}

verify_target_secure_boot_staging() {
  secure_boot_state_mode=$(target_secure_boot_state_mode)
  case "$secure_boot_state_mode" in
    luks)
      verify_luks_open_helper=${FILE_LUKS_MOK_OPEN_HELPER}
      verify_luks_close_helper=${FILE_LUKS_MOK_CLOSE_HELPER}
      verify_luks_passwd_helper=${FILE_LUKS_MOK_PASSWD_HELPER}
      ;;
    direct)
      verify_luks_open_helper=
      verify_luks_close_helper=
      verify_luks_passwd_helper=
      ;;
    *)
      installer_fatal "unsupported Secure Boot state mode: ${secure_boot_state_mode}"
      ;;
  esac

  # shellcheck disable=SC2016
  run_in_target "verify staged Secure Boot payload" /bin/sh -c '
set -eu
fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}
state_mode=$1
tool=$2
config=$3
sign_helper=$4
open_helper=$5
close_helper=$6
passwd_helper=$7
dkms_conf=$8
postinst_hook=$9
postrm_hook=${10}
header_hook=${11}
key_path=${12}
cert_pem=${13}
cert_der=${14}
esp_mok_dir=${15}
esp_mok_cert=${16}
boot_chain_packages=${17}
esp_dir=${18}
shim_efi_path=${19}
grub_efi_path=${20}
mok_manager_efi_path=${21}
removable_boot_efi_path=${22}

[ -x "$tool" ]
[ -r "$config" ]
[ -x "$sign_helper" ]
case "$state_mode" in
  luks)
    [ -x "$open_helper" ]
    [ -x "$close_helper" ]
    [ -x "$passwd_helper" ]
    ;;
  direct)
    ;;
  *)
    fatal "unsupported Secure Boot state mode: $state_mode"
    ;;
esac
[ -r "$dkms_conf" ]
[ -x "$postinst_hook" ]
[ -x "$postrm_hook" ]
[ -x "$header_hook" ]
[ -r "$key_path" ]
[ -r "$cert_pem" ]
[ -r "$cert_der" ]
[ -d "$esp_mok_dir" ]
[ -r "$esp_mok_cert" ]
[ -f "$esp_dir$shim_efi_path" ]
[ -f "$esp_dir$grub_efi_path" ]
[ -f "$esp_dir$mok_manager_efi_path" ]
[ -f "$esp_dir$removable_boot_efi_path" ]
' sh \
    "$secure_boot_state_mode" \
    "${FILE_SECURE_BOOT_TOOL}" \
    "${FILE_SECURE_BOOT_CONFIG}" \
    "${FILE_SIGN_MODULE_HELPER}" \
    "$verify_luks_open_helper" \
    "$verify_luks_close_helper" \
    "$verify_luks_passwd_helper" \
    "${FILE_DKMS_FRAMEWORK_SECURE_BOOT}" \
    "${FILE_KERNEL_POSTINST_SIGN}" \
    "${FILE_KERNEL_POSTRM_SIGN}" \
    "${FILE_KERNEL_HEADER_POSTINST_SIGN}" \
    "${FILE_SECURE_BOOT_MOK_KEY}" \
    "${FILE_SECURE_BOOT_MOK_CERT_PEM}" \
    "${FILE_SECURE_BOOT_MOK_CERT_DER}" \
    "${DIR_SECURE_BOOT_ENROLLMENT_ESP}" \
    "${FILE_SECURE_BOOT_MOK_CERT_DER_ESP}" \
    "${INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES}" \
    "${DIR_BOOT_EFI}" \
    "${INSTALLER_GRUB_SHIM_EFI_PATH}" \
    "${INSTALLER_GRUB_BINARY_EFI_PATH}" \
    "${INSTALLER_GRUB_MOK_MANAGER_EFI_PATH}" \
    "${INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH}"
}

install_target_grub_profiles() {
  profile_script="/tmp/install-grub-profiles.$$"
  profile_script_target="/target${profile_script}"
  install -d -m 0755 "$(dirname "$profile_script_target")"
  command -v render_target_template >/dev/null 2>&1 || \
    installer_fatal "render_target_template is unavailable before GRUB profile installation"
  prepare_target_secure_boot_runtime
  render_target_template "${TMP_ENV_DIR}/grub-profiles" "$profile_script_target" 0755

  if ! attempt_in_target "install GRUB profile entries" /bin/sh "$profile_script" \
    "${DEV_PART_BOOT}" \
    "${DEV_PART_ROOT}" \
    "${DEV_PART_EFI}" \
    "${BOOTPROFILE_DEFAULT}" \
    "${BOOTPROFILE_PERFORMANCE}" \
    "${BOOTPROFILE_HARDENED}" \
    "${GRUB_ROOT_FLAGS}" \
    "${GRUB_INITRAMFS_FLAGS}" \
    "${GRUB_NVME_FLAGS:-}" \
    "${GRUB_CGROUP_FLAGS}" \
    "${GRUB_SECURITY_CORE_FLAGS}" \
    "${GRUB_BLACKLIST_FLAGS:-}" \
    "${GRUB_VFIO_FLAGS:-}" \
    "${GRUB_MEMORY_CORE_FLAGS}" \
    "${GRUB_HARDENING_FLAGS}" \
    "${GRUB_ASPM_FLAGS:-}" \
    "${GRUB_SYSTEMD_MASK_FLAGS:-}" \
    "${GRUB_PROFILE_DEFAULT_FLAGS}" \
    "${GRUB_PROFILE_PERFORMANCE_FLAGS}" \
    "${GRUB_PROFILE_HARDENED_FLAGS}" \
    "${FILE_SECURE_BOOT_MOK_CERT_DER}" \
    "${GRUB_DEFAULT_ENTRY}" \
    "$(installer_rescue_usb_search_uuid)" \
    "${GRUB_DISPLAY_GFXPAYLOAD_LINUX}" \
    "${DUALBOOT_ENABLED:-false}"; then
    rm -f "$profile_script_target"
    installer_fatal "failed to install GRUB profile entries"
  fi
  rm -f "$profile_script_target"
  disable_stock_kernel_menu
}

verify_grub_profile_entries() {
  grub_cfg=/target/boot/grub/grub.cfg
  custom_cfg=/target/boot/grub/custom.cfg
  grub_custom_script="/target${DIR_GRUB_SCRIPTS}/40_custom"
  grub_defaults=/target/etc/default/grub
  grub_dropin="/target${DIR_GRUB_DEFAULT}/05-bootprofiles.cfg"
  grub_os_prober_cfg="/target${DIR_GRUB_DEFAULT}/50-os-prober.cfg"
  grub_display_cfg="/target${FILE_GRUB_DISPLAY_CFG}"

  [ -r "$grub_cfg" ] || installer_fatal "generated grub.cfg is missing"
  [ -r "$custom_cfg" ] || installer_fatal "managed GRUB custom.cfg is missing"
  [ -x "$grub_custom_script" ] || installer_fatal "managed GRUB 40_custom script is missing or not executable"
  [ -r "$grub_defaults" ] || installer_fatal "target /etc/default/grub is missing"
  [ -r "$grub_dropin" ] || installer_fatal "target GRUB bootprofile drop-in is missing"
  [ -r "$grub_os_prober_cfg" ] || installer_fatal "target GRUB os-prober drop-in is missing"
  [ -r "$grub_display_cfg" ] || installer_fatal "target GRUB display drop-in is missing"
  if [ -e "/target${DIR_GRUB_SCRIPTS}/05_debian_theme" ] && [ -x "/target${DIR_GRUB_SCRIPTS}/05_debian_theme" ]; then
    installer_fatal "target GRUB 05_debian_theme generator is still executable"
  fi
}

verify_target_signed_kernel_images() {
  # shellcheck disable=SC2016
  run_in_target "verify signed bootable kernel images" /bin/sh -c '
set -eu
fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}
cert_pem=$1
found_signed_kernel=false
found_signed_kernel_count=0
[ -r "$cert_pem" ]
for kernel_image in /boot/vmlinuz-*; do
  [ -e "$kernel_image" ] || continue
  signer_listing=$(sbverify --list "$kernel_image" 2>/dev/null || true)
  [ -n "$signer_listing" ] || fatal "bootable kernel image is unsigned: $kernel_image"
  if printf "%s\n" "$signer_listing" | grep -Eiq "subject:.*debian|issuer:.*debian"; then
    found_signed_kernel=true
    found_signed_kernel_count=$((found_signed_kernel_count + 1))
    continue
  fi
  sbverify --cert "$cert_pem" "$kernel_image" >/dev/null 2>&1 || \
    fatal "bootable non-Debian kernel image is not signed with the managed MOK: $kernel_image"
  found_signed_kernel=true
  found_signed_kernel_count=$((found_signed_kernel_count + 1))
done
[ "$found_signed_kernel" = true ] || fatal "expected at least one bootable kernel image, found ${found_signed_kernel_count}"
' sh "${FILE_SECURE_BOOT_MOK_CERT_PEM}"
}
