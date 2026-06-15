#!/bin/sh
# F2FS/ext4 runtime layout helpers.
# shellcheck disable=SC2034

if ! command -v runtime_fatal >/dev/null 2>&1; then
  if [ -n "${RUNTIME_COMMON_LIB:-}" ] && [ -r "$RUNTIME_COMMON_LIB" ]; then
    # shellcheck disable=SC1090
    . "$RUNTIME_COMMON_LIB"
  else
    echo "fatal: runtime common helper is unavailable; set RUNTIME_COMMON_LIB before sourcing ${0##*/}" >&2
    exit 1
  fi
fi

runtime_secure_boot_state_mode() {
  mode=${SECURE_BOOT_STATE_MODE:-direct}
  case "$mode" in
    direct|luks)
      printf '%s\n' "$mode"
      ;;
    *)
      runtime_fatal "SECURE_BOOT_STATE_MODE must be 'direct' or 'luks' for F2FS profiles, got '${mode}'"
      ;;
  esac
}

runtime_crypto_answers_required() {
  runtime_secure_boot_state_uses_luks
}

runtime_required_slot_from_env() {
  label=$1
  eval "value=\${$label:-}"
  runtime_require_positive_integer "$label" "$value"
  printf '%s\n' "$value"
}

runtime_optional_slot_from_env() {
  label=$1
  eval "value=\${$label:-}"
  if [ -z "$value" ]; then
    printf '\n'
    return 0
  fi
  runtime_require_positive_integer "$label" "$value"
  printf '%s\n' "$value"
}

runtime_validate_layout_slots() {
  previous=0

  for slot in \
    "$RUNTIME_EFI_SLOT" \
    "$RUNTIME_BOOT_SLOT" \
    "$RUNTIME_ROOT_SLOT" \
    "${RUNTIME_HOME_SLOT:-}" \
    "${RUNTIME_POOL_SLOT:-}" \
    "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" \
    "$RUNTIME_VAR_LOG_JOURNAL_SLOT" \
    "$RUNTIME_RAW_SWAP_SLOT" \
    "$RUNTIME_RAW_ZRAM_SLOT"
  do
    [ -n "$slot" ] || continue
    runtime_require_positive_integer runtime_layout_slot "$slot"
    if [ "$slot" -le "$previous" ]; then
      runtime_fatal "F2FS slot numbering must stay strictly increasing from EFI through optional Secure Boot state and raw zram backing"
    fi
    previous=$slot
  done
}

