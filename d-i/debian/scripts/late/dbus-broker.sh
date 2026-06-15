#!/bin/sh
# Shared late_command dbus-broker helpers. This file is sourced, not executed.

validate_dbus_target_path() {
  label=$1
  value=$2

  case "$value" in
    /*) ;;
    *) installer_fatal "${label} must be an absolute target path, got '${value}'" ;;
  esac
  case "$value" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@:+%=-]*)
      installer_fatal "${label} contains unsupported path syntax: ${value}"
      ;;
  esac
}

require_uint_range() {
  label=$1
  value=$2
  min=$3
  max=$4

  case "$value" in
    ''|*[!0123456789]*)
      installer_fatal "${label} must be an integer, got '${value}'"
      ;;
  esac
  [ "$value" -ge "$min" ] || installer_fatal "${label} must be >= ${min}, got ${value}"
  [ "$value" -le "$max" ] || installer_fatal "${label} must be <= ${max}, got ${value}"
}

validate_dbus_broker_policy_env() {
  for dir_var in DIR_DBUS_SESSION_SERVICES DIR_DBUS_LOCAL_SESSION_SERVICES; do
    eval "dir_value=\${$dir_var-}"
    [ -n "$dir_value" ] || installer_fatal "${dir_var} must be set"
    validate_dbus_target_path "$dir_var" "$dir_value"
  done

  for path_var in \
    FILE_DBUS_BLOCKED_PACKAGES_APT_PREFERENCE \
    FILE_DBUS_SYSTEM_LOCAL_CONF \
    FILE_DBUS_SYSTEM_CONF \
    FILE_DBUS_SYSTEM_SERVICE_ALIAS \
    FILE_DBUS_USER_SERVICE_ALIAS \
    FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE \
    FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE \
    FILE_DBUS_BROKER_BINARY \
    FILE_DBUS_BROKER_LAUNCH_BINARY
  do
    eval "path_value=\${$path_var-}"
    [ -n "$path_value" ] || installer_fatal "${path_var} must be set"
    validate_dbus_target_path "$path_var" "$path_value"
  done

  require_uint_range DBUS_LIMIT_MAX_INCOMING_BYTES "${DBUS_LIMIT_MAX_INCOMING_BYTES:-}" 1048576 134217728
  require_uint_range DBUS_LIMIT_MAX_OUTGOING_BYTES "${DBUS_LIMIT_MAX_OUTGOING_BYTES:-}" 1048576 134217728
  require_uint_range DBUS_LIMIT_MAX_MESSAGE_SIZE "${DBUS_LIMIT_MAX_MESSAGE_SIZE:-}" 1024 33554432
  require_uint_range DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS "${DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS:-}" 0 1024
  require_uint_range DBUS_LIMIT_MAX_INCOMING_UNIX_FDS "${DBUS_LIMIT_MAX_INCOMING_UNIX_FDS:-}" 0 1024
  require_uint_range DBUS_LIMIT_MAX_OUTGOING_UNIX_FDS "${DBUS_LIMIT_MAX_OUTGOING_UNIX_FDS:-}" 0 1024
  require_uint_range DBUS_LIMIT_MAX_MATCH_RULES_PER_CONNECTION "${DBUS_LIMIT_MAX_MATCH_RULES_PER_CONNECTION:-}" 1 65536
  require_uint_range DBUS_LIMIT_MAX_NAMES_PER_CONNECTION "${DBUS_LIMIT_MAX_NAMES_PER_CONNECTION:-}" 1 1024
  require_uint_range DBUS_LIMIT_MAX_REPLIES_PER_CONNECTION "${DBUS_LIMIT_MAX_REPLIES_PER_CONNECTION:-}" 1 4096
  require_uint_range DBUS_LIMIT_MAX_INCOMPLETE_CONNECTIONS "${DBUS_LIMIT_MAX_INCOMPLETE_CONNECTIONS:-}" 1 4096
  require_uint_range DBUS_LIMIT_MAX_COMPLETED_CONNECTIONS "${DBUS_LIMIT_MAX_COMPLETED_CONNECTIONS:-}" 16 65536
  require_uint_range DBUS_LIMIT_MAX_CONNECTIONS_PER_USER "${DBUS_LIMIT_MAX_CONNECTIONS_PER_USER:-}" 1 4096
  require_uint_range DBUS_LIMIT_MAX_PENDING_SERVICE_STARTS "${DBUS_LIMIT_MAX_PENDING_SERVICE_STARTS:-}" 1 4096
  require_uint_range DBUS_LIMIT_AUTH_TIMEOUT_MS "${DBUS_LIMIT_AUTH_TIMEOUT_MS:-}" 1000 600000
  require_uint_range DBUS_LIMIT_PENDING_FD_TIMEOUT_MS "${DBUS_LIMIT_PENDING_FD_TIMEOUT_MS:-}" 1000 600000
  require_uint_range DBUS_LIMIT_SERVICE_START_TIMEOUT_MS "${DBUS_LIMIT_SERVICE_START_TIMEOUT_MS:-}" 1000 600000
  require_uint_range DBUS_LIMIT_REPLY_TIMEOUT_MS "${DBUS_LIMIT_REPLY_TIMEOUT_MS:-}" 1000 600000

  [ "$DBUS_LIMIT_MAX_MESSAGE_SIZE" -le "$DBUS_LIMIT_MAX_INCOMING_BYTES" ] || \
    installer_fatal "DBUS_LIMIT_MAX_MESSAGE_SIZE must not exceed DBUS_LIMIT_MAX_INCOMING_BYTES"
  [ "$DBUS_LIMIT_MAX_MESSAGE_SIZE" -le "$DBUS_LIMIT_MAX_OUTGOING_BYTES" ] || \
    installer_fatal "DBUS_LIMIT_MAX_MESSAGE_SIZE must not exceed DBUS_LIMIT_MAX_OUTGOING_BYTES"
  [ "$DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS" -le "$DBUS_LIMIT_MAX_INCOMING_UNIX_FDS" ] || \
    installer_fatal "DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS must not exceed DBUS_LIMIT_MAX_INCOMING_UNIX_FDS"
  [ "$DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS" -le "$DBUS_LIMIT_MAX_OUTGOING_UNIX_FDS" ] || \
    installer_fatal "DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS must not exceed DBUS_LIMIT_MAX_OUTGOING_UNIX_FDS"

  require_uint_range DBUS_BROKER_TASKS_MAX "${DBUS_BROKER_TASKS_MAX:-}" 64 8192
  require_uint_range DBUS_BROKER_LIMIT_NOFILE "${DBUS_BROKER_LIMIT_NOFILE:-}" 1024 1048576
}

dbus_broker_placeholder_map() {
  for var_name in \
    DBUS_LIMIT_MAX_INCOMING_BYTES \
    DBUS_LIMIT_MAX_OUTGOING_BYTES \
    DBUS_LIMIT_MAX_MESSAGE_SIZE \
    DBUS_LIMIT_MAX_MESSAGE_UNIX_FDS \
    DBUS_LIMIT_MAX_INCOMING_UNIX_FDS \
    DBUS_LIMIT_MAX_OUTGOING_UNIX_FDS \
    DBUS_LIMIT_MAX_MATCH_RULES_PER_CONNECTION \
    DBUS_LIMIT_MAX_NAMES_PER_CONNECTION \
    DBUS_LIMIT_MAX_REPLIES_PER_CONNECTION \
    DBUS_LIMIT_MAX_INCOMPLETE_CONNECTIONS \
    DBUS_LIMIT_MAX_COMPLETED_CONNECTIONS \
    DBUS_LIMIT_MAX_CONNECTIONS_PER_USER \
    DBUS_LIMIT_MAX_PENDING_SERVICE_STARTS \
    DBUS_LIMIT_AUTH_TIMEOUT_MS \
    DBUS_LIMIT_PENDING_FD_TIMEOUT_MS \
    DBUS_LIMIT_SERVICE_START_TIMEOUT_MS \
    DBUS_LIMIT_REPLY_TIMEOUT_MS \
    DBUS_BROKER_TASKS_MAX \
    DBUS_BROKER_LIMIT_NOFILE
  do
    eval "var_value=\${$var_name-}"
    [ -n "$var_value" ] || installer_fatal "${var_name} must be set before D-Bus template rendering"
    printf '%s=%s\n' "$var_name" "$var_value"
  done
}

render_target_asset_with_placeholders() {
  repo_path=$1
  target_path=$2
  mode=$3
  map_func=$4
  tmp_asset="${TMP_ENV_DIR}/asset.$$.tmp"
  tmp_rendered="${TMP_ENV_DIR}/asset.$$.rendered"

  fetch_hook "$repo_path" "$tmp_asset"
  cp "$tmp_asset" "$tmp_rendered"
  while IFS= read -r map_line || [ -n "$map_line" ]; do
    map_name=${map_line%%=*}
    map_value=${map_line#*=}
    [ -n "$map_name" ] || continue
    installer_replace_placeholder_in_file \
      "$tmp_rendered" \
      "__INSTALLER_${map_name}__" \
      "$map_value" || {
        rm -f "$tmp_asset" "$tmp_rendered"
        installer_fatal "failed to render D-Bus template placeholder ${map_name} for ${repo_path}"
      }
  done <<EOF
$("$map_func")
EOF
  ensure_target_asset_parent "$target_path"
  install -m "$mode" "$tmp_rendered" "/target${target_path}"
  rm -f "$tmp_asset" "$tmp_rendered"
}

render_dbus_target_asset() {
  render_target_asset_with_placeholders "$1" "$2" "$3" dbus_broker_placeholder_map
}

verify_target_apt_preferences() {
  command -v installer_configured_apt_preferences >/dev/null 2>&1 ||
    installer_fatal "installer_configured_apt_preferences is unavailable"
  configured_preferences=$(installer_configured_apt_preferences)

  # shellcheck disable=SC2016
  run_in_target "verify target apt preferences" /bin/sh -c '
	set -eu
	preferences_dir=$1
	configured_preferences=$2

for pref_name in $configured_preferences; do
  [ -r "${preferences_dir}/${pref_name}" ] || {
    printf "missing target apt preference: %s\n" "${preferences_dir}/${pref_name}" >&2
    exit 1
  }
done
  ' sh "${DIR_APT_PREFERENCES_D}" "$configured_preferences"
}

repair_target_dbus_broker_packages() {
  require_in_target "dbus-broker package repair"

  prepare_target_volatile_dirs_for_apt
  run_in_target "install dbus-broker target packages" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y install --no-install-recommends \
        dbus-broker \
        dbus-user-session \
        dbus-bin \
        dbus-system-bus-common \
        dbus-session-bus-common

  run_in_target "purge reference D-Bus daemon packages if present" \
    env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get \
      -o Acquire::Retries=5 \
      -o Acquire::http::Timeout=45 \
      -o Acquire::https::Timeout=45 \
      -o Binary::apt::APT::Keep-Downloaded-Packages=false \
      -o DPkg::Use-Pty=0 \
      -y purge dbus dbus-daemon dbus-x11
}

stage_target_dbus_session_service_aliases() {
  # shellcheck disable=SC2016
  run_in_target "stage dbus-broker session service compatibility aliases" /bin/sh -c '
set -eu
session_service_dir=$1
local_service_dir=$2
shift 2
aliases_staged=0

extract_name() {
  service_path=$1
  sed -n "s/^[[:space:]]*Name[[:space:]]*=[[:space:]]*//p" "$service_path" | sed -n "1p"
}

