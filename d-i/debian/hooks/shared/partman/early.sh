#!/bin/sh

partman_early_require_command() {
  command -v "$1" >/dev/null 2>&1 || installer_fatal "required command is unavailable: $1"
}

partman_early_settle_block_devices() {
  disk=${1:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_settle_block_devices requires a disk path"
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "$disk" || installer_warn "partprobe failed for ${disk}"
  fi
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || installer_warn "udevadm settle failed for ${disk}"
  fi
}

partman_early_log_partition_state() {
  label=$1
  disk=${2:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_log_partition_state requires a disk path"
  installer_info "${label}: sfdisk --json ${disk}"
  sfdisk --json "$disk" 2>/dev/null || installer_warn "sfdisk --json failed during ${label} for ${disk}"
  installer_info "${label}: parted -sm ${disk} unit MiB print free"
  parted -sm "$disk" unit MiB print free 2>/dev/null || installer_warn "parted print free failed during ${label} for ${disk}"
}

partman_early_reinitialize_gpt_disk() {
  disk=${1:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_reinitialize_gpt_disk requires a disk path"
  installer_info "reinitializing GPT label on ${disk} using sfdisk + parted"
  sfdisk --delete "$disk" >/dev/null 2>&1 || true
  parted -s "$disk" mklabel gpt || installer_fatal "failed to create GPT label on ${disk} with parted"
  partman_early_settle_block_devices "$disk"
  partman_early_log_partition_state "after-gpt-label" "$disk"
}
