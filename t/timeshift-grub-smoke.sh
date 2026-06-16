#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=10
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

printf '1..%s\n' "$TEST_COUNT"

run_class_case() {
  runtime_name=$1
  classes_raw=$2
  case_dir="$ROOT_DIR/.tmp-timeshift-class-$runtime_name.$$"
  mkdir -p "$case_dir"
  if (
    set -eu
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian"
    INSTALLER_RUNTIME_DIR="$case_dir"
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
    installer_auto_class_tokens() { return 0; }
    installer_cmdline_value() {
      case "$1" in
        auto-install/classes|classes)
          printf '%s\n' "$classes_raw"
          ;;
      esac
    }
    installer_debconf_value() { return 1; }
    installer_write_context "$ROOT_DIR/d-i/debian" >/dev/null
  ); then
    rm -rf "$case_dir"
    return 0
  fi
  rm -rf "$case_dir"
  return 1
}

timeshift_class="$ROOT_DIR/d-i/debian/classes/class-addon/timeshift.cfg"
if grep -Eq '^d-i pkgsel/include string timeshift$' "$timeshift_class"; then
  pass "timeshift addon fragment installs the Timeshift package"
else
  fail "timeshift addon fragment installs the Timeshift package"
fi

classes_conf="$ROOT_DIR/d-i/debian/classes/CLASSES.conf"
common_lib="$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
if grep -q '^\[class\.addon\.timeshift\]$' "$classes_conf" &&
   grep -q '^allowed_hardware_classes=disk/nvme disk/vm$' "$classes_conf" &&
   grep -q 'allowed_hardware_classes=$(installer_class_meta_value' "$common_lib" &&
   grep -q 'selected class ${group_name}/${class_name} is only allowed with one of:' "$common_lib"; then
  pass "timeshift addon is restricted to Btrfs-root storage classes and enforced by class resolution"
else
  fail "timeshift addon is restricted to Btrfs-root storage classes and enforced by class resolution"
fi

if run_class_case allow 'lab,desktop,standard,dhcp,amd64,intel,generic,nvme,timeshift'; then
  pass "timeshift addon is accepted for the Btrfs NVMe class"
else
  fail "timeshift addon is accepted for the Btrfs NVMe class"
fi

if run_class_case deny 'lab,desktop,standard,dhcp,amd64,intel,generic,emmc,timeshift'; then
  fail "timeshift addon is rejected for the F2FS eMMC class"
else
  pass "timeshift addon is rejected for the F2FS eMMC class"
fi

runtime_env="$ROOT_DIR/d-i/debian/hosts/shared/runtime.env"
if grep -q '^FILE_TIMESHIFT_CONFIG=' "$runtime_env" &&
   grep -q '^FILE_TIMESHIFT_SNAPSHOT_HELPER=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_CONFIG=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_REFRESH_HELPER=' "$runtime_env" &&
   grep -q '^FILE_GRUB_BTRFS_REFRESH_PATH=' "$runtime_env"; then
  pass "runtime env exports the managed Timeshift and GRUB snapshot asset paths"
else
  fail "runtime env exports the managed Timeshift and GRUB snapshot asset paths"
fi

timeshift_config="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/timeshift/timeshift.json.tmpl"
if grep -q '"btrfs_mode" : "true"' "$timeshift_config" &&
   grep -q '"include_btrfs_home" : "false"' "$timeshift_config" &&
   grep -q '"count_daily" : "16"' "$timeshift_config" &&
   grep -q '"count_weekly" : "4"' "$timeshift_config" &&
   grep -q '"count_monthly" : "2"' "$timeshift_config"; then
  pass "Timeshift config template encodes the managed retention policy"
else
  fail "Timeshift config template encodes the managed retention policy"
fi

snapshot_helper="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/sbin/timeshift-managed-snapshot"
grub_refresh_helper="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/sbin/grub-btrfs-refresh"
if /bin/sh -n "$snapshot_helper" &&
   /bin/bash -n "$grub_refresh_helper" &&
   grep -q 'export SKIP_MOK_SIGNING=${SKIP_MOK_SIGNING:-1}' "$grub_refresh_helper" &&
   grep -q 'flock -n 9' "$grub_refresh_helper" &&
   grep -q 'new_temp_file()' "$grub_refresh_helper" &&
   grep -q 'remove_temp_file "$profile_body"' "$grub_refresh_helper" &&
   ! grep -q 'cat <<EOF' "$grub_refresh_helper" &&
   ! grep -q 'update-grub' "$grub_refresh_helper"; then
  pass "managed Timeshift and GRUB snapshot helpers are syntax-valid"
else
  fail "managed Timeshift and GRUB snapshot helpers are syntax-valid"
fi

grub_refresh_path="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/grub-btrfs-refresh.path"
grub_refresh_service="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/grub-btrfs-refresh.service"
if grep -q '^PathExistsGlob=/run/timeshift/\*$' "$grub_refresh_path" &&
   grep -q '^PathChanged=/run/timeshift$' "$grub_refresh_path" &&
   grep -q '^Environment=SKIP_MOK_SIGNING=1$' "$grub_refresh_service" &&
   grep -q '^ExecStart=/usr/local/sbin/grub-btrfs-refresh --wait$' "$grub_refresh_service"; then
  pass "GRUB snapshot refresh is driven by a Timeshift-aware path and wait-capable service"
else
  fail "GRUB snapshot refresh is driven by a Timeshift-aware path and wait-capable service"
fi

daily_timer="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/timeshift-daily.timer"
weekly_timer="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/timeshift-weekly.timer"
monthly_timer="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/timeshift-monthly.timer"
if grep -q '^OnCalendar=\*-\*-\* 00,06,12,18:00:00$' "$daily_timer" &&
   grep -q '^OnCalendar=Sun,Wed \*-\*-\* 03:00:00$' "$weekly_timer" &&
   grep -q '^OnCalendar=\*-\*-01 04:00:00$' "$monthly_timer"; then
  pass "managed Timeshift timers encode the four-daily, twice-weekly, and monthly schedule"
else
  fail "managed Timeshift timers encode the four-daily, twice-weekly, and monthly schedule"
fi

btrfs_family="$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh"
if grep -q 'configure_target_timeshift()' "$btrfs_family" &&
   grep -q 'load_target_btrfs_optional_package_state()' "$btrfs_family" &&
   grep -q 'TARGET_HAS_BTRFSMAINTENANCE_PACKAGE=0' "$btrfs_family" &&
   grep -q 'TARGET_HAS_TIMESHIFT_PACKAGE=0' "$btrfs_family" &&
   grep -q 'btrfs_stage_shared_target_asset()' "$btrfs_family" &&
   grep -q 'verify_target_timeshift_staging()' "$btrfs_family" &&
   grep -q 'require_symlink_target /etc/systemd/system/timers.target.wants/timeshift-daily.timer' "$btrfs_family" &&
   grep -q 'verify_target_timeshift_grub_menu()' "$btrfs_family" &&
   grep -q 'grub-btrfs-refresh.path' "$btrfs_family" &&
   grep -q 'stage_target_systemd_unit_enabled "$unit" system' "$btrfs_family" &&
   grep -q 'run_in_target "prime managed GRUB BTRFS snapshot menu"' "$btrfs_family" &&
   grep -q 'verify_target_timeshift_grub_menu' "$btrfs_family"; then
  pass "Btrfs late hook stages, enables, verifies, and primes the Timeshift snapshot integration"
else
  fail "Btrfs late hook stages, enables, verifies, and primes the Timeshift snapshot integration"
fi

[ "$FAIL_COUNT" -eq 0 ]
