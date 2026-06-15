#!/bin/sh
# Shared late_command network handoff helpers. This file is sourced.

target_network_selected_class() {
  installer_selected_class_for_purpose network 2>/dev/null || printf '%s' "${INSTALLER_NETWORK_CLASS:-}"
}

target_wifi_handoff_requested() {
  installer_selected_class_reference_is_selected addon/wifi 2>/dev/null
}

target_static_network_selected() {
  network_class=$(target_network_selected_class)
  [ "$network_class" = static ] && return 0
  installer_selected_class_reference_is_selected network/static 2>/dev/null
}

target_preseed_network_handoff_requested() {
  target_static_network_selected || target_wifi_handoff_requested
}

target_preseed_network_mode() {
  if target_static_network_selected || target_wifi_handoff_requested; then
    printf '%s\n' static
  else
    printf '%s\n' dhcp
  fi
}

target_preseed_network_link_type() {
  link_types=$(target_preseed_network_link_types)
  printf '%s\n' "${link_types%% *}"
}

target_preseed_network_link_types() {
  static_selected=false
  wifi_selected=false
  target_static_network_selected && static_selected=true
  target_wifi_handoff_requested && wifi_selected=true

  if [ "$static_selected" = true ]; then
    if [ "$wifi_selected" = true ]; then
      printf '%s\n' "ethernet wifi"
    else
      printf '%s\n' ethernet
    fi
  elif [ "$wifi_selected" = true ]; then
    printf '%s\n' wifi
  else
    printf '%s\n' ethernet
  fi
}

network_link_types_has() {
  link_types=$1
  wanted=$2

  case " ${link_types} " in
    *" ${wanted} "*) return 0 ;;
  esac
  return 1
}

target_host_variant_class() {
  installer_selected_class_for_purpose host-variant 2>/dev/null || printf '%s\n' "${INSTALLER_HOST_VARIANT:-}"
}

network_answer_value() {
  for answer_key in "$@"; do
    value=$(installer_cmdline_value "$answer_key" 2>/dev/null || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  for answer_key in "$@"; do
    value=$(installer_debconf_value "$answer_key" 2>/dev/null || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

valid_installer_network_interface_name() {
  iface=$1

  case "$iface" in
    ''|.|..|lo|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
      return 1
      ;;
  esac
  [ "${#iface}" -le 15 ] || return 1
  return 0
}

installer_interface_is_wireless() {
  iface=$1
  valid_installer_network_interface_name "$iface" || return 1

  [ -d "/sys/class/net/${iface}/wireless" ] || [ -d "/sys/class/net/${iface}/phy80211" ]
}

installer_interface_matches_link_type() {
  iface=$1
  link_type=$2
  type_file="/sys/class/net/${iface}/type"
  device_path="/sys/class/net/${iface}/device"

  valid_installer_network_interface_name "$iface" || return 1
  [ -r "$type_file" ] || return 1
  [ -e "$device_path" ] || return 1
  IFS= read -r iface_type <"$type_file" || return 1
  [ "$iface_type" = 1 ] || return 1

  case "$link_type" in
    wifi)
      installer_interface_is_wireless "$iface"
      ;;
    ethernet)
      installer_interface_is_wireless "$iface" && return 1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

valid_installer_mac_address() {
  mac=$1

  case "$mac" in
    00:00:00:00:00:00)
      return 1
      ;;
    [0123456789abcdefABCDEF][0123456789abcdefABCDEF]:[0123456789abcdefABCDEF][0123456789abcdefABCDEF]:[0123456789abcdefABCDEF][0123456789abcdefABCDEF]:[0123456789abcdefABCDEF][0123456789abcdefABCDEF]:[0123456789abcdefABCDEF][0123456789abcdefABCDEF]:[0123456789abcdefABCDEF][0123456789abcdefABCDEF])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

installer_default_route_interface() {
  command -v ip >/dev/null 2>&1 || return 1
  ip -4 route show default 2>/dev/null | sed -n '1{s/.* dev \([^ ]*\).*/\1/p;}'
}

installer_global_ipv4_interface() {
  link_type=$1

  command -v ip >/dev/null 2>&1 || return 1
  ip -o -4 addr show scope global 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
    iface=$(printf '%s\n' "$line" | sed -n 's/^[0-9][0-9]*: \([^ :]*\).*/\1/p')
    [ -n "$iface" ] || continue
    installer_interface_matches_link_type "$iface" "$link_type" || continue
    printf '%s\n' "$iface"
    break
  done
}

installer_first_interface_for_link_type() {
  link_type=$1

  for sys_iface in /sys/class/net/*; do
    [ -e "$sys_iface" ] || continue
    iface=${sys_iface##*/}
    installer_interface_matches_link_type "$iface" "$link_type" || continue
    printf '%s\n' "$iface"
    return 0
  done
  return 1
}

