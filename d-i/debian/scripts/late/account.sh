#!/bin/sh
# Shared late_command account helpers. This file is sourced, not executed.

provision_target_identity() {
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/hostname.tmpl)" /etc/hostname 0644
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/hosts.tmpl)" /etc/hosts 0644
}

ensure_target_account_home_ownership() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"

  case "$ACCOUNT_USERNAME" in
    [abcdefghijklmnopqrstuvwxyz_]*)
      ;;
    *)
      installer_fatal "ACCOUNT_USERNAME must start with a lowercase letter or underscore"
      ;;
  esac
  case "$ACCOUNT_USERNAME" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "ACCOUNT_USERNAME contains unsupported characters"
      ;;
  esac
  case "$ACCOUNT_HOME" in
    /*) ;;
    *)
      installer_fatal "ACCOUNT_HOME must be an absolute path"
      ;;
  esac
  case "$ACCOUNT_HOME" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "ACCOUNT_HOME contains unsupported path syntax"
      ;;
  esac

  # shellcheck disable=SC2016
  run_in_target "fix account home and home-subvolume ownership" /bin/sh -c '
set -eu
account_user=$1
account_home=$2
shift 2

fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

case "$account_home" in
  /*) ;;
  *) fatal "account home must be absolute: $account_home" ;;
esac
case "$account_home" in
  /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
    fatal "account home contains unsupported path syntax: $account_home"
    ;;
esac

uid=$(id -u "$account_user")
gid=$(id -g "$account_user")

install -d -m 0755 "$account_home"
chown "$uid:$gid" "$account_home"

for path in "$@"; do
  [ -n "$path" ] || continue
  case "$path" in
    "$account_home"/*) ;;
    *) fatal "managed home subvolume path is outside account home: $path" ;;
  esac
  install -d -m 0755 "$path"
  chown "$uid:$gid" "$path"
done

for path in "$account_home" "$@"; do
  [ -n "$path" ] || continue
  [ -d "$path" ] || fatal "managed home path is not a directory: $path"
  owner=$(stat -c "%u:%g" "$path")
  [ "$owner" = "$uid:$gid" ] || fatal "managed home path has owner $owner, expected $uid:$gid: $path"
done
  ' sh \
    "$ACCOUNT_USERNAME" \
    "$ACCOUNT_HOME" \
    "${DIR_HOME_DESKTOP:-}" \
    "${DIR_HOME_DOCUMENTS:-}" \
    "${DIR_HOME_DOWNLOADS:-}" \
    "${DIR_HOME_MUSIC:-}" \
    "${DIR_HOME_PUBLIC:-}" \
    "${DIR_HOME_PICTURES:-}" \
    "${DIR_HOME_TEMPLATES:-}" \
    "${DIR_HOME_VIDEOS:-}" \
    "${DIR_HOME_WORKSPACE:-}"
}

install_target_account_sudoers() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"

  case "$ACCOUNT_USERNAME" in
    [abcdefghijklmnopqrstuvwxyz_]*)
      ;;
    *)
      installer_fatal "ACCOUNT_USERNAME must start with a lowercase letter or underscore"
      ;;
  esac
  case "$ACCOUNT_USERNAME" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "ACCOUNT_USERNAME contains unsupported characters for sudoers"
      ;;
  esac

  sudoers_dir=/target/etc/sudoers.d
  sudoers_target="${sudoers_dir}/${ACCOUNT_USERNAME}"
  sudoers_tmp="${TMP_ENV_DIR}/account.sudoers.rendered"
  install -d -m 0750 "$sudoers_dir"
  installer_apply_scalar_placeholders \
    "$TMP_ENV_DIR/account.sudoers.tmpl" \
    "$sudoers_tmp" \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  install -m 0440 "$sudoers_tmp" "$sudoers_target"
  chown root:root "$sudoers_target"

  if ! test_in_target test -x /usr/sbin/visudo; then
    installer_fatal "visudo is unavailable in target; sudo package is required for ${sudoers_target}"
  fi
  run_in_target "validate account sudoers drop-in" /usr/sbin/visudo -cf "/etc/sudoers.d/${ACCOUNT_USERNAME}"
}

stage_target_polkit_rule() {
  rule_name=$1

  case "$rule_name" in
    [0123456789][0123456789]-*.rules) ;;
    *)
      installer_fatal "unsafe managed polkit rule name: ${rule_name:-unset}"
      ;;
  esac
  case "$rule_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*|*..*|.*|*/*)
      installer_fatal "unsafe managed polkit rule name: ${rule_name}"
      ;;
  esac

  stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/polkit-1/rules.d/${rule_name}")" \
    "${DIR_POLKIT_RULES_D}/${rule_name}" \
    0644
}