[ -d "$session_service_dir" ] || exit 0
command -v dpkg-divert >/dev/null 2>&1 || {
  printf "fatal: dpkg-divert is required for D-Bus service alias staging\n" >&2
  exit 1
}
install -d -m 0755 "$local_service_dir"

for service_spec in "$@"; do
  service_file=${service_spec%%:*}
  expected_name=${service_spec#*:}
  source_path="${session_service_dir}/${service_file}"
  divert_path="${source_path}.distrib"
  alias_path="${local_service_dir}/${expected_name}.service"

  case "$service_file:$expected_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-]*)
      printf "fatal: unsafe D-Bus session service alias spec: %s\n" "$service_spec" >&2
      exit 1
      ;;
  esac

  if [ -r "$source_path" ]; then
    actual_name=$(extract_name "$source_path")
    [ "$actual_name" = "$expected_name" ] || {
      printf "fatal: unexpected D-Bus Name in %s: got %s, expected %s\n" "$source_path" "${actual_name:-unset}" "$expected_name" >&2
      exit 1
    }
    if ! dpkg-divert --list "$source_path" 2>/dev/null | grep -Fq "$divert_path"; then
      dpkg-divert --quiet --rename --add --divert "$divert_path" "$source_path"
    fi
  fi

  [ -r "$divert_path" ] || continue
  actual_name=$(extract_name "$divert_path")
  [ "$actual_name" = "$expected_name" ] || {
    printf "fatal: unexpected D-Bus Name in %s: got %s, expected %s\n" "$divert_path" "${actual_name:-unset}" "$expected_name" >&2
    exit 1
  }

  [ ! -d "$alias_path" ] || {
    printf "fatal: D-Bus service alias path is a directory: %s\n" "$alias_path" >&2
    exit 1
  }
  tmp_alias="${alias_path}.$$"
  rm -f "$tmp_alias"
  ln -s "$divert_path" "$tmp_alias"
  mv -f "$tmp_alias" "$alias_path"
  aliases_staged=$((aliases_staged + 1))
done

printf "dbus_session_service_aliases_staged=%s\n" "$aliases_staged"
' sh \
    "${DIR_DBUS_SESSION_SERVICES}" \
    "${DIR_DBUS_LOCAL_SESSION_SERVICES}" \
    "fr.emersion.mako.service:org.freedesktop.Notifications" \
    "org.xfce.Thunar.FileManager1.service:org.freedesktop.FileManager1" \
    "org.xfce.Tumbler.Cache1.service:org.freedesktop.thumbnails.Cache1" \
    "org.xfce.Tumbler.Manager1.service:org.freedesktop.thumbnails.Manager1" \
    "org.xfce.Tumbler.Thumbnailer1.service:org.freedesktop.thumbnails.Thumbnailer1"
}