installer_network_interface_for_handoff() {
  link_type=$1
  iface=

  iface=$(installer_default_route_interface 2>/dev/null || true)
  if [ -n "$iface" ] && installer_interface_matches_link_type "$iface" "$link_type"; then
    printf '%s\n' "$iface"
    return 0
  fi

  iface=$(network_answer_value netcfg/choose_interface choose_interface 2>/dev/null || true)
  case "$iface" in
    auto|'') ;;
    *)
      if installer_interface_matches_link_type "$iface" "$link_type"; then
        printf '%s\n' "$iface"
        return 0
      fi
      ;;
  esac

  iface=$(installer_global_ipv4_interface "$link_type" 2>/dev/null || true)
  if [ -n "$iface" ]; then
    printf '%s\n' "$iface"
    return 0
  fi

  installer_first_interface_for_link_type "$link_type"
}

installer_interface_mac_address() {
  iface=$1
  address_file="/sys/class/net/${iface}/address"

  valid_installer_network_interface_name "$iface" || return 1
  [ -r "$address_file" ] || return 1
  IFS= read -r mac <"$address_file" || return 1
  valid_installer_mac_address "$mac" || return 1
  printf '%s\n' "$mac" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

validate_network_single_line_token() {
  label=$1
  value=$2

  case "$value" in
    ''|*[![:print:]]*|*[[:space:]]*)
      installer_fatal "${label} must be a single printable token"
      ;;
  esac
}

validate_network_iface_name() {
  label=$1
  value=$2

  case "$value" in
    ''|.|..|lo)
      installer_fatal "${label} must be a non-loopback interface name"
      ;;
  esac
  case "$value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
      installer_fatal "${label} contains unsupported characters"
      ;;
  esac
  [ "${#value}" -le 15 ] || installer_fatal "${label} must be 15 characters or fewer"
}

validate_network_hostname_component() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-]*|.*|*.|*..*)
      installer_fatal "${label} must contain only hostname-safe labels"
      ;;
  esac
}

validate_network_ipv4_address() {
  label=$1
  value=$2
  old_ifs=$IFS

  case "$value" in
    ''|*[!0123456789.]*|.*|*.|*..*)
      installer_fatal "${label} must be an IPv4 dotted-quad address"
      ;;
  esac

  IFS=.
  # shellcheck disable=SC2086
  set -- $value
  IFS=$old_ifs

  [ "$#" -eq 4 ] || installer_fatal "${label} must contain four IPv4 octets"
  for octet in "$@"; do
    case "$octet" in
      ''|*[!0123456789]*|????*)
        installer_fatal "${label} contains an invalid IPv4 octet"
        ;;
    esac
    [ "$octet" -le 255 ] || installer_fatal "${label} octet is outside 0-255"
  done
}

validate_network_ipv4_address_list() {
  label=$1
  value=$2
  count=0

  case "$value" in
    *','*) installer_fatal "${label} must use spaces between IPv4 addresses, not commas" ;;
  esac

  for address in $value; do
    count=$((count + 1))
    validate_network_ipv4_address "${label} entry" "$address"
  done

  [ "$count" -ge 1 ] || installer_fatal "${label} must contain at least one IPv4 address"
  [ "$count" -le 3 ] || installer_fatal "${label} must contain no more than three IPv4 addresses"
}

validate_network_wifi_wpa() {
  label=$1
  value=$2
  length=${#value}

  validate_network_single_line_token "$label" "$value"
  if [ "$length" -ge 8 ] && [ "$length" -le 63 ]; then
    return 0
  fi
  case "$value" in
    *[!0123456789ABCDEFabcdef]*)
      installer_fatal "${label} must be 8-63 printable characters or a 64-character hexadecimal PSK"
      ;;
  esac
  [ "$length" -eq 64 ] || installer_fatal "${label} must be 8-63 printable characters or a 64-character hexadecimal PSK"
}