runtime_apply_layout_from_cmdline() {
  installer_resolve_install_target_defaults
  : "${DEV_INSTALL_DISK:?DEV_INSTALL_DISK must be set}"
  F2FS_LAYOUT_VARIANT=${F2FS_LAYOUT_VARIANT:-custom}
  PARTMAN_RECIPE_NAME=${PARTMAN_RECIPE_NAME:-f2fs-layout}
  secure_boot_state_mode=$(runtime_secure_boot_state_mode)

  dualboot_efi_raw=$(runtime_cmdline_value dualboot_efi 2>/dev/null || true)
  dualboot_debian_raw=$(runtime_cmdline_value dualboot_debian 2>/dev/null || true)
  if runtime_dualboot_class_selected; then
    runtime_fatal "classes=...,dualboot is not supported for F2FS layouts"
  fi
  if [ -n "$dualboot_efi_raw" ] || [ -n "$dualboot_debian_raw" ]; then
    runtime_fatal "dualboot_efi and dualboot_debian require classes=...,dualboot on a Btrfs-family layout"
  fi

  runtime_derive_part_prefix
  RUNTIME_EFI_SLOT=$(runtime_required_slot_from_env DEFAULT_EFI_SLOT)
  RUNTIME_BOOT_SLOT=$(runtime_required_slot_from_env DEFAULT_BOOT_SLOT)
  RUNTIME_ROOT_SLOT=$(runtime_required_slot_from_env DEFAULT_ROOT_SLOT)
  RUNTIME_HOME_SLOT=$(runtime_optional_slot_from_env DEFAULT_HOME_SLOT)
  RUNTIME_POOL_SLOT=$(runtime_optional_slot_from_env DEFAULT_POOL_SLOT)
  RUNTIME_VAR_LOG_JOURNAL_SLOT=$(runtime_required_slot_from_env DEFAULT_VAR_LOG_JOURNAL_SLOT)
  RUNTIME_RAW_SWAP_SLOT=$(runtime_required_slot_from_env DEFAULT_RAW_SWAP_SLOT)
  RUNTIME_RAW_ZRAM_SLOT=$(runtime_required_slot_from_env DEFAULT_RAW_ZRAM_SLOT)
  RUNTIME_VAR_LIB_SHSIGNED_SLOT=
  if [ "$secure_boot_state_mode" = "luks" ]; then
    RUNTIME_VAR_LIB_SHSIGNED_SLOT=$(runtime_optional_slot_from_env DEFAULT_VAR_LIB_SHSIGNED_SLOT)
    if [ -z "$RUNTIME_VAR_LIB_SHSIGNED_SLOT" ]; then
      RUNTIME_VAR_LIB_SHSIGNED_SLOT=$RUNTIME_VAR_LOG_JOURNAL_SLOT
      RUNTIME_VAR_LOG_JOURNAL_SLOT=$((RUNTIME_VAR_LOG_JOURNAL_SLOT + 1))
      RUNTIME_RAW_SWAP_SLOT=$((RUNTIME_RAW_SWAP_SLOT + 1))
      RUNTIME_RAW_ZRAM_SLOT=$((RUNTIME_RAW_ZRAM_SLOT + 1))
    fi
  fi
  runtime_validate_layout_slots

  DEV_PART_EFI=$(runtime_partition_path "$RUNTIME_EFI_SLOT")
  DEV_PART_BOOT=$(runtime_partition_path "$RUNTIME_BOOT_SLOT")
  DEV_PART_ROOT=$(runtime_partition_path "$RUNTIME_ROOT_SLOT")
  if [ -n "${RUNTIME_HOME_SLOT:-}" ]; then
    DEV_PART_HOME=$(runtime_partition_path "$RUNTIME_HOME_SLOT")
  else
    DEV_PART_HOME=
  fi
  if [ -n "${RUNTIME_POOL_SLOT:-}" ]; then
    DEV_PART_POOL=$(runtime_partition_path "$RUNTIME_POOL_SLOT")
  else
    DEV_PART_POOL=
  fi
  if [ -n "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" ]; then
    DEV_PART_VAR_LIB_SHSIGNED=$(runtime_partition_path "$RUNTIME_VAR_LIB_SHSIGNED_SLOT")
  else
    DEV_PART_VAR_LIB_SHSIGNED=
  fi
  DEV_PART_VAR_LOG_JOURNAL=$(runtime_partition_path "$RUNTIME_VAR_LOG_JOURNAL_SLOT")
  DEV_PART_RAW_SWAP=$(runtime_partition_path "$RUNTIME_RAW_SWAP_SLOT")
  DEV_PART_RAW_ZRAM=$(runtime_partition_path "$RUNTIME_RAW_ZRAM_SLOT")
  ZRAM_BACKING_RAW_DEVICE=$DEV_PART_RAW_ZRAM
  ZRAM_BACKING_MAPPER_NAME=${ZRAM_BACKING_MAPPER_NAME:-zram-writeback}
  ZRAM_BACKING_DEVICE="/dev/mapper/${ZRAM_BACKING_MAPPER_NAME}"
  SWAP_FALLBACK_RAW_DEVICE=$DEV_PART_RAW_SWAP
  SWAP_FALLBACK_MAPPER_NAME=${SWAP_FALLBACK_MAPPER_NAME:-swap-fallback}
  SWAP_FALLBACK_MAPPER="/dev/mapper/${SWAP_FALLBACK_MAPPER_NAME}"
}

