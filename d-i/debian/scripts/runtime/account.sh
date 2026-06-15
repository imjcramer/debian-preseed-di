#!/bin/sh
# Shared account debconf rendering for every installer storage family.
# shellcheck disable=SC2034

if ! command -v runtime_fatal >/dev/null 2>&1; then
  if [ -n "${RUNTIME_COMMON_LIB:-}" ] && [ -r "$RUNTIME_COMMON_LIB" ]; then
    # shellcheck disable=SC1090
    . "$RUNTIME_COMMON_LIB"
  else
    printf 'fatal: runtime common helper is unavailable; set RUNTIME_COMMON_LIB before sourcing %s\n' "${0##*/}" >&2
    exit 1
  fi
fi

runtime_validate_printable_single_line() {
  label=$1
  value=$2

  [ -n "$value" ] || runtime_fatal "${label} must not be empty"
  case "$value" in
    *[![:print:]]*|*[[:space:]]*)
      runtime_fatal "${label} must be a single printable token without whitespace"
      ;;
  esac
}

runtime_validate_account_fullname() {
  value=$1

  [ -n "$value" ] || runtime_fatal "ACCOUNT_FULLNAME must not be empty"
  case "$value" in
    *[![:print:]]*)
      runtime_fatal "ACCOUNT_FULLNAME must not contain control characters"
      ;;
    [[:space:]]*|*[[:space:]])
      runtime_fatal "ACCOUNT_FULLNAME must not start or end with whitespace"
      ;;
  esac
}

runtime_validate_account_username() {
  value=$1

  printf '%s\n' "$value" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]*$' || \
    runtime_fatal "ACCOUNT_USERNAME must match ^[a-z_][a-z0-9_-]*$"
}

runtime_account_apply_home_paths() {
  ACCOUNT_HOME="/home/${ACCOUNT_USERNAME}"
  DIR_HOME_DESKTOP="${ACCOUNT_HOME}/Desktop"
  DIR_HOME_DOCUMENTS="${ACCOUNT_HOME}/Documents"
  DIR_HOME_DOWNLOADS="${ACCOUNT_HOME}/Downloads"
  DIR_HOME_MUSIC="${ACCOUNT_HOME}/Music"
  DIR_HOME_PUBLIC="${ACCOUNT_HOME}/Public"
  DIR_HOME_PICTURES="${ACCOUNT_HOME}/Pictures"
  DIR_HOME_TEMPLATES="${ACCOUNT_HOME}/Templates"
  DIR_HOME_VIDEOS="${ACCOUNT_HOME}/Videos"
  DIR_HOME_WORKSPACE="${ACCOUNT_HOME}/Workspace"
  SSH_AUTHORIZED_KEYS_TARGET="${ACCOUNT_HOME}/.ssh/authorized_keys"
  SSH_USER_CONFIG_TARGET="${ACCOUNT_HOME}/.ssh/config"
}

runtime_apply_account_from_cmdline() {
  [ "${RUNTIME_ACCOUNT_CMDLINE_READY:-0}" = 1 ] && return 0

  primary_user_raw=$(runtime_cmdline_value primary_user 2>/dev/null || true)
  primary_password_raw=$(runtime_cmdline_value primary_password 2>/dev/null || true)
  root_password_raw=$(runtime_cmdline_value root_password 2>/dev/null || true)

  runtime_validate_printable_single_line primary_user "$primary_user_raw"
  runtime_validate_account_username "$primary_user_raw"
  runtime_validate_printable_single_line primary_password "$primary_password_raw"
  runtime_validate_printable_single_line root_password "$root_password_raw"

  ACCOUNT_USERNAME=$primary_user_raw
  ACCOUNT_PASSWORD=$primary_password_raw
  ROOT_PASSWORD=$root_password_raw
  ACCOUNT_PASSWORD_IS_PLAIN=true
  ROOT_PASSWORD_IS_PLAIN=true
  runtime_account_apply_home_paths
  RUNTIME_ACCOUNT_CMDLINE_READY=1
}