# shellcheck disable=SC2034
# These PRESEED_NETWORK_* values are sourced state consumed by security.sh.
target_prepare_preseed_network_handoff_state() {
  if [ "${PRESEED_NETWORK_STATE_PREPARED:-false}" = true ]; then
    return 0
  fi
  PRESEED_NETWORK_STATE_PREPARED=true
  PRESEED_NETWORK_IPV4_ENABLED=false
  PRESEED_NETWORK_IPV6_ENABLED=false
  PRESEED_NETWORK_IPV6_ADDRESS=
  PRESEED_NETWORK_IPV6_PREFIXLEN=
  PRESEED_NETWORK_IPV6_GATEWAY=
  PRESEED_NETWORK_IPV6_DNS=
  PRESEED_NETWORK_IPV6_CIDR=
  PRESEED_NETWORK_IPV6_HOST_CIDR=
  PRESEED_NETWORK_IPV6_NETWORK_CIDR=

  PRESEED_NETWORK_IPV4_HOST_CIDRS=
  PRESEED_NETWORK_IPV4_NETWORK_CIDRS=
  PRESEED_NETWORK_IPV6_HOST_CIDRS=
  PRESEED_NETWORK_IPV6_NETWORK_CIDRS=

  state_env=$(target_preseed_network_state_env)
  [ -r "$state_env" ] || return 0
  # shellcheck disable=SC1090
  . "$state_env"
  [ "${PRESEED_NETWORK_IPV4_ENABLED:-false}" = true ] ||
    [ "${PRESEED_NETWORK_IPV6_ENABLED:-false}" = true ] ||
    return 0
  PRESEED_NETWORK_IPV6_HOST_CIDR=${PRESEED_NETWORK_IPV6_HOST_CIDR:-}
  PRESEED_NETWORK_IPV6_NETWORK_CIDR=${PRESEED_NETWORK_IPV6_NETWORK_CIDR:-}
  PRESEED_NETWORK_IPV6_CIDR=${PRESEED_NETWORK_IPV6_CIDR:-}
  installer_info "loaded static network CIDRs for nftables: ipv4_hosts=${PRESEED_NETWORK_IPV4_HOST_CIDRS:-none} ipv6_hosts=${PRESEED_NETWORK_IPV6_HOST_CIDRS:-none}"
}

target_prepare_preseed_network_ipv6_handoff() {
  target_prepare_preseed_network_handoff_state
}

normalize_network_address_list() {
  printf '%s\n' "${1:-}" |
    tr ',\015\012\011' '    ' |
    sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

target_preseed_network_state_env() {
  printf '%s\n' "${TMP_ENV_DIR:-/tmp}/preseed-network-state.env"
}

target_preseed_network_generator_target_path() {
  printf '%s\n' /tmp/preseed-network-generate.pl
}

target_preseed_network_input_target_path() {
  printf '%s\n' /tmp/preseed-network-input.env
}

target_preseed_network_state_target_path() {
  printf '%s\n' /tmp/preseed-network-state.env
}

validate_network_wifi_psk_security() {
  label=$1
  value=$2

  case "$value" in
    open|wep|open/wep|wpa|sae) ;;
    *) installer_fatal "${label} must be open, wep, open/wep, wpa, or sae" ;;
  esac
}