runtime_compute_layout_sizing() {
  disk_total_mb=$(runtime_install_disk_size_mb)
  ram_total_mib=$(runtime_total_ram_mib)

  runtime_require_positive_integer SIZE_LAYOUT_SAFETY_MARGIN_MB "$SIZE_LAYOUT_SAFETY_MARGIN_MB"
  runtime_require_positive_integer SIZE_PART_EFI_MB "$SIZE_PART_EFI_MB"
  runtime_require_positive_integer SIZE_PART_BOOT_MB "$SIZE_PART_BOOT_MB"
  runtime_require_positive_integer SIZE_PART_ROOT_MB "$SIZE_PART_ROOT_MB"
  runtime_require_nonnegative_integer SIZE_PART_HOME_MB "$SIZE_PART_HOME_MB"
  runtime_require_positive_integer SIZE_PART_VAR_LOG_JOURNAL_MB "$SIZE_PART_VAR_LOG_JOURNAL_MB"
  runtime_require_positive_integer SIZE_PART_RAW_SWAP_MB "$SIZE_PART_RAW_SWAP_MB"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_MB "$SIZE_PART_RAW_ZRAM_MB"
  runtime_require_nonnegative_integer SIZE_PART_POOL_MB "$SIZE_PART_POOL_MB"
  runtime_require_nonnegative_integer SIZE_PART_VAR_LIB_SHSIGNED_MB "$SIZE_PART_VAR_LIB_SHSIGNED_MB"
  runtime_require_nonnegative_integer SIZE_PART_HOME_TARGET_MB "$SIZE_PART_HOME_TARGET_MB"

  usable_budget_mb=$((disk_total_mb - SIZE_LAYOUT_SAFETY_MARGIN_MB))
  [ "$usable_budget_mb" -gt 0 ] || runtime_fatal "usable install budget collapsed to ${usable_budget_mb} MiB"

  DEV_PART_RAW_ZRAM_MB=$(runtime_compute_raw_zram_partition_mb "$usable_budget_mb" "$disk_total_mb")
  SWAP_SIZE_MIB=$(runtime_compute_swap_partition_mib "$usable_budget_mb" "$ram_total_mib")
  DEV_PART_RAW_SWAP_MB=$SWAP_SIZE_MIB

  DEV_PART_EFI_MB=$SIZE_PART_EFI_MB
  DEV_PART_BOOT_MB=$SIZE_PART_BOOT_MB
  DEV_PART_ROOT_MB=$SIZE_PART_ROOT_MB
  DEV_PART_HOME_MB=$SIZE_PART_HOME_MB
  DEV_PART_POOL_MB=$SIZE_PART_POOL_MB
  DEV_PART_VAR_LIB_SHSIGNED_MB=0
  if runtime_secure_boot_state_uses_luks; then
    runtime_require_positive_integer SIZE_PART_VAR_LIB_SHSIGNED_MB "$SIZE_PART_VAR_LIB_SHSIGNED_MB"
    DEV_PART_VAR_LIB_SHSIGNED_MB=$SIZE_PART_VAR_LIB_SHSIGNED_MB
  fi
  DEV_PART_VAR_LOG_JOURNAL_MB=$SIZE_PART_VAR_LOG_JOURNAL_MB

  base_total_mb=$((DEV_PART_EFI_MB + DEV_PART_BOOT_MB + DEV_PART_ROOT_MB + DEV_PART_HOME_MB + DEV_PART_POOL_MB + DEV_PART_VAR_LIB_SHSIGNED_MB + DEV_PART_VAR_LOG_JOURNAL_MB + DEV_PART_RAW_SWAP_MB + DEV_PART_RAW_ZRAM_MB))
  if [ "$base_total_mb" -gt "$usable_budget_mb" ]; then
    runtime_fatal "disk budget ${usable_budget_mb} MiB is too small for the F2FS minimum layout (${base_total_mb} MiB)"
  fi

  elastic_budget_mb=$((usable_budget_mb - base_total_mb))

  if [ "$DEV_PART_HOME_MB" -gt 0 ]; then
    runtime_apply_fill_result DEV_PART_HOME_MB elastic_budget_mb \
      "$(runtime_fill_partition_to_target "$DEV_PART_HOME_MB" "$SIZE_PART_HOME_TARGET_MB" "$elastic_budget_mb")"
  fi
  DEV_PART_ROOT_MB=$((DEV_PART_ROOT_MB + elastic_budget_mb))

  RUNTIME_DISK_TOTAL_MB=$disk_total_mb
  RUNTIME_LAYOUT_SAFETY_MARGIN_MB=$SIZE_LAYOUT_SAFETY_MARGIN_MB
  RUNTIME_USABLE_BUDGET_MB=$usable_budget_mb
  RUNTIME_BASE_LAYOUT_MB=$base_total_mb
  RUNTIME_INSTALL_RAM_MIB=$ram_total_mib
}

