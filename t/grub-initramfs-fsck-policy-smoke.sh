#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=16
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

run_case() {
  root_flags=$1
  initramfs_flags=$2

  (
    set -eu
    . "$ROOT_DIR/d-i/debian/scripts/late/grub.sh"
    GRUB_ROOT_FLAGS=$root_flags
    GRUB_INITRAMFS_FLAGS=$initramfs_flags
    apply_btrfs_root_initramfs_fsck_policy
    printf '%s\n' "$GRUB_INITRAMFS_FLAGS"
  )
}

printf '1..%s\n' "$TEST_COUNT"

if [ "$(run_case 'rootfstype=btrfs rootflags=subvol=@' 'initramfs_options=mode=0755,huge=within_size')" = \
  'initramfs_options=mode=0755,huge=within_size' ]; then
  pass "Btrfs root leaves global fsck policy unchanged"
else
  fail "Btrfs root leaves global fsck policy unchanged"
fi

if [ "$(run_case 'rootfstype=f2fs rootwait rootflags=rw' 'initramfs_options=mode=0755,huge=within_size')" = \
  'initramfs_options=mode=0755,huge=within_size' ]; then
  pass "non-Btrfs root leaves initramfs fsck policy unchanged"
else
  fail "non-Btrfs root leaves initramfs fsck policy unchanged"
fi

if [ "$(run_case 'rootfstype=btrfs rootflags=subvol=@' 'initramfs_options=mode=0755 fsck.mode=force')" = \
  'initramfs_options=mode=0755 fsck.mode=force' ]; then
  pass "explicit fsck policy is preserved"
else
  fail "explicit fsck policy is preserved"
fi

grub_profiles="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl"
if grep -q 'bootable_kernel_images=$(list_bootable_kernel_images)' "$grub_profiles" &&
   [ "$(grep -c 'list_bootable_kernel_images' "$grub_profiles")" -eq 2 ]; then
  pass "GRUB profile generator caches bootable kernel discovery once per run"
else
  fail "GRUB profile generator caches bootable kernel discovery once per run"
fi

fstab_generator="$ROOT_DIR/d-i/debian/hooks/shared/partman/finish.d/99-storage-layout.sh"
if grep -q 'fstab_entry "\$root_src" "/" "btrfs" "\$MNT_BTRFS_ROOT_OPTS" 0 0' "$fstab_generator" &&
   grep -q 'fstab_entry "\$efi_src" "\$DIR_BOOT_EFI" "vfat" "\$MNT_EFI_OPTS" 0 2' "$fstab_generator"; then
  pass "managed fstab generation skips fsck on btrfs root while keeping EFI at pass 2"
else
  fail "managed fstab generation skips fsck on btrfs root while keeping EFI at pass 2"
fi

fstab_guard="$ROOT_DIR/d-i/debian/hooks/shared/base-stage.d/20-fstab-guard"
if grep -q 'btrfs:/) pass=0 ;;' "$fstab_guard" &&
   grep -q 'vfat:\*|ext4:\*|f2fs:\*) pass=2 ;;' "$fstab_guard"; then
  pass "fallback fstab guard preserves the btrfs-root and EFI fsck policy"
else
  fail "fallback fstab guard preserves the btrfs-root and EFI fsck policy"
fi

if grep -q '^GRUB_REMOVABLE_BOOT_EFI_PATH=$INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH$' "$ROOT_DIR/d-i/debian/scripts/late/templates.sh" &&
   grep -q '^rescue_usb_efi_path=__INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH__$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   grep -q 'rescue_usb_uuid=${23}' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl" &&
   ! grep -q 'ESPBOOT' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl"; then
  pass "rescue USB GRUB entry uses the architecture-specific removable EFI path and installer-derived UUID search"
else
  fail "rescue USB GRUB entry uses the architecture-specific removable EFI path and installer-derived UUID search"
fi

if grep -q 'skip_mok_signing=false' "$grub_profiles" &&
   grep -q 'SKIP_MOK_SIGNING must be boolean when set' "$grub_profiles" &&
   grep -q 'MOK enrollment menu omitted because SKIP_MOK_SIGNING=1' "$grub_profiles" &&
   grep -q 'emit_mok_enrollment_menu()' "$grub_profiles" &&
   grep -q 'validate_grub_absolute_efi_path mokmanager_path "$mokmanager_path"' "$grub_profiles"; then
  pass "GRUB profile generator supports explicit MOK menu suppression for snapshot refreshes"
else
  fail "GRUB profile generator supports explicit MOK menu suppression for snapshot refreshes"
fi

if grep -q 'prepare_target_secure_boot_runtime()' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'load_target_boot_tool_state()' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'install_target_bootprofile_assets()' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'verify_target_bootprofile_core_staging()' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'prepare_target_secure_boot_runtime' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh" &&
   grep -q 'install_target_bootprofile_assets' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh" &&
   grep -q 'verify_target_bootprofile_core_staging' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh" &&
   grep -q 'load_target_boot_tool_state' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'install_target_bootprofile_assets' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'verify_target_bootprofile_core_staging' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'load_target_boot_tool_state' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"; then
  pass "late boot helpers expose shared Secure Boot, boot-tool, and bootprofile helpers"
else
  fail "late boot helpers expose shared Secure Boot, boot-tool, and bootprofile helpers"
fi