write_target_preseed_network_input() {
  network_mode=$1
  link_types=$2
  installer_mac=
  ethernet_mac=
  wifi_mac=
  static_domain=${SYSTEM_DOMAIN:-}
  wifi_essid=
  wifi_essid_again=
  wifi_wpa=
  wifi_wep=
  ipv4_dns=
  ipv6_dns=

  [ "$network_mode" = static ] ||
    installer_fatal "preseed network generator only supports static target networking"
  [ -n "${IPV4_STATIC_RANGE:-}" ] || installer_fatal "IPV4_STATIC_RANGE is required for static target networking"
  [ -n "${IPV4_CIDR:-}" ] || installer_fatal "IPV4_CIDR is required for static target networking"
  [ -n "${IPV4_GATEWAY:-}" ] || installer_fatal "IPV4_GATEWAY is required for static target networking"
  [ -n "${IPV6_STATIC_RANGE:-}" ] || installer_fatal "IPV6_STATIC_RANGE is required for static target networking"
  [ -n "${IPV6_PREFIXLEN:-}" ] || installer_fatal "IPV6_PREFIXLEN is required for static target networking"
  [ -n "${IPV6_GATEWAY:-}" ] || installer_fatal "IPV6_GATEWAY is required for static target networking"

  validate_network_ipv4_address IPV4_GATEWAY "$IPV4_GATEWAY"
  validate_network_hostname_component SYSTEM_DOMAIN "$static_domain"
  ipv4_dns=$(normalize_network_address_list "${IPV4_DNS:-}")
  [ -n "$ipv4_dns" ] || ipv4_dns=$IPV4_GATEWAY
  validate_network_ipv4_address_list IPV4_DNS "$ipv4_dns"
  ipv6_dns=$(normalize_network_address_list "${IPV6_DNS:-}")
  [ -n "$ipv6_dns" ] || ipv6_dns=$IPV6_GATEWAY

  for handoff_link_type in $link_types; do
    installer_iface=$(installer_network_interface_for_handoff "$handoff_link_type" 2>/dev/null || true)
    installer_mac_for_type=
    if [ -n "$installer_iface" ]; then
      installer_mac_for_type=$(installer_interface_mac_address "$installer_iface" 2>/dev/null || true)
    fi
    case "$handoff_link_type" in
      ethernet) ethernet_mac=$installer_mac_for_type ;;
      wifi) wifi_mac=$installer_mac_for_type ;;
    esac
    [ -n "$installer_mac" ] || installer_mac=$installer_mac_for_type
  done

  if network_link_types_has "$link_types" wifi; then
    wifi_essid=$(network_answer_value netcfg/wireless_essid wireless_essid wifi_essid ssid 2>/dev/null || true)
    wifi_essid_again=$(network_answer_value netcfg/wireless_essid_again wireless_essid_again wifi_essid_again 2>/dev/null || true)
    wifi_wpa=$(network_answer_value netcfg/wireless_wpa wireless_wpa wifi_wpa 2>/dev/null || true)
    wifi_wep=$(network_answer_value netcfg/wireless_wep wireless_wep wifi_wep 2>/dev/null || true)
    [ -n "$wifi_essid_again" ] || wifi_essid_again=$wifi_essid
    validate_network_single_line_token PRESEED_NETWORK_WIFI_ESSID "$wifi_essid"
    validate_network_single_line_token PRESEED_NETWORK_WIFI_ESSID_AGAIN "$wifi_essid_again"
    [ "${#wifi_essid}" -le 32 ] || installer_fatal "PRESEED_NETWORK_WIFI_ESSID must be 32 characters or shorter"
    [ "$wifi_essid_again" = "$wifi_essid" ] || installer_fatal "PRESEED_NETWORK_WIFI_ESSID_AGAIN must match PRESEED_NETWORK_WIFI_ESSID"
    validate_network_wifi_psk_security WIFI_PSK_SECURITY "${WIFI_PSK_SECURITY:-wpa}"
    case "${WIFI_PSK_SECURITY:-wpa}" in
      wpa|sae) validate_network_wifi_wpa PRESEED_NETWORK_WIFI_WPA "$wifi_wpa" ;;
      wep) validate_network_single_line_token PRESEED_NETWORK_WIFI_WEP "$wifi_wep" ;;
    esac
  fi

  target_ethernet_iface=${PRESEED_NETWORK_ETHERNET_IFACE:-preeth0}
  target_wifi_iface=${PRESEED_NETWORK_WIFI_IFACE:-prewifi0}
  validate_network_iface_name PRESEED_NETWORK_ETHERNET_IFACE "$target_ethernet_iface"
  validate_network_iface_name PRESEED_NETWORK_WIFI_IFACE "$target_wifi_iface"
  [ "$target_ethernet_iface" != "$target_wifi_iface" ] ||
    installer_fatal "PRESEED_NETWORK_ETHERNET_IFACE and PRESEED_NETWORK_WIFI_IFACE must differ"

  {
    printf '# Managed by debian-preseed-di.\n'
    printf '# Temporary input for late-command static target network generation.\n'
    write_shell_config_var PRESEED_NETWORK_WAIT_SECONDS 8
    write_shell_config_var PRESEED_NETWORK_MODE "$network_mode"
    write_shell_config_var PRESEED_NETWORK_LINK_TYPES "$link_types"
    write_shell_config_var PRESEED_NETWORK_TARGET_ROOT /
    write_shell_config_var PRESEED_NETWORK_SYS_CLASS_NET /sys/class/net
    write_shell_config_var PRESEED_NETWORK_STATE_ENV "$(target_preseed_network_state_target_path)"
    write_shell_config_var PRESEED_NETWORK_HOSTNAME "${SYSTEM_HOSTNAME:-preseed-host}"
    write_shell_config_var PRESEED_NETWORK_DOMAIN "$static_domain"
    write_shell_config_var PRESEED_NETWORK_HOST_VARIANT "${PRESEED_NETWORK_HOST_VARIANT:-$(target_host_variant_class)}"
    write_shell_config_var PRESEED_NETWORK_CLASSES_RAW "${INSTALLER_CLASSES_RAW:-}"
    write_shell_config_var PRESEED_NETWORK_SELECTED_CLASS_REFS "${INSTALLER_SELECTED_CLASS_REFS:-}"
    write_shell_config_var SYSTEMD_LOG_LEVEL "${SYSTEMD_LOG_LEVEL:-error}"
    if [ -n "$installer_mac" ]; then
      write_shell_config_var PRESEED_NETWORK_INSTALLER_MAC "$installer_mac"
    fi
    if [ -n "$ethernet_mac" ]; then
      write_shell_config_var PRESEED_NETWORK_ETHERNET_MAC "$ethernet_mac"
    fi
    write_shell_config_var PRESEED_NETWORK_ETHERNET_IFACE "$target_ethernet_iface"
    if [ -n "$wifi_mac" ]; then
      write_shell_config_var PRESEED_NETWORK_WIFI_MAC "$wifi_mac"
    fi
    write_shell_config_var PRESEED_NETWORK_WIFI_IFACE "$target_wifi_iface"
    write_shell_config_var PRESEED_NETWORK_IPV4_STATIC_RANGE "$IPV4_STATIC_RANGE"
    write_shell_config_var PRESEED_NETWORK_IPV4_CIDR "$IPV4_CIDR"
    write_shell_config_var PRESEED_NETWORK_IPV4_GATEWAY "$IPV4_GATEWAY"
    write_shell_config_var PRESEED_NETWORK_IPV4_DNS "$ipv4_dns"
    write_shell_config_var PRESEED_NETWORK_IPV6_STATIC_RANGE "$IPV6_STATIC_RANGE"
    write_shell_config_var PRESEED_NETWORK_IPV6_PREFIXLEN "$IPV6_PREFIXLEN"
    write_shell_config_var PRESEED_NETWORK_IPV6_GATEWAY "$IPV6_GATEWAY"
    write_shell_config_var PRESEED_NETWORK_IPV6_DNS "$ipv6_dns"
    if network_link_types_has "$link_types" wifi; then
      write_shell_config_var PRESEED_NETWORK_WIFI_ESSID "$wifi_essid"
      write_shell_config_var PRESEED_NETWORK_WIFI_ESSID_AGAIN "$wifi_essid_again"
      write_shell_config_var PRESEED_NETWORK_WIFI_WPA "$wifi_wpa"
      write_shell_config_var PRESEED_NETWORK_WIFI_WEP "$wifi_wep"
      write_shell_config_var PRESEED_NETWORK_WIFI_PSK_SECURITY "${WIFI_PSK_SECURITY:-wpa}"
    fi
  } | write_target_file "$(target_preseed_network_input_target_path)" 0600
}