runtime_write_runtime_env() {
  dest=$1
  runtime_ensure_system_identity
  runtime_apply_layout_from_cmdline
  runtime_compute_layout_sizing
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf 'SYSTEM_PREFIX=%s\n' "$(runtime_shell_quote "$SYSTEM_PREFIX")"
    printf 'SYSTEM_HOSTNAME=%s\n' "$(runtime_shell_quote "$SYSTEM_HOSTNAME")"
    printf 'SYSTEM_DOMAIN=%s\n' "$(runtime_shell_quote "$SYSTEM_DOMAIN")"
    printf 'F2FS_LAYOUT_VARIANT=%s\n' "$(runtime_shell_quote "$F2FS_LAYOUT_VARIANT")"
    printf 'PARTMAN_RECIPE_NAME=%s\n' "$(runtime_shell_quote "$PARTMAN_RECIPE_NAME")"
    printf 'DEV_INSTALL_DISK=%s\n' "$(runtime_shell_quote "$DEV_INSTALL_DISK")"
    printf 'DEV_PART_PREFIX=%s\n' "$(runtime_shell_quote "$DEV_PART_PREFIX")"
    printf 'DEV_PART_EFI=%s\n' "$(runtime_shell_quote "$DEV_PART_EFI")"
    printf 'DEV_PART_BOOT=%s\n' "$(runtime_shell_quote "$DEV_PART_BOOT")"
    printf 'DEV_PART_ROOT=%s\n' "$(runtime_shell_quote "$DEV_PART_ROOT")"
    printf 'DEV_PART_HOME=%s\n' "$(runtime_shell_quote "${DEV_PART_HOME:-}")"
    printf 'DEV_PART_POOL=%s\n' "$(runtime_shell_quote "${DEV_PART_POOL:-}")"
    printf 'RUNTIME_VAR_LIB_SHSIGNED_SLOT=%s\n' "$(runtime_shell_quote "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}")"
    printf 'DEV_PART_VAR_LIB_SHSIGNED=%s\n' "$(runtime_shell_quote "${DEV_PART_VAR_LIB_SHSIGNED:-}")"
    printf 'DEV_PART_VAR_LOG_JOURNAL=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LOG_JOURNAL")"
    printf 'DEV_PART_RAW_SWAP=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_SWAP")"
    printf 'DEV_PART_RAW_ZRAM=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_ZRAM")"
    printf 'DEV_PART_EFI_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_EFI_MB")"
    printf 'DEV_PART_BOOT_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_BOOT_MB")"
    printf 'DEV_PART_ROOT_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_ROOT_MB")"
    printf 'DEV_PART_HOME_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_HOME_MB")"
    printf 'DEV_PART_POOL_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_POOL_MB")"
    printf 'DEV_PART_VAR_LIB_SHSIGNED_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LIB_SHSIGNED_MB")"
    printf 'DEV_PART_VAR_LOG_JOURNAL_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LOG_JOURNAL_MB")"
    printf 'DEV_PART_RAW_SWAP_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_SWAP_MB")"
    printf 'DEV_PART_RAW_ZRAM_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_ZRAM_MB")"
    printf 'SWAP_SIZE_MIB=%s\n' "$(runtime_shell_quote "$SWAP_SIZE_MIB")"
    printf 'RUNTIME_DISK_TOTAL_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_DISK_TOTAL_MB")"
    printf 'RUNTIME_LAYOUT_SAFETY_MARGIN_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_LAYOUT_SAFETY_MARGIN_MB")"
    printf 'RUNTIME_USABLE_BUDGET_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_USABLE_BUDGET_MB")"
    printf 'RUNTIME_BASE_LAYOUT_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_BASE_LAYOUT_MB")"
    printf 'RUNTIME_INSTALL_RAM_MIB=%s\n' "$(runtime_shell_quote "$RUNTIME_INSTALL_RAM_MIB")"
    printf 'ZRAM_BACKING_RAW_DEVICE=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_RAW_DEVICE")"
    printf 'ZRAM_BACKING_MAPPER_NAME=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_MAPPER_NAME")"
    printf 'ZRAM_BACKING_DEVICE=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_DEVICE")"
    printf 'SWAP_FALLBACK_RAW_DEVICE=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_RAW_DEVICE")"
    printf 'SWAP_FALLBACK_MAPPER_NAME=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_MAPPER_NAME")"
    printf 'SWAP_FALLBACK_MAPPER=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_MAPPER")"
  } >"$dest"
  chmod 0600 "$dest"
}