runtime_validate_account_groups() {
  value=$1

  printf '%s\n' "$value" | LC_ALL=C grep -Eq '^[A-Za-z0-9_-]+( [A-Za-z0-9_-]+)*$' || \
    runtime_fatal "ACCOUNT_DEFAULT_GROUPS must be a space-separated group list"
}

runtime_validate_account_settings() {
  runtime_apply_account_from_cmdline

  : "${ROOT_LOGIN:?ROOT_LOGIN must be set}"
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_FULLNAME:?ACCOUNT_FULLNAME must be set}"
  : "${ACCOUNT_DEFAULT_GROUPS:?ACCOUNT_DEFAULT_GROUPS must be set}"

  if ! runtime_bool_is_true "$ROOT_LOGIN" && ! runtime_bool_is_false "$ROOT_LOGIN"; then
    runtime_fatal "ROOT_LOGIN must be true or false, got '${ROOT_LOGIN}'"
  fi

  runtime_validate_account_username "$ACCOUNT_USERNAME"
  runtime_validate_account_fullname "$ACCOUNT_FULLNAME"
  runtime_validate_account_groups "$ACCOUNT_DEFAULT_GROUPS"

  if [ "${ROOT_PASSWORD_IS_PLAIN:-false}" = true ]; then
    runtime_validate_printable_single_line ROOT_PASSWORD "$ROOT_PASSWORD"
  else
    : "${ROOT_PASSWORD_CRYPTED:?ROOT_PASSWORD_CRYPTED must be set}"
    runtime_validate_printable_single_line ROOT_PASSWORD_CRYPTED "$ROOT_PASSWORD_CRYPTED"
  fi

  if [ "${ACCOUNT_PASSWORD_IS_PLAIN:-false}" = true ]; then
    runtime_validate_printable_single_line ACCOUNT_PASSWORD "$ACCOUNT_PASSWORD"
  else
    : "${ACCOUNT_PASSWORD_CRYPTED:?ACCOUNT_PASSWORD_CRYPTED must be set}"
    runtime_validate_printable_single_line ACCOUNT_PASSWORD_CRYPTED "$ACCOUNT_PASSWORD_CRYPTED"
  fi
}

runtime_write_account_answers() {
  dest=$1

  runtime_validate_account_settings
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf '##########  Runtime Account Configuration  ##########\n'
    printf '# Generated inside the installer from hosts/shared/account.env.\n'
    printf 'd-i passwd/root-login boolean %s\n' "$ROOT_LOGIN"
    printf 'd-i passwd/root-login seen true\n'
    if [ "${ROOT_PASSWORD_IS_PLAIN:-false}" = true ]; then
      printf 'd-i passwd/root-password password %s\n' "$ROOT_PASSWORD"
      printf 'd-i passwd/root-password seen true\n'
      printf 'd-i passwd/root-password-again password %s\n' "$ROOT_PASSWORD"
      printf 'd-i passwd/root-password-again seen true\n'
    else
      printf 'd-i passwd/root-password-crypted password %s\n' "$ROOT_PASSWORD_CRYPTED"
      printf 'd-i passwd/root-password-crypted seen true\n'
    fi
    printf 'd-i passwd/make-user boolean true\n'
    printf 'd-i passwd/make-user seen true\n'
    printf 'd-i passwd/user-fullname string %s\n' "$ACCOUNT_FULLNAME"
    printf 'd-i passwd/user-fullname seen true\n'
    printf 'd-i passwd/username string %s\n' "$ACCOUNT_USERNAME"
    printf 'd-i passwd/username seen true\n'
    if [ "${ACCOUNT_PASSWORD_IS_PLAIN:-false}" = true ]; then
      printf 'd-i passwd/user-password password %s\n' "$ACCOUNT_PASSWORD"
      printf 'd-i passwd/user-password seen true\n'
      printf 'd-i passwd/user-password-again password %s\n' "$ACCOUNT_PASSWORD"
      printf 'd-i passwd/user-password-again seen true\n'
    else
      printf 'd-i passwd/user-password-crypted password %s\n' "$ACCOUNT_PASSWORD_CRYPTED"
      printf 'd-i passwd/user-password-crypted seen true\n'
    fi
    printf 'd-i passwd/user-default-groups string %s\n' "$ACCOUNT_DEFAULT_GROUPS"
    printf 'd-i passwd/user-default-groups seen true\n'
    printf 'd-i user-setup/allow-password-weak boolean false\n'
    printf 'd-i user-setup/allow-password-weak seen true\n'
  } >"$dest"
  chmod 0600 "$dest"
}