sanitize_target_dbus_session_conf() {
  # shellcheck disable=SC2016
  run_in_target "sanitize dbus-broker session.conf eavesdrop policy" /bin/sh -c '
set -eu
session_conf=/usr/share/dbus-1/session.conf
divert_conf=/usr/share/dbus-1/session.conf.distrib

[ -r "$session_conf" ] || exit 0
if ! grep -Eq "eavesdrop[[:space:]]*=" "$session_conf"; then
  exit 0
fi
command -v dpkg-divert >/dev/null 2>&1 || {
  printf "fatal: dpkg-divert is required to sanitize %s\n" "$session_conf" >&2
  exit 1
}
if ! dpkg-divert --list "$session_conf" 2>/dev/null | grep -Fq "$divert_conf"; then
  dpkg-divert --quiet --rename --add --divert "$divert_conf" "$session_conf"
fi
[ -r "$divert_conf" ] || {
  printf "fatal: diverted D-Bus session config is missing: %s\n" "$divert_conf" >&2
  exit 1
}
tmp_conf=$(mktemp /tmp/dbus-session-conf.XXXXXX)
trap '\''rm -f "$tmp_conf"'\'' EXIT HUP INT TERM
python3 -c "
import pathlib
import re
import sys
source_path = pathlib.Path(sys.argv[1])
target_path = pathlib.Path(sys.argv[2])
single_quote = chr(39)
space_pattern = r\"\\s+\"
output_lines = []
for raw_line in source_path.read_text(encoding=\"utf-8\").splitlines():
    if re.search(r\"<allow[^>]*eavesdrop\\s*=\", raw_line):
        stripped = re.sub(space_pattern + r\"eavesdrop=\\\"[^\\\"]*\\\"\", \"\", raw_line)
        stripped = re.sub(space_pattern + \"eavesdrop=\" + single_quote + \"[^\" + single_quote + \"]*\" + single_quote, \"\", stripped)
        if re.search(r\"<allow\\s*/>\", stripped):
            output_lines.extend([
                \"    <allow receive_type=\\\"method_call\\\"/>\",
                \"    <allow receive_type=\\\"method_return\\\"/>\",
                \"    <allow receive_type=\\\"error\\\"/>\",
                \"    <allow receive_type=\\\"signal\\\"/>\",
            ])
        else:
            output_lines.append(stripped)
        continue
    output_lines.append(raw_line)
target_path.write_text(\"\\n\".join(output_lines) + \"\\n\", encoding=\"utf-8\")
" "$divert_conf" "$tmp_conf"
grep -q "<busconfig" "$tmp_conf" || {
  printf "fatal: sanitized D-Bus session config lost busconfig root\n" >&2
  exit 1
}
if grep -Eq "eavesdrop[[:space:]]*=" "$tmp_conf"; then
  printf "fatal: sanitized D-Bus session config still contains eavesdrop policy\n" >&2
  exit 1
fi
if grep -Eq "<(allow|deny)[[:space:]]*/>" "$tmp_conf"; then
  printf "fatal: sanitized D-Bus session config contains attribute-free policy rules\n" >&2
  exit 1
fi
if grep -Eq "<allow[^>]+send_destination=\"\\*\"" "$divert_conf" &&
   ! grep -Eq "<allow[^>]+send_destination=\"\\*\"" "$tmp_conf"; then
  printf "fatal: sanitized D-Bus session config removed the default send allow rule\n" >&2
  exit 1
fi
if grep -Eq "<allow[^>]+own=\"\\*\"" "$divert_conf" &&
   ! grep -Eq "<allow[^>]+own=\"\\*\"" "$tmp_conf"; then
  printf "fatal: sanitized D-Bus session config removed the default own allow rule\n" >&2
  exit 1
fi
if grep -Eq "<allow[[:space:]]+eavesdrop=" "$divert_conf"; then
  for receive_type in method_call method_return error signal; do
    if ! grep -Eq "<allow[^>]+receive_type=\"${receive_type}\"" "$tmp_conf"; then
      printf "fatal: sanitized D-Bus session config removed default receive allow for %s\n" "$receive_type" >&2
      exit 1
    fi
  done
fi
install -m 0644 "$tmp_conf" "$session_conf"
printf "dbus_session_conf_sanitized=%s\n" "$session_conf"
' sh
}

verify_target_dbus_session_service_aliases() {
  # shellcheck disable=SC2016
  run_in_target "verify dbus-broker session service compatibility aliases" /bin/sh -c '
set -eu
session_service_dir=$1
local_service_dir=$2
shift 2

extract_name() {
  service_path=$1
  sed -n "s/^[[:space:]]*Name[[:space:]]*=[[:space:]]*//p" "$service_path" | sed -n "1p"
}

[ -d "$session_service_dir" ] || exit 0
[ -d "$local_service_dir" ] || {
  printf "missing local dbus service alias directory: %s\n" "$local_service_dir" >&2
  exit 1
}

for service_spec in "$@"; do
  service_file=${service_spec%%:*}
  expected_name=${service_spec#*:}
  source_path="${session_service_dir}/${service_file}"
  divert_path="${source_path}.distrib"
  alias_path="${local_service_dir}/${expected_name}.service"

  if [ -r "$source_path" ]; then
    source_payload=$source_path
  elif [ -r "$divert_path" ]; then
    source_payload=$divert_path
  else
    continue
  fi
  [ -r "$alias_path" ] || {
    printf "missing dbus service alias: %s\n" "$alias_path" >&2
    exit 1
  }
  [ -L "$alias_path" ] || {
    printf "dbus service alias is not a symlink: %s\n" "$alias_path" >&2
    exit 1
  }
  alias_target=$(readlink "$alias_path")
  [ "$alias_target" = "$divert_path" ] || {
    printf "dbus service alias %s points to %s, expected %s\n" "$alias_path" "$alias_target" "$divert_path" >&2
    exit 1
  }

  source_name=$(extract_name "$source_payload")
  alias_name=$(extract_name "$alias_path")
  [ "$source_name" = "$expected_name" ] || {
    printf "unexpected dbus Name in source %s: %s\n" "$source_payload" "${source_name:-unset}" >&2
    exit 1
  }
  [ "$alias_name" = "$expected_name" ] || {
    printf "unexpected dbus Name in alias %s: %s\n" "$alias_path" "${alias_name:-unset}" >&2
    exit 1
  }
done
' sh \
    "${DIR_DBUS_SESSION_SERVICES}" \
    "${DIR_DBUS_LOCAL_SESSION_SERVICES}" \
    "fr.emersion.mako.service:org.freedesktop.Notifications" \
    "org.xfce.Thunar.FileManager1.service:org.freedesktop.FileManager1" \
    "org.xfce.Tumbler.Cache1.service:org.freedesktop.thumbnails.Cache1" \
    "org.xfce.Tumbler.Manager1.service:org.freedesktop.thumbnails.Manager1" \
    "org.xfce.Tumbler.Thumbnailer1.service:org.freedesktop.thumbnails.Thumbnailer1"
}

target_user_unit_exists() {
  unit=$1

  target_systemd_unit_path "$unit" user >/dev/null 2>&1
}

validate_systemd_unit_name() {
  systemd_unit_name=$1

  case "$systemd_unit_name" in
    ''|/*|*/*|*..*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@:-]*)
      installer_fatal "unsafe systemd unit name for staged enablement: ${systemd_unit_name}"
      ;;
  esac
}

target_systemd_scope_base_dir() {
  case "$1" in
    system) printf '%s\n' "${DIR_SYSTEMD_SYSTEM}" ;;
    user) printf '%s\n' "${DIR_SYSTEMD_USER}" ;;
    *) installer_fatal "unsupported systemd scope for staged enablement: $1" ;;
  esac
}

target_systemd_scope_unit_dirs() {
  case "$1" in
    system)
      printf '%s\n' "${DIR_SYSTEMD_SYSTEM}"
      printf '%s\n' "${DIR_SYSTEMD_SYSTEM_LEGACY}"
      printf '%s\n' "${DIR_SYSTEMD_SYSTEM_LIB}"
      ;;
    user)
      printf '%s\n' "${DIR_SYSTEMD_USER}"
      printf '%s\n' "${DIR_SYSTEMD_USER_LEGACY}"
      printf '%s\n' "${DIR_SYSTEMD_USER_LIB}"
      ;;
    *)
      installer_fatal "unsupported systemd scope for staged unit lookup: $1"
      ;;
  esac
}