runtime_emit_recipe() {
  cat <<EOF
${PARTMAN_RECIPE_NAME} ::
    ${DEV_PART_EFI_MB} ${DEV_PART_EFI_MB} ${DEV_PART_EFI_MB} free
        \$iflabel{ gpt } \$primary{ } \$reusemethod{ } \$bootable{ }
        method{ efi } format{ }
    .
    ${DEV_PART_BOOT_MB} ${DEV_PART_BOOT_MB} ${DEV_PART_BOOT_MB} ext4
        \$primary{ } \$bootable{ }
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 }
        mountpoint{ /boot }
    .
    ${DEV_PART_ROOT_MB} ${DEV_PART_ROOT_MB} ${DEV_PART_ROOT_MB} f2fs
        method{ format } format{ }
        use_filesystem{ } filesystem{ f2fs }
        mountpoint{ / }
    .
EOF
  if [ "$DEV_PART_HOME_MB" -gt 0 ]; then
    cat <<EOF
    ${DEV_PART_HOME_MB} ${DEV_PART_HOME_MB} ${DEV_PART_HOME_MB} f2fs
        method{ format } format{ }
        use_filesystem{ } filesystem{ f2fs }
        mountpoint{ /home }
    .
EOF
  fi
  if [ "$DEV_PART_POOL_MB" -gt 0 ]; then
    cat <<EOF
    ${DEV_PART_POOL_MB} ${DEV_PART_POOL_MB} ${DEV_PART_POOL_MB} ext4
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 }
        mountpoint{ /pool }
    .
EOF
  fi
  if [ "$DEV_PART_VAR_LIB_SHSIGNED_MB" -gt 0 ]; then
    cat <<EOF
    ${DEV_PART_VAR_LIB_SHSIGNED_MB} ${DEV_PART_VAR_LIB_SHSIGNED_MB} ${DEV_PART_VAR_LIB_SHSIGNED_MB} ext4
        method{ crypto } format{ }
        crypto_type{ dm-crypt }
        cipher{ aes }
        keysize{ 256 }
        ivalgorithm{ xts-plain64 }
        keytype{ passphrase }
        keyhash{ sha256 }
        use_filesystem{ } filesystem{ ext4 }
        label{ ${FS_LABEL_VAR_LIB_SHSIGNED} }
        mountpoint{ /var/lib/shim-signed }
    .