runtime_write_effective_account_env() {
  dest=$1

  runtime_apply_account_from_cmdline
  runtime_validate_account_username "$ACCOUNT_USERNAME"
  runtime_validate_account_fullname "$ACCOUNT_FULLNAME"
  runtime_validate_account_groups "$ACCOUNT_DEFAULT_GROUPS"
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf '# Generated inside the installer from hosts/shared/account.env plus cmdline identity overrides.\n'
    printf 'ROOT_LOGIN=%s\n' "$(runtime_shell_quote "$ROOT_LOGIN")"
    printf 'ACCOUNT_USERNAME=%s\n' "$(runtime_shell_quote "$ACCOUNT_USERNAME")"
    printf 'ACCOUNT_FULLNAME=%s\n' "$(runtime_shell_quote "$ACCOUNT_FULLNAME")"
    printf 'ACCOUNT_DEFAULT_GROUPS=%s\n' "$(runtime_shell_quote "$ACCOUNT_DEFAULT_GROUPS")"
    printf 'ACCOUNT_HOME=%s\n' "$(runtime_shell_quote "$ACCOUNT_HOME")"
    printf 'DIR_HOME_DESKTOP=%s\n' "$(runtime_shell_quote "$DIR_HOME_DESKTOP")"
    printf 'DIR_HOME_DOCUMENTS=%s\n' "$(runtime_shell_quote "$DIR_HOME_DOCUMENTS")"
    printf 'DIR_HOME_DOWNLOADS=%s\n' "$(runtime_shell_quote "$DIR_HOME_DOWNLOADS")"
    printf 'DIR_HOME_MUSIC=%s\n' "$(runtime_shell_quote "$DIR_HOME_MUSIC")"
    printf 'DIR_HOME_PUBLIC=%s\n' "$(runtime_shell_quote "$DIR_HOME_PUBLIC")"
    printf 'DIR_HOME_PICTURES=%s\n' "$(runtime_shell_quote "$DIR_HOME_PICTURES")"
    printf 'DIR_HOME_TEMPLATES=%s\n' "$(runtime_shell_quote "$DIR_HOME_TEMPLATES")"
    printf 'DIR_HOME_VIDEOS=%s\n' "$(runtime_shell_quote "$DIR_HOME_VIDEOS")"
    printf 'DIR_HOME_WORKSPACE=%s\n' "$(runtime_shell_quote "$DIR_HOME_WORKSPACE")"
    printf 'SSH_PUBLIC_KEY_SOURCE=%s\n' "$(runtime_shell_quote "$SSH_PUBLIC_KEY_SOURCE")"
    printf 'SSHD_CONFIG_SOURCE=%s\n' "$(runtime_shell_quote "$SSHD_CONFIG_SOURCE")"
    printf 'SSH_USER_CONFIG_SOURCE=%s\n' "$(runtime_shell_quote "$SSH_USER_CONFIG_SOURCE")"
    printf 'SSH_PUBLIC_KEY_MAX_BYTES=%s\n' "$(runtime_shell_quote "$SSH_PUBLIC_KEY_MAX_BYTES")"
    printf 'SSH_CONFIG_MAX_BYTES=%s\n' "$(runtime_shell_quote "$SSH_CONFIG_MAX_BYTES")"
    printf 'SSH_AUTHORIZED_KEYS_TARGET=%s\n' "$(runtime_shell_quote "$SSH_AUTHORIZED_KEYS_TARGET")"
    printf 'SSH_USER_CONFIG_TARGET=%s\n' "$(runtime_shell_quote "$SSH_USER_CONFIG_TARGET")"
  } >"$dest"
  chmod 0600 "$dest"
}
