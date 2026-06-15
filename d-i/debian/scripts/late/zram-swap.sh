#!/bin/sh
# Shared late_command zram, swap, and storage-unit helpers. This file is sourced, not executed.

fstab_entry() {
  printf '%-28s %-36s %-8s %-72s %s %s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

device_source() {
  dev=$1
  if [ "$dev" = "tmpfs" ]; then
    printf 'tmpfs\n'
    return 0
  fi
  if command -v blkid >/dev/null 2>&1; then
    uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
    if [ -n "$uuid" ]; then
      printf 'UUID=%s\n' "$uuid"
      return 0
    fi
  fi
  printf '%s\n' "$dev"
}

write_target_swap_fallback_config() {
  {
    write_shell_config_var SWAP_FALLBACK_RAW_DEVICE "${SWAP_FALLBACK_RAW_DEVICE}"
    write_shell_config_var SWAP_FALLBACK_MAPPER_NAME "${SWAP_FALLBACK_MAPPER_NAME}"
    write_shell_config_var SWAP_FALLBACK_MAPPER "${SWAP_FALLBACK_MAPPER}"
    write_shell_config_var SWAP_FALLBACK_PRIORITY "${SWAP_FALLBACK_PRIORITY}"
    write_shell_config_var DMCRYPT_EPHEMERAL_CIPHER "${DMCRYPT_EPHEMERAL_CIPHER}"
    write_shell_config_var DMCRYPT_EPHEMERAL_KEY_SIZE "${DMCRYPT_EPHEMERAL_KEY_SIZE}"
    write_shell_config_var DMCRYPT_EPHEMERAL_HASH "${DMCRYPT_EPHEMERAL_HASH}"
    write_shell_config_var DMCRYPT_RANDOM_KEY_FILE "${DMCRYPT_RANDOM_KEY_FILE}"
  } >"/target${FILE_SWAP_FALLBACK_CONFIG}"
  chmod 0600 "/target${FILE_SWAP_FALLBACK_CONFIG}"
}

zram_perl_modules() {
  cat <<'EOF'
Zram.pm
Zram/BackingDevice.pm
Zram/Budget.pm
Zram/CLI.pm
Zram/Command.pm
Zram/Command/Apply.pm
Zram/Command/Metrics.pm
Zram/Command/Reset.pm
Zram/Command/Status.pm
Zram/Command/Writeback.pm
Zram/Config.pm
Zram/Config/Parser.pm
Zram/Config/Schema.pm
Zram/Config/Validator.pm
Zram/Daemon.pm
Zram/Debugfs.pm
Zram/Device.pm
Zram/Error.pm
Zram/Lock.pm
Zram/Logger.pm
Zram/Metrics.pm
Zram/Path.pm
Zram/Policy.pm
Zram/Pressure.pm
Zram/Procfs.pm
Zram/Sizing.pm
Zram/Swap.pm
Zram/Stats.pm
Zram/Sysfs.pm
Zram/Types.pm
EOF
}

stage_target_zram_perl_modules() {
  zram_perl_modules | while IFS= read -r zram_module; do
    [ -n "$zram_module" ] || continue
    stage_target_asset \
      "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "usr/local/libexec/zram-writeback/${zram_module}")" \
      "${DIR_ZRAM_LIBEXEC}/${zram_module}" \
      0644
  done
}

stage_target_zram_assets() {
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modprobe.d/zram.conf)" "${FILE_MODPROBE_ZRAM}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modules-load.d/40-zram.conf)" "${FILE_MODULES_LOAD_ZRAM}" 0644
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/default/zram-writeback.tmpl)" "${FILE_ZRAM_DEFAULT}" 0644
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/zram-writeback.conf)" "${FILE_ZRAM_CONFIG}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/60-zram-writeback.conf)" "${FILE_ZRAM_TMPFILES}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/zram-device-setup.tmpl)" "${FILE_ZRAM_SETUP_HELPER}" 0755
  stage_target_zram_perl_modules
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/zram-writeback.tmpl)" "${FILE_ZRAM_WRITEBACK_HELPER}" 0755
  render_target_template "$TMP_ENV_DIR/zram-setup.service.tmpl" "/target${FILE_ZRAM_SETUP_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-writeback.service.tmpl" "/target${FILE_ZRAM_WRITEBACK_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-writebackd.service.tmpl" "/target${FILE_ZRAM_WRITEBACKD_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-idle-writeback.timer.tmpl" "/target${FILE_ZRAM_IDLE_WRITEBACK_TIMER}" 0644
  render_target_template "$TMP_ENV_DIR/zram-cold-tier.timer.tmpl" "/target${FILE_ZRAM_COLD_TIER_TIMER}" 0644
}