account_polkit_managed_rule_files() {
  cat <<'EOF'
00-admin-identities.rules
05-active-local-gate.rules
10-pkexec.rules
20-login1-power.rules
40-networkmanager.rules
50-usb-policy.rules
55-software-management.rules
60-system-services-identity.rules
70-hardware-peripherals.rules
EOF
}

configure_target_usb_media_access() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_DEFAULT_GROUPS:?ACCOUNT_DEFAULT_GROUPS must be set}"
  : "${DIR_POLKIT_LOCAL_RULES_D:?DIR_POLKIT_LOCAL_RULES_D must be set}"
  : "${DIR_POLKIT_RUNTIME_RULES_D:?DIR_POLKIT_RUNTIME_RULES_D must be set}"
  : "${FILE_POLKIT_RUNTIME_TMPFILES:?FILE_POLKIT_RUNTIME_TMPFILES must be set}"

  case "$ACCOUNT_USERNAME" in
    [abcdefghijklmnopqrstuvwxyz_]*)
      ;;
    *)
      installer_fatal "ACCOUNT_USERNAME must start with a lowercase letter or underscore"
      ;;
  esac
  case "$ACCOUNT_USERNAME" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "ACCOUNT_USERNAME contains unsupported characters for USB media policy"
      ;;
  esac
  case " $ACCOUNT_DEFAULT_GROUPS " in
    *" usbadmin "*)
      installer_fatal "ACCOUNT_DEFAULT_GROUPS must not include usbadmin; add users to usbadmin manually after install"
      ;;
  esac

  # shellcheck disable=SC2016
  run_in_target "create USB media authorization groups" /bin/sh -c '
set -eu
account_user=$1

for group_name in devops usbmedia usbadmin; do
  if ! getent group "$group_name" >/dev/null 2>&1; then
    groupadd --system "$group_name"
  fi
done

usermod -a -G devops,usbmedia "$account_user"
' sh "$ACCOUNT_USERNAME"

  install -d -m 0755 \
    "/target${DIR_UDISKS2}" \
    "/target${DIR_UDEV_CONF_D}" \
    "/target${DIR_UDEV_RULES}" \
    "/target${DIR_POLKIT_RULES_D}" \
    "/target${DIR_POLKIT_LOCAL_RULES_D}"

  polkit_managed_rule_files=$(account_polkit_managed_rule_files)
  [ -n "$polkit_managed_rule_files" ] || installer_fatal "managed polkit rule set is empty"

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/udisks2/udisks2.conf)" "${FILE_UDISKS2_CONF}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/udisks2/mount_options.conf)" "${FILE_UDISKS2_MOUNT_OPTIONS_CONF}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/udev/udev.conf.d/90-hardening.conf)" "${FILE_UDEV_HARDENING_CONF}" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/udev/rules.d/90-udisks-behavior.rules)" "${FILE_UDEV_UDISKS_BEHAVIOR_RULES}" 0644
  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/70-polkit-runtime.conf)" "${FILE_POLKIT_RUNTIME_TMPFILES}" 0644
  for polkit_rule in $polkit_managed_rule_files; do
    stage_target_polkit_rule "$polkit_rule"
  done
  unset polkit_rule
}