generate_target_preseed_network_config() {
  network_mode=$1
  link_types=$2
  generator_target=$(target_preseed_network_generator_target_path)
  input_target=$(target_preseed_network_input_target_path)
  state_target=$(target_preseed_network_state_target_path)
  state_env=$(target_preseed_network_state_env)

  stage_target_asset "$(installer_repo_join_var DIR_SCRIPTS_LATE preseed-network-generate.pl)" "$generator_target" 0700
  write_target_preseed_network_input "$network_mode" "$link_types"
  if ! attempt_in_target "generate static preseed target network config" \
    /usr/bin/perl "$generator_target" --input "$input_target" --state-env "$state_target"; then
    remove_target_asset "$generator_target"
    remove_target_asset "$input_target"
    remove_target_asset "$state_target"
    installer_fatal "failed to generate static preseed target network config"
  fi
  if [ ! -r "/target${state_target}" ]; then
    remove_target_asset "$generator_target"
    remove_target_asset "$input_target"
    remove_target_asset "$state_target"
    installer_fatal "preseed network generator did not produce ${state_target}"
  fi
  if ! cp "/target${state_target}" "$state_env"; then
    remove_target_asset "$generator_target"
    remove_target_asset "$input_target"
    remove_target_asset "$state_target"
    installer_fatal "failed to copy preseed network generator state"
  fi
  if ! chmod 0600 "$state_env"; then
    remove_target_asset "$generator_target"
    remove_target_asset "$input_target"
    remove_target_asset "$state_target"
    installer_fatal "failed to protect preseed network generator state"
  fi
  remove_target_asset "$generator_target"
  remove_target_asset "$input_target"
  remove_target_asset "$state_target"
  # shellcheck disable=SC1090
  . "$state_env"
}