target_systemd_unit_path_allowed() {
  unit_path=$1
  scope=$2

  case "$scope" in
    system)
      case "$unit_path" in
        "${DIR_SYSTEMD_SYSTEM}"/*|"${DIR_SYSTEMD_SYSTEM_LEGACY}"/*|"${DIR_SYSTEMD_SYSTEM_LIB}"/*)
          return 0
          ;;
      esac
      ;;
    user)
      case "$unit_path" in
        "${DIR_SYSTEMD_USER}"/*|"${DIR_SYSTEMD_USER_LEGACY}"/*|"${DIR_SYSTEMD_USER_LIB}"/*)
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

target_systemd_normalize_unit_path() {
  unit_path=$1
  target_systemd_normalized_unit_path=
  normalized=$(readlink -f "/target${unit_path}" 2>/dev/null || true)

  case "$normalized" in
    /target/*)
      target_systemd_normalized_unit_path=${normalized#/target}
      return 0
      ;;
  esac

  return 1
}

target_systemd_resolve_unit_path() {
  unit_path=$1
  scope=$2
  resolve_depth=0
  target_systemd_resolved_unit_path=

  target_systemd_unit_path_allowed "$unit_path" "$scope" || \
    installer_fatal "target systemd unit path escapes ${scope} scope: ${unit_path}"
  if target_systemd_normalize_unit_path "$unit_path"; then
    unit_path=$target_systemd_normalized_unit_path
    target_systemd_unit_path_allowed "$unit_path" "$scope" || \
      installer_fatal "target systemd unit path escapes ${scope} scope after normalization: ${unit_path}"
  fi

  while [ -L "/target${unit_path}" ]; do
    [ "$resolve_depth" -lt 16 ] || installer_fatal "too many target systemd unit symlink hops: ${unit_path}"
    link_target=$(readlink "/target${unit_path}") || \
      installer_fatal "unable to read target systemd unit symlink: ${unit_path}"
    case "$link_target" in
      ''|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@:-]*)
        installer_fatal "unsafe target systemd unit symlink target for ${unit_path}: ${link_target}"
        ;;
      /*)
        next_unit_path=$link_target
        ;;
      *)
        next_unit_path=${unit_path%/*}/${link_target}
        ;;
    esac
    case "$next_unit_path" in
      /*) ;;
      *) installer_fatal "resolved target systemd unit path is not absolute: ${next_unit_path}" ;;
    esac
    if target_systemd_normalize_unit_path "$next_unit_path"; then
      unit_path=$target_systemd_normalized_unit_path
    else
      case "$next_unit_path" in
        *..*)
          installer_fatal "unable to normalize relative target systemd unit symlink: ${next_unit_path}"
          ;;
        *)
          unit_path=$next_unit_path
          ;;
      esac
    fi
    target_systemd_unit_path_allowed "$unit_path" "$scope" || \
      installer_fatal "target systemd unit symlink escapes ${scope} scope: ${unit_path}"
    validate_systemd_unit_name "${unit_path##*/}"
    resolve_depth=$((resolve_depth + 1))
  done

  [ -e "/target${unit_path}" ] || return 1
  target_systemd_resolved_unit_path=$unit_path
  return 0
}