EOF
  fi
  cat <<EOF
    ${DEV_PART_VAR_LOG_JOURNAL_MB} ${DEV_PART_VAR_LOG_JOURNAL_MB} ${DEV_PART_VAR_LOG_JOURNAL_MB} ext4
        method{ format } format{ }
        use_filesystem{ } filesystem{ ext4 }
        mountpoint{ /var/log/journal }
    .
    ${DEV_PART_RAW_SWAP_MB} ${DEV_PART_RAW_SWAP_MB} ${DEV_PART_RAW_SWAP_MB} free
        method{ keep }
    .
    ${DEV_PART_RAW_ZRAM_MB} ${DEV_PART_RAW_ZRAM_MB} 1000000000 free
        method{ keep }
    .
EOF
}

runtime_write_expert_recipe() {
  dest=$1
  runtime_apply_layout_from_cmdline
  runtime_compute_layout_sizing
  runtime_prepare_parent_dir "$dest" 0700
  runtime_emit_recipe >"$dest"
  chmod 0600 "$dest"
}

runtime_write_partman_fragment() {
  dest=$1
  recipe_file=$2
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf 'd-i partman-efi/confirm boolean true\n'
    printf 'd-i partman-efi/confirm seen true\n'
    printf 'd-i partman-auto/disk string %s\n' "$DEV_INSTALL_DISK"
    printf 'd-i partman-auto/disk seen true\n'
    printf 'd-i partman-partitioning/choose_label select gpt\n'
    printf 'd-i partman-partitioning/choose_label seen true\n'
    printf 'd-i partman-partitioning/default_label string gpt\n'
    printf 'd-i partman-partitioning/default_label seen true\n'
    printf 'd-i partman-partitioning/confirm_new_label boolean true\n'
    printf 'd-i partman-partitioning/confirm_new_label seen true\n'
    printf 'd-i partman-partitioning/confirm_write_new_label boolean true\n'
    printf 'd-i partman-partitioning/confirm_write_new_label seen true\n'
    printf 'd-i partman/confirm_write_new_label boolean true\n'
    printf 'd-i partman/confirm_write_new_label seen true\n'
    printf 'd-i partman-auto/method string regular\n'
    printf 'd-i partman-auto/method seen true\n'
    printf 'd-i partman-auto/choose_recipe select %s\n' "$PARTMAN_RECIPE_NAME"
    printf 'd-i partman-auto/choose_recipe seen true\n'
    printf 'd-i partman-auto/expert_recipe_file string %s\n' "$recipe_file"
    printf 'd-i partman-auto/expert_recipe_file seen true\n'
    printf 'd-i partman/choose_partition select finish\n'
    printf 'd-i partman/choose_partition seen true\n'
    printf 'd-i partman/confirm boolean true\n'
    printf 'd-i partman/confirm seen true\n'
    printf 'd-i partman/confirm_nochanges boolean true\n'
    printf 'd-i partman/confirm_nochanges seen true\n'
    printf 'd-i partman/confirm_nooverwrite boolean true\n'
    printf 'd-i partman/confirm_nooverwrite seen true\n'
    printf 'd-i partman-auto/confirm boolean true\n'
    printf 'd-i partman-auto/confirm seen true\n'
  } >"$dest"
  chmod 0644 "$dest"
}

runtime_write_identity_answers() {
  dest=$1
  runtime_ensure_system_identity
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf 'd-i netcfg/get_hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/get_hostname seen true\n'
    printf 'd-i netcfg/get_domain string %s\n' "$SYSTEM_DOMAIN"
    printf 'd-i netcfg/get_domain seen true\n'
    printf 'd-i netcfg/hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/hostname seen true\n'
  } >"$dest"
  chmod 0600 "$dest"
}

runtime_seed_identity_answers() {
  runtime_seed_generated_answers runtime_write_identity_answers
}