verify_target_preseed_network_handoff() {
  network_mode=$1
  link_types=$2

  require_in_target "preseed network handoff verification"

  # shellcheck disable=SC2016
  run_in_target "verify staged preseed network handoff" /bin/sh -c '
set -eu
helper=$1
service=$2
interfaces=$3
managed_interfaces=$4
defaults=$5
networkmanager_unmanaged=$6
network_mode=$7
link_types=$8
ethernet_iface=$9
wifi_iface=${10}

command -v perl >/dev/null 2>&1
command -v ifup >/dev/null 2>&1
[ "$network_mode" = static ]
[ -x "$helper" ]
perl -c "$helper" >/dev/null
[ -r "$service" ]
grep -q "ExecStart=/usr/local/sbin/preseed-network validate" "$service"
[ -r "$defaults" ]
[ "$(stat -c %a "$defaults")" = 600 ]
[ -d /etc/network ]
[ -d /etc/network/interfaces.d ]
[ -r "$interfaces" ]
[ -r "$managed_interfaces" ]
[ -r "$networkmanager_unmanaged" ]
[ -L /etc/systemd/system/sysinit.target.wants/preseed-network.service ]
case " $link_types " in
  *" wifi "*)
    command -v wpa_supplicant >/dev/null 2>&1
    [ "$(stat -c %a "$managed_interfaces")" = 600 ]
    grep -q "interface-name:${wifi_iface}" "$networkmanager_unmanaged"
    [ -r /etc/systemd/network/11-preseed-wifi.link ]
    ;;
esac
case " $link_types " in
  *" ethernet "*)
    grep -q "interface-name:${ethernet_iface}" "$networkmanager_unmanaged"
    [ -r /etc/systemd/network/10-preseed-ethernet.link ]
    ;;
esac
' sh \
    "${FILE_PRESEED_NETWORK_HELPER}" \
    "${FILE_PRESEED_NETWORK_SERVICE}" \
    "${FILE_NETWORK_INTERFACES}" \
    "${FILE_PRESEED_NETWORK_INTERFACES}" \
    "${FILE_PRESEED_NETWORK_DEFAULT}" \
    "${FILE_NETWORKMANAGER_PRESEED_UNMANAGED_CONF}" \
    "$network_mode" \
    "$link_types" \
    "${PRESEED_NETWORK_ETHERNET_IFACE:-preeth0}" \
    "${PRESEED_NETWORK_WIFI_IFACE:-prewifi0}"
}

enable_target_networking_service_if_available() {
  if target_systemd_unit_path networking.service system >/dev/null 2>&1; then
    stage_target_systemd_unit_enabled networking.service system
  else
    installer_warn "target networking.service is unavailable; preseed network handoff is staged but ifupdown service enablement was skipped"
  fi
}

stage_target_networkmanager_dispatcher_activation_if_available() {
  if ! command -v target_systemd_unit_path >/dev/null 2>&1 ||
     ! command -v stage_target_systemd_unit_enabled >/dev/null 2>&1; then
    installer_warn "systemd staging helpers are unavailable; NetworkManager dispatcher D-Bus alias was not checked"
    return 0
  fi

  if target_systemd_unit_path NetworkManager-dispatcher.service system >/dev/null 2>&1; then
    stage_target_systemd_unit_enabled NetworkManager-dispatcher.service system
    installer_info "staged NetworkManager dispatcher D-Bus activation alias"
  fi
}