target_systemd_link_target_path() {
  link_path=$1
  target_systemd_link_target_unit_path=

  case "$link_path" in
    /target/*)
      link_unit_path=${link_path#/target}
      ;;
    *)
      installer_fatal "target systemd link path is outside /target: ${link_path}"
      ;;
  esac

  link_target=$(readlink "$link_path") || \
    installer_fatal "unable to read staged systemd unit link: ${link_path#/target}"
  case "$link_target" in
    ''|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@:-]*)
      installer_fatal "unsafe staged systemd unit link target for ${link_path#/target}: ${link_target}"
      ;;
    /*)
      target_systemd_link_target_unit_path=$link_target
      ;;
    *)
      target_systemd_link_target_unit_path=${link_unit_path%/*}/${link_target}
      ;;
  esac
}

verify_target_systemd_unit_link() {
  link_path=$1
  expected_unit_path=$2
  scope=$3
  link_description=$4

  [ -L "$link_path" ] || installer_fatal "staged ${scope} unit ${link_description} is missing: ${link_path#/target}"
  target_systemd_link_target_path "$link_path"
  actual_unit_path=$target_systemd_link_target_unit_path

  if target_systemd_resolve_unit_path "$actual_unit_path" "$scope"; then
    actual_unit_path=$target_systemd_resolved_unit_path
  else
    installer_fatal "staged ${scope} unit ${link_description} ${link_path#/target} points to missing unit path: ${actual_unit_path}"
  fi
  if target_systemd_resolve_unit_path "$expected_unit_path" "$scope"; then
    expected_unit_path=$target_systemd_resolved_unit_path
  else
    installer_fatal "expected target ${scope} unit path is missing during staged-enable verification: ${expected_unit_path}"
  fi

  [ "$actual_unit_path" = "$expected_unit_path" ] || \
    installer_fatal "staged ${scope} unit ${link_description} ${link_path#/target} points to ${actual_unit_path}, expected ${expected_unit_path}"
}

target_systemd_unit_path() {
  unit=$1
  scope=$2

  validate_systemd_unit_name "$unit"
  for unit_dir in $(target_systemd_scope_unit_dirs "$scope"); do
    [ -n "$unit_dir" ] || continue
    unit_path="${unit_dir}/${unit}"
    if [ -e "/target${unit_path}" ] || [ -L "/target${unit_path}" ]; then
      if target_systemd_resolve_unit_path "$unit_path" "$scope"; then
        printf '%s\n' "$target_systemd_resolved_unit_path"
        return 0
      fi
    fi
  done
  return 1
}

target_systemd_install_values() {
  unit_path=$1
  key=$2

  [ -r "/target${unit_path}" ] || installer_fatal "target systemd unit is unreadable: ${unit_path}"
  in_install=false
  while IFS= read -r unit_line || [ -n "$unit_line" ]; do
    unit_line=$(printf '%s' "$unit_line" | sed 's/\r$//')
    unit_trimmed=$(installer_trim_whitespace "$unit_line")
    case "$unit_trimmed" in
      \[*\])
        [ "$unit_trimmed" = "[Install]" ] && in_install=true || in_install=false
        continue
        ;;
    esac
    [ "$in_install" = true ] || continue
    value_line=$(printf '%s\n' "$unit_line" | sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p")
    [ -n "$value_line" ] || continue
    value_line=$(printf '%s' "$value_line" | sed 's/[[:space:]]*[#;].*$//')
    for value in $value_line; do
      printf '%s\n' "$value"
    done
  done <"/target${unit_path}"
}

stage_target_systemd_unit_enabled() {
  unit=$1
  scope=${2:-system}
  unit_path=$(target_systemd_unit_path "$unit" "$scope" || true)
  base_dir=$(target_systemd_scope_base_dir "$scope")
  staged=false

  [ -n "$unit_path" ] || installer_fatal "expected target ${scope} unit is missing: ${unit}"

  for wanted_by in $(target_systemd_install_values "$unit_path" WantedBy); do
    validate_systemd_unit_name "$wanted_by"
    install -d -m 0755 "/target${base_dir}/${wanted_by}.wants"
    ln -sf "$unit_path" "/target${base_dir}/${wanted_by}.wants/${unit}"
    staged=true
  done

  for required_by in $(target_systemd_install_values "$unit_path" RequiredBy); do
    validate_systemd_unit_name "$required_by"
    install -d -m 0755 "/target${base_dir}/${required_by}.requires"
    ln -sf "$unit_path" "/target${base_dir}/${required_by}.requires/${unit}"
    staged=true
  done

  for alias_name in $(target_systemd_install_values "$unit_path" Alias); do
    validate_systemd_unit_name "$alias_name"
    install -d -m 0755 "/target${base_dir}"
    ln -sf "$unit_path" "/target${base_dir}/${alias_name}"
    staged=true
  done

  for also_unit in $(target_systemd_install_values "$unit_path" Also); do
    validate_systemd_unit_name "$also_unit"
    [ "$also_unit" = "$unit" ] && continue
    if [ -z "$(target_systemd_unit_path "$also_unit" "$scope" || true)" ]; then
      continue
    fi
    stage_target_systemd_unit_enabled "$also_unit" "$scope"
    staged=true
  done

  [ "$staged" = true ] || installer_fatal "target ${scope} unit has no supported [Install] entries: ${unit}"
  verify_target_systemd_unit_enabled "$unit" "$scope"
}

stage_target_systemd_unit_wanted_by() {
  unit=$1
  scope=$2
  wanted_by=$3
  unit_path=$(target_systemd_unit_path "$unit" "$scope" || true)
  base_dir=$(target_systemd_scope_base_dir "$scope")

  validate_systemd_unit_name "$unit"
  validate_systemd_unit_name "$wanted_by"
  [ -n "$unit_path" ] || installer_fatal "expected target ${scope} unit is missing: ${unit}"

  install -d -m 0755 "/target${base_dir}/${wanted_by}.wants"
  ln -sf "$unit_path" "/target${base_dir}/${wanted_by}.wants/${unit}"
  verify_target_systemd_unit_link "/target${base_dir}/${wanted_by}.wants/${unit}" "$unit_path" "$scope" "${wanted_by} requirement"
}

stage_target_systemd_unit_alias_to_path() {
  alias_name=$1
  scope=$2
  unit_path=$3
  base_dir=$(target_systemd_scope_base_dir "$scope")

  validate_systemd_unit_name "$alias_name"
  [ -n "$unit_path" ] || installer_fatal "expected target ${scope} unit path for alias ${alias_name} is missing"

  install -d -m 0755 "/target${base_dir}"
  ln -sf "$unit_path" "/target${base_dir}/${alias_name}"
  verify_target_systemd_unit_link "/target${base_dir}/${alias_name}" "$unit_path" "$scope" "alias"
}

verify_target_systemd_unit_enabled() {
  unit=$1
  scope=${2:-system}
  unit_path=$(target_systemd_unit_path "$unit" "$scope" || true)
  base_dir=$(target_systemd_scope_base_dir "$scope")

  [ -n "$unit_path" ] || installer_fatal "expected target ${scope} unit is missing during staged-enable verification: ${unit}"

  for wanted_by in $(target_systemd_install_values "$unit_path" WantedBy); do
    validate_systemd_unit_name "$wanted_by"
    link_path="/target${base_dir}/${wanted_by}.wants/${unit}"
    verify_target_systemd_unit_link "$link_path" "$unit_path" "$scope" "enablement link"
  done

  for required_by in $(target_systemd_install_values "$unit_path" RequiredBy); do
    validate_systemd_unit_name "$required_by"
    link_path="/target${base_dir}/${required_by}.requires/${unit}"
    verify_target_systemd_unit_link "$link_path" "$unit_path" "$scope" "requirement link"
  done

  for alias_name in $(target_systemd_install_values "$unit_path" Alias); do
    validate_systemd_unit_name "$alias_name"
    link_path="/target${base_dir}/${alias_name}"
    verify_target_systemd_unit_link "$link_path" "$unit_path" "$scope" "alias"
  done
}

unstage_target_systemd_unit_enabled() {
  unit=$1
  scope=${2:-system}
  base_dir=$(target_systemd_scope_base_dir "$scope")

  validate_systemd_unit_name "$unit"
  for link_dir in "/target${base_dir}"/*.wants "/target${base_dir}"/*.requires; do
    [ -d "$link_dir" ] || continue
    rm -f "${link_dir}/${unit}"
  done
}

stage_target_default_systemd_unit() {
  unit=$1
  unit_path=$(target_systemd_unit_path "$unit" system || true)
  default_link="/target${DIR_SYSTEMD_SYSTEM}/default.target"

  [ -n "$unit_path" ] || installer_fatal "expected target default unit target is missing: ${unit}"
  install -d -m 0755 "/target${DIR_SYSTEMD_SYSTEM}"
  ln -sfn "$unit_path" "$default_link"
  [ -L "$default_link" ] || installer_fatal "default.target staged symlink is missing"
  [ "$(readlink "$default_link")" = "$unit_path" ] || installer_fatal "default.target does not point to ${unit_path}"
}

enable_target_dbus_broker_units() {
  system_broker_unit_path=$(target_systemd_unit_path "dbus-broker.service" system || true)
  user_broker_unit_path=$(target_systemd_unit_path "dbus-broker.service" user || true)
  system_socket_unit_path=$(target_systemd_unit_path "dbus.socket" system || true)
  user_socket_unit_path=$(target_systemd_unit_path "dbus.socket" user || true)

  [ -n "$system_socket_unit_path" ] || installer_fatal "expected target dbus.socket is missing"
  [ -n "$system_broker_unit_path" ] || installer_fatal "expected target dbus-broker.service is missing"
  [ -n "$user_socket_unit_path" ] || installer_fatal "expected target user dbus.socket is missing"
  [ -n "$user_broker_unit_path" ] || installer_fatal "expected target user dbus-broker.service is missing"
  [ "$system_broker_unit_path" = "${DIR_SYSTEMD_SYSTEM_LIB}/dbus-broker.service" ] || \
    installer_fatal "system dbus-broker.service must resolve to ${DIR_SYSTEMD_SYSTEM_LIB}/dbus-broker.service, got ${system_broker_unit_path}"
  [ "$user_broker_unit_path" = "${DIR_SYSTEMD_USER_LIB}/dbus-broker.service" ] || \
    installer_fatal "user dbus-broker.service must resolve to ${DIR_SYSTEMD_USER_LIB}/dbus-broker.service, got ${user_broker_unit_path}"

  stage_target_systemd_unit_wanted_by dbus.socket system sockets.target
  stage_target_systemd_unit_wanted_by dbus.socket user sockets.target
  stage_target_systemd_unit_alias_to_path dbus.service system "$system_broker_unit_path"
  stage_target_systemd_unit_alias_to_path dbus.service user "$user_broker_unit_path"

  verify_target_dbus_broker_aliases "$system_broker_unit_path" "$user_broker_unit_path"
  verify_target_dbus_broker_socket_activation \
    "$system_broker_unit_path" \
    "$user_broker_unit_path" \
    "$system_socket_unit_path" \
    "$user_socket_unit_path" \
    "${FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE}" \
    "${FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE}"
}

verify_target_dbus_broker_aliases() {
  system_broker_unit_path=$1
  user_broker_unit_path=$2

  # shellcheck disable=SC2016
  run_in_target "verify dbus-broker systemd aliases" /bin/sh -c '
set -eu
system_alias_path=$1
user_alias_path=$2
expected_system_unit=$3
expected_user_unit=$4
system_alias_literal=$(readlink "$system_alias_path" 2>/dev/null || true)
user_alias_literal=$(readlink "$user_alias_path" 2>/dev/null || true)
system_alias=$(readlink -f "$system_alias_path" 2>/dev/null || true)
user_alias=$(readlink -f "$user_alias_path" 2>/dev/null || true)
expected_system_unit=$(readlink -f "$expected_system_unit" 2>/dev/null || true)
expected_user_unit=$(readlink -f "$expected_user_unit" 2>/dev/null || true)

[ -n "$expected_system_unit" ] || {
  printf "expected system dbus-broker unit is missing: %s\n" "$3" >&2
  exit 1
}
[ -n "$expected_user_unit" ] || {
  printf "expected user dbus-broker unit is missing: %s\n" "$4" >&2
  exit 1
}
[ "$system_alias_literal" = "$3" ] || {
  printf "dbus.service system alias target must be %s, got %s\n" "$3" "${system_alias_literal:-missing}" >&2
  exit 1
}
[ "$user_alias_literal" = "$4" ] || {
  printf "dbus.service user alias target must be %s, got %s\n" "$4" "${user_alias_literal:-missing}" >&2
  exit 1
}
[ "$system_alias" = "$expected_system_unit" ] || {
  printf "dbus.service system alias does not point to %s: %s\n" "$expected_system_unit" "${system_alias:-missing}" >&2
  exit 1
}
[ "$user_alias" = "$expected_user_unit" ] || {
  printf "dbus.service user alias does not point to %s: %s\n" "$expected_user_unit" "${user_alias:-missing}" >&2
  exit 1
}
  ' sh \
    "${FILE_DBUS_SYSTEM_SERVICE_ALIAS}" \
    "${FILE_DBUS_USER_SERVICE_ALIAS}" \
    "$system_broker_unit_path" \
    "$user_broker_unit_path"
}

verify_target_dbus_broker_socket_activation() {
  system_broker_unit_path=$1
  user_broker_unit_path=$2
  system_socket_unit_path=$3
  user_socket_unit_path=$4
  system_broker_override_path=$5
  user_broker_override_path=$6

  # shellcheck disable=SC2016
  run_in_target "verify dbus-broker socket activation" /bin/sh -c '
set -eu
system_broker_unit=$1
user_broker_unit=$2
system_socket_unit=$3
user_socket_unit=$4
system_broker_override=$5
user_broker_override=$6

verify_socket_link() {
  link_path=$1
  expected_unit=$2
  link_target=$(readlink -f "$link_path" 2>/dev/null || true)
  expected_target=$(readlink -f "$expected_unit" 2>/dev/null || true)
  [ -n "$link_target" ] || {
    printf "dbus socket activation link is missing: %s\n" "$link_path" >&2
    exit 1
  }
  [ -n "$expected_target" ] || {
    printf "expected dbus socket unit is missing: %s\n" "$expected_unit" >&2
    exit 1
  }
  [ "$link_target" = "$expected_target" ] || {
    printf "dbus socket activation link %s points to %s, expected %s\n" "$link_path" "$link_target" "$expected_target" >&2
    exit 1
  }
}

verify_absent_link() {
  link_path=$1
  [ ! -e "$link_path" ] && [ ! -L "$link_path" ] && return 0
  printf "dbus-broker.service must be socket/alias activated, but direct enablement exists: %s\n" "$link_path" >&2
  exit 1
}

for unit_path in "$system_broker_unit" "$user_broker_unit" "$system_socket_unit" "$user_socket_unit" "$system_broker_override" "$user_broker_override"; do
  [ -r "$unit_path" ] || {
    printf "expected dbus unit path is unreadable: %s\n" "$unit_path" >&2
    exit 1
  }
done

verify_socket_link /etc/systemd/system/sockets.target.wants/dbus.socket "$system_socket_unit"
verify_socket_link /etc/systemd/user/sockets.target.wants/dbus.socket "$user_socket_unit"
verify_absent_link /etc/systemd/system/multi-user.target.wants/dbus-broker.service
verify_absent_link /etc/systemd/user/default.target.wants/dbus-broker.service
' sh \
    "$system_broker_unit_path" \
    "$user_broker_unit_path" \
    "$system_socket_unit_path" \
    "$user_socket_unit_path" \
    "$system_broker_override_path" \
    "$user_broker_override_path"
}

configure_target_dbus_broker() {
  validate_dbus_broker_policy_env

  # late_command runs against a chrooted target, not a live booted system:
  # stage files and validate metadata only, without assuming services are running.
  verify_target_apt_preferences
  repair_target_dbus_broker_packages
  sanitize_target_dbus_session_conf
  stage_target_dbus_session_service_aliases
  render_dbus_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/dbus-1/system-local.conf.tmpl)" "${FILE_DBUS_SYSTEM_LOCAL_CONF}" 0644
  render_dbus_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/dbus-broker.service.d/10-broker-hardening.conf.tmpl)" "${FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE}" 0644
  render_dbus_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl)" "${FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE}" 0644

  enable_target_dbus_broker_units

  verify_target_dbus_broker_staging
  verify_target_dbus_session_service_aliases
}

verify_target_dbus_broker_staging() {
  # shellcheck disable=SC2016
  run_in_target "verify staged dbus-broker payload" /bin/sh -c '
set -eu
system_local_conf=$1
system_broker_override=$2
user_broker_override=$3
blocked_package_pref=$4

for path in \
  "$blocked_package_pref" \
  "$system_local_conf" \
  "$system_broker_override" \
  "$user_broker_override"
do
  [ -r "$path" ] || {
    printf "missing staged D-Bus payload: %s\n" "$path" >&2
    exit 1
  }
done

[ -x "/usr/bin/dbus-broker" ] || {
  printf "dbus-broker binary is missing from target\n" >&2
  exit 1
}
[ -x "/usr/bin/dbus-broker-launch" ] || {
  printf "dbus-broker-launch binary is missing from target\n" >&2
  exit 1
}
[ -r "/usr/share/dbus-1/system.conf" ] || {
  printf "system bus configuration is missing from target\n" >&2
  exit 1
}
if [ -r "/usr/share/dbus-1/session.conf" ] &&
   grep -Eq "eavesdrop[[:space:]]*=" "/usr/share/dbus-1/session.conf"; then
  printf "session bus configuration still contains broker-ignored eavesdrop policy\n" >&2
  exit 1
fi
' sh \
    "${FILE_DBUS_SYSTEM_LOCAL_CONF}" \
    "${FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE}" \
    "${FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE}" \
    "${FILE_DBUS_BLOCKED_PACKAGES_APT_PREFERENCE}"
}