if (
  set -eu
  . "$ROOT_DIR/d-i/debian/scripts/late/grub.sh"
  prepare_calls=0
  capture_calls=0
  require_in_target() { :; }
  run_in_target() { prepare_calls=$((prepare_calls + 1)); }
  capture_in_target() {
    capture_calls=$((capture_calls + 1))
    cat <<'EOF'
TARGET_HAS_UPDATE_INITRAMFS=1
EOF
  }
  FILE_SECURE_BOOT_TOOL=/usr/libexec/install-tools/secure-boot-tool
  prepare_target_secure_boot_runtime
  prepare_target_secure_boot_runtime
  load_target_boot_tool_state
  load_target_boot_tool_state
  [ "$prepare_calls" -eq 1 ]
  [ "$capture_calls" -eq 1 ]
  [ "$TARGET_HAS_UPDATE_INITRAMFS" = 1 ]
  [ -z "${TARGET_HAS_OS_PROBER+x}" ]
  [ -z "${TARGET_HAS_UPDATE_GRUB+x}" ]
); then
  pass "cached GRUB late helpers avoid repeated target prepare and probe only the shared initramfs state"
else
  fail "cached GRUB late helpers avoid repeated target prepare and probe only the shared initramfs state"
fi

secure_boot_tool="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/libexec/install-tools/secure-boot-tool.tmpl"
if grep -q '^queue_enrolled_mok_deletions() {$' "$secure_boot_tool" &&
   grep -q 'queueing deletion of .* enrolled MOK certificate(s) before managed import' "$secure_boot_tool" &&
   grep -q 'failed to revoke stale pending MOK delete request; continuing with managed import' "$secure_boot_tool" &&
   grep -q 'matching managed MOK certificate is already enrolled and no delete request was queued; import is already satisfied' "$secure_boot_tool" &&
   ! grep -q '^queue_duplicate_mok_deletions() {$' "$secure_boot_tool" &&
   ! grep -q 'deferring stale duplicate cleanup until after managed MOK enrollment' "$secure_boot_tool"; then
  pass "secure boot helper queues MOK deletions before import and no longer defers duplicate cleanup"
else
  fail "secure boot helper queues MOK deletions before import and no longer defers duplicate cleanup"
fi

boot_env="$ROOT_DIR/d-i/debian/hosts/shared/boot.env"
display_template="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub.d/07-display.cfg.tmpl"
if grep -q '^GRUB_DISPLAY_GFXMODE="1024x768,auto"$' "$boot_env" &&
   ! grep -q '^GRUB_DISPLAY_COLOR_' "$boot_env" &&
   ! grep -q '^GRUB_COLOR_NORMAL=' "$display_template" &&
   ! grep -q '^GRUB_COLOR_HIGHLIGHT=' "$display_template"; then
  pass "managed GRUB display policy keeps VGA 766 equivalent gfxmode without color settings"
else
  fail "managed GRUB display policy keeps VGA 766 equivalent gfxmode without color settings"
fi

snapshot_menu_line=$(grep -n "submenu 'BTRFS Snapshots'" "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl" | head -n 1 | cut -d: -f1)
rescue_menu_line=$(grep -n "menuentry 'Boot from Rescue USB'" "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl" | head -n 1 | cut -d: -f1)
if [ -n "${snapshot_menu_line:-}" ] &&
   [ -n "${rescue_menu_line:-}" ] &&
   [ "$snapshot_menu_line" -lt "$rescue_menu_line" ] &&
   grep -q 'configfile "${prefix}/grub-btrfs.cfg"' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/grub-profiles.tmpl"; then
  pass "managed GRUB menu places BTRFS snapshots before the rescue USB entry"
else
  fail "managed GRUB menu places BTRFS snapshots before the rescue USB entry"
fi

initramfs_btrfs_skip_hook="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/initramfs-tools/scripts/local-premount/20-btrfs-root-no-fsck"
if grep -q 'Skipping initramfs fsck for Btrfs root filesystem' "$initramfs_btrfs_skip_hook" &&
   grep -q 'case "${2:-}:${3:-}" in' "$initramfs_btrfs_skip_hook" &&
   grep -q 'root:btrfs|/:btrfs' "$initramfs_btrfs_skip_hook"; then
  pass "initramfs hook limits the fsck skip to Btrfs root calls at checkfs runtime"
else
  fail "initramfs hook limits the fsck skip to Btrfs root calls at checkfs runtime"
fi

if (
  set -eu
  ROOT=/dev/root
  ROOTFSTYPE=btrfs
  root_calls=0
  other_calls=0
  get_fstype() { printf 'btrfs\n'; }
  log_warning_msg() { :; }
  panic() { exit 1; }
  _checkfs_once() {
    case "$2" in
      root|/) root_calls=$((root_calls + 1)) ;;
      *) other_calls=$((other_calls + 1)) ;;
    esac
    return 0
  }
  checkfs() { _checkfs_once "$@"; }
  . "$initramfs_btrfs_skip_hook"
  checkfs /dev/root root btrfs
  checkfs /dev/sda1 /boot ext4
  [ "$root_calls" -eq 0 ]
  [ "$other_calls" -eq 1 ]
); then
  pass "initramfs hook skips only the root fsck call and preserves other checks"
else
  fail "initramfs hook skips only the root fsck call and preserves other checks"
fi

if grep -q 'install MOK LUKS aliases in target shell rc files' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'ensure_rc_file "\$bashrc_path" /etc/skel/.bashrc' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'append_alias_block "\$bashrc_path"' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh" &&
   grep -q 'rewrite_without_marker "\$profile_path"' "$ROOT_DIR/d-i/debian/scripts/late/grub.sh"; then
  pass "secure boot late helper keeps managed MOK aliases out of the shared profile and installs them in shell rc files"
else
  fail "secure boot late helper keeps managed MOK aliases out of the shared profile and installs them in shell rc files"
fi