remove_target_preseed_network_handoff() {
  remove_target_asset "${FILE_PRESEED_NETWORK_INTERFACES:-/etc/network/interfaces.d/50-preseed-network}"
  remove_target_asset "${FILE_PRESEED_NETWORK_DEFAULT:-/etc/default/preseed-network}"
  remove_target_asset "${FILE_PRESEED_NETWORK_HELPER:-/usr/local/sbin/preseed-network}"
  remove_target_asset "${FILE_PRESEED_NETWORK_SERVICE:-/etc/systemd/system/preseed-network.service}"
  remove_target_asset "${FILE_NETWORKMANAGER_PRESEED_UNMANAGED_CONF:-/etc/NetworkManager/conf.d/90-preseed-network-unmanaged.conf}"
  remove_target_asset "/etc/systemd/system/sysinit.target.wants/preseed-network.service"
  remove_target_asset "/etc/systemd/network/10-preseed-ethernet.link"
  remove_target_asset "/etc/systemd/network/11-preseed-wifi.link"
}

install_target_preseed_network_handoff() {
  : "${DIR_NETWORK:?DIR_NETWORK must be set}"
  : "${DIR_NETWORK_INTERFACES_D:?DIR_NETWORK_INTERFACES_D must be set}"
  : "${FILE_NETWORK_INTERFACES:?FILE_NETWORK_INTERFACES must be set}"
  : "${FILE_PRESEED_NETWORK_INTERFACES:?FILE_PRESEED_NETWORK_INTERFACES must be set}"
  : "${FILE_PRESEED_NETWORK_DEFAULT:?FILE_PRESEED_NETWORK_DEFAULT must be set}"
  : "${FILE_PRESEED_NETWORK_HELPER:?FILE_PRESEED_NETWORK_HELPER must be set}"
  : "${FILE_PRESEED_NETWORK_SERVICE:?FILE_PRESEED_NETWORK_SERVICE must be set}"
  : "${FILE_NETWORKMANAGER_PRESEED_UNMANAGED_CONF:?FILE_NETWORKMANAGER_PRESEED_UNMANAGED_CONF must be set}"

  stage_target_networkmanager_dispatcher_activation_if_available

  if ! target_preseed_network_handoff_requested; then
    installer_info "skipping target preseed network handoff; selected networking is not managed by this helper"
    remove_target_preseed_network_handoff
    return 0
  fi

  network_mode=$(target_preseed_network_mode)
  link_types=$(target_preseed_network_link_types)

  require_in_target "preseed network handoff prerequisite verification"
  if ! test_in_target /bin/sh -c 'command -v ifup >/dev/null 2>&1'; then
    installer_fatal "ifupdown is required for target networking handoff, but ifup is missing in /target"
  fi
  if network_link_types_has "$link_types" wifi && ! test_in_target /bin/sh -c 'command -v wpa_supplicant >/dev/null 2>&1'; then
    installer_fatal "wpasupplicant is required for Wi-Fi target networking, but wpa_supplicant is missing in /target"
  fi

  install -d -m 0755 "/target${DIR_NETWORK}" "/target${DIR_NETWORK_INTERFACES_D}"
  remove_target_preseed_network_handoff
  install -d -m 0755 "/target${DIR_NETWORK}" "/target${DIR_NETWORK_INTERFACES_D}"
  generate_target_preseed_network_config "$network_mode" "$link_types"
  stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/preseed-network)" \
    "${FILE_PRESEED_NETWORK_HELPER}" \
    0755
  stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/preseed-network.service)" \
    "${FILE_PRESEED_NETWORK_SERVICE}" \
    0644
  stage_target_systemd_unit_enabled preseed-network.service system
  enable_target_networking_service_if_available
  verify_target_preseed_network_handoff "$network_mode" "$link_types"
  installer_append_log_category late target_customization info network \
    "staged preseed network handoff mode=${network_mode} link_types=${link_types} ipv6=${PRESEED_NETWORK_IPV6_CIDR:-none} helper=${FILE_PRESEED_NETWORK_HELPER} service=${FILE_PRESEED_NETWORK_SERVICE}" || true
}