verify_target_zram_staging() {
  require_in_target "zram verification"

  # shellcheck disable=SC2016
  run_in_target "verify staged zram payload" /bin/sh -c '
set -eu
default_config=$1
ini_config=$2
tmpfiles_config=$3
setup_helper=$4
writeback_helper=$5
setup_unit=$6
writeback_unit=$7
writebackd_unit=$8
idle_timer=${9}
cold_timer=${10}
modprobe_file=${11}
modules_file=${12}
module_root=${13}
shift 13

[ -r "$default_config" ]
[ -r "$ini_config" ]
[ -r "$tmpfiles_config" ]
[ -x "$setup_helper" ]
[ -x "$writeback_helper" ]
[ -r "$setup_unit" ]
[ -r "$writeback_unit" ]
[ -r "$writebackd_unit" ]
[ -r "$idle_timer" ]
[ -r "$cold_timer" ]
[ -r "$modprobe_file" ]
[ -r "$modules_file" ]
[ -L /etc/systemd/system/multi-user.target.wants/zram-setup.service ]
[ -L /etc/systemd/system/multi-user.target.wants/zram-writebackd.service ]
[ -L /etc/systemd/system/timers.target.wants/zram-idle-writeback.timer ]
[ -L /etc/systemd/system/timers.target.wants/zram-cold-tier.timer ]
sh -n "$default_config"
sh -n "$setup_helper"
for module in "$@"; do
  [ -r "$module_root/$module" ]
  PERL5LIB="$module_root" perl -c "$module_root/$module" >/dev/null
done
PERL5LIB="$module_root" perl -MZram::Config -e \
  "Zram::Config::load_config(\$ARGV[0]); Zram::Config::validate_config(require_sysfs => 0);" \
  "$ini_config"
PERL5LIB="$module_root" perl -c "$writeback_helper" >/dev/null
' sh \
    "${FILE_ZRAM_DEFAULT}" \
    "${FILE_ZRAM_CONFIG}" \
    "${FILE_ZRAM_TMPFILES}" \
    "${FILE_ZRAM_SETUP_HELPER}" \
    "${FILE_ZRAM_WRITEBACK_HELPER}" \
    "${FILE_ZRAM_SETUP_SERVICE}" \
    "${FILE_ZRAM_WRITEBACK_SERVICE}" \
    "${FILE_ZRAM_WRITEBACKD_SERVICE}" \
    "${FILE_ZRAM_IDLE_WRITEBACK_TIMER}" \
    "${FILE_ZRAM_COLD_TIER_TIMER}" \
    "${FILE_MODPROBE_ZRAM}" \
    "${FILE_MODULES_LOAD_ZRAM}" \
    "${DIR_ZRAM_LIBEXEC}" \
    $(zram_perl_modules)
}

set_target_default_unit() {
  stage_target_default_systemd_unit multi-user.target
}

target_unit_exists() {
  unit=$1

  target_systemd_unit_path "$unit" system >/dev/null 2>&1
}

enable_target_required_unit() {
  unit=$1
  target_unit_exists "$unit" || installer_fatal "expected target unit is missing: ${unit}"
  stage_target_systemd_unit_enabled "$unit" system
}

enable_target_storage_units() {
  enable_target_required_unit "swap-fallback.service"
  enable_target_required_unit "zram-setup.service"
  enable_target_required_unit "zram-writebackd.service"
  enable_target_required_unit "zram-idle-writeback.timer"
  enable_target_required_unit "zram-cold-tier.timer"
  if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
    enable_target_required_unit "apt-refresh-lists.service"
  fi
  enable_target_required_unit "bootprofile-apply.service"
  enable_target_required_unit "fstrim.timer"
}
