#!/bin/sh
# Shared late_command security helpers. This file is sourced, not executed.

late_command_security_class() {
  installer_selected_class_for_purpose security 2>/dev/null || printf '%s\n' "${INSTALLER_SECURITY_CLASS:-standard}"
}

nftables_normalize_env_token() {
  nftables_ws=$(printf ' \011\015\012_')
  nftables_ws=${nftables_ws%_}

  # d-i tr implementations may treat [:upper:] and [:space:] as literal sets,
  # which corrupts "default" into "dfllt". Use explicit ASCII sets here.
  printf '%s' "$1" |
    tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' |
    tr -d "$nftables_ws"
}

late_command_nftables_requested_profile() {
  nft_profile=$(nftables_normalize_env_token "${NFT_PROFILE:-default}")
  [ -n "$nft_profile" ] || installer_fatal "NFT_PROFILE must not be empty"

  case "$nft_profile" in
    none|default|baseline|desktop|server)
      printf '%s\n' "$nft_profile"
      ;;
    *)
      installer_fatal "unsupported NFT_PROFILE: ${nft_profile}; expected none, default, baseline, server, or desktop"
      ;;
  esac
}

late_command_nftables_host_variant() {
  host_variant=${INSTALLER_HOST_VARIANT:-}
  if [ -z "$host_variant" ]; then
    host_variant=$(installer_selected_class_for_purpose host-variant 2>/dev/null || true)
  fi

  case "$host_variant" in
    desktop|server)
      printf '%s\n' "$host_variant"
      ;;
    '')
      installer_fatal "NFT_PROFILE=default requires a selected role class (desktop or server)"
      ;;
    *)
      installer_fatal "NFT_PROFILE=default cannot resolve unsupported host variant: ${host_variant}"
      ;;
  esac
}

late_command_nftables_profile() {
  nft_profile=${1:-$(late_command_nftables_requested_profile)}

  case "$nft_profile" in
    none|baseline|desktop|server)
      printf '%s\n' "$nft_profile"
      ;;
    default)
      late_command_nftables_host_variant
      ;;
    *)
      installer_fatal "unsupported normalized NFT_PROFILE: ${nft_profile}; expected none, default, baseline, server, or desktop"
      ;;
  esac
}

nftables_service_assets() {
  cat <<'EOF'
backup-restic
crowdsec
cups
dhcp-client
dhcp-server
dns-client
dns-server
docker
egress
git-server
gitlab-runner
grafana
imap-server
kdeconnect
loki
matrix-synapse
mdns
mosquitto
mysql
nfs
node-exporter
ntp-client
ntp-server
ollama
openvpn
pihole
podman
postgresql
prometheus
qbittorrent
redis
rsync
samba
smtp-client
smtp-server
ssdp
ssh-client
ssh-server
syncthing
tailscale
wazuh-agent
wazuh-server
web
wireguard
zerotier
EOF
}

nftables_service_asset_supported() {
  candidate=$1

  case "$candidate" in
    backup-restic|crowdsec|cups|dhcp-client|dhcp-server|dns-client|dns-server|docker|egress|git-server|gitlab-runner|grafana|imap-server|kdeconnect|loki|matrix-synapse|mdns|mosquitto|mysql|nfs|node-exporter|ntp-client|ntp-server|ollama|openvpn|pihole|podman|postgresql|prometheus|qbittorrent|redis|rsync|samba|smtp-client|smtp-server|ssdp|ssh-client|ssh-server|syncthing|tailscale|wazuh-agent|wazuh-server|web|wireguard|zerotier)
      return 0
      ;;
  esac

  return 1
}

late_command_nftables_services() {
  nft_services=$(nftables_normalize_env_token "${NFT_SERVICES:-none}")
  [ -n "$nft_services" ] || installer_fatal "NFT_SERVICES must not be empty when NFT_PROFILE is not none"

  case "$nft_services" in
    none)
      return 0
      ;;
    *[!abcdefghijklmnopqrstuvwxyz0123456789,-]*)
      installer_fatal "NFT_SERVICES contains unsupported characters: ${nft_services}"
      ;;
    ,*|*,|*,,*)
      installer_fatal "NFT_SERVICES must be a comma-separated list without empty entries: ${nft_services}"
      ;;
  esac

  old_ifs=$IFS
  IFS=,
  # shellcheck disable=SC2086
  set -- $nft_services
  IFS=$old_ifs

  selected_services=
  for service_asset in "$@"; do
    [ "$service_asset" != none ] || installer_fatal "NFT_SERVICES=none cannot be combined with service names"
    nftables_service_asset_supported "$service_asset" ||
      installer_fatal "unsupported NFT_SERVICES entry: ${service_asset}"
    case " $selected_services " in
      *" $service_asset "*) ;;
      *) selected_services="${selected_services:+$selected_services }$service_asset" ;;
    esac
  done

  printf '%s\n' "$selected_services"
}

nftables_merge_selected_services() {
  selected_services=$1
  shift

  merged_services=$selected_services
  for service_asset in "$@"; do
    [ -n "$service_asset" ] || continue
    case " $merged_services " in
      *" $service_asset "*) ;;
      *) merged_services="${merged_services:+$merged_services }$service_asset" ;;
    esac
  done

  printf '%s\n' "$merged_services"
}

late_command_nftables_effective_services() {
  selected_services=$(late_command_nftables_services)
  effective_services=$selected_services

  if [ "${SSH_SERVER_ENABLED:-false}" = true ]; then
    effective_services=$(nftables_merge_selected_services "$effective_services" ssh-server)
  fi

  if command -v gitlab_runner_service_is_selected >/dev/null 2>&1 &&
     gitlab_runner_service_is_selected; then
    effective_services=$(nftables_merge_selected_services "$effective_services" gitlab-runner)
  fi

  if [ "$effective_services" != "$selected_services" ]; then
    installer_info "nftables service overlays adjusted from ${selected_services:-none} to $(printf '%s' "$effective_services" | tr ' ' ',')"
  fi

  printf '%s\n' "$effective_services"
}

stage_target_nftables_service_assets() {
  for service_asset in "$@"; do
    if [ "$service_asset" = ssh-server ] && [ "${SSH_SERVER_ENABLED:-false}" = true ]; then
      render_target_asset_with_placeholder_map \
        "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/nftables/services/${service_asset}.yml")" \
        "/etc/nftables/services/${service_asset}.yml" \
        0644 \
        nftables_ssh_service_placeholder_map
      continue
    fi
    stage_target_asset \
      "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/nftables/services/${service_asset}.yml")" \
      "/etc/nftables/services/${service_asset}.yml" \
      0644
  done
}

stage_target_nftables_profile_assets() {
  for profile_asset in baseline desktop server; do
    render_target_asset_with_placeholder_map \
      "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/nftables/profiles/${profile_asset}.yml")" \
      "/etc/nftables/profiles/${profile_asset}.yml" \
      0644 \
      nftables_interface_placeholder_map
  done
}

stage_target_nftables_all_service_assets() {
  for service_asset in $(nftables_service_assets); do
    stage_target_nftables_service_assets "$service_asset"
  done
}

nftables_service_overlay_paths() {
  selected_paths=

  for service_asset in "$@"; do
    selected_paths="${selected_paths:+$selected_paths }/etc/nftables/services/${service_asset}.yml"
  done

  printf '%s\n' "$selected_paths"
}

nftables_runtime_cidr_pairs() {
  if [ "${PRESEED_NETWORK_IPV6_ENABLED:-false}" = true ]; then
    for cidr in ${PRESEED_NETWORK_IPV6_HOST_CIDRS:-${PRESEED_NETWORK_IPV6_HOST_CIDR:-}}; do
      printf '%s\n' "desktop_static_ipv6_host=${cidr}"
    done
    for cidr in ${PRESEED_NETWORK_IPV6_NETWORK_CIDRS:-${PRESEED_NETWORK_IPV6_NETWORK_CIDR:-}}; do
      printf '%s\n' "desktop_static_ipv6_network=${cidr}"
      printf '%s\n' "lan_ipv6=${cidr}"
    done
  fi
  if [ "${PRESEED_NETWORK_IPV4_ENABLED:-false}" = true ]; then
    for cidr in ${PRESEED_NETWORK_IPV4_NETWORK_CIDRS:-}; do
      printf '%s\n' "lan_ipv4=${cidr}"
    done
  fi
}

nftables_runtime_cidrs_env_value() {
  runtime_cidrs=
  while IFS= read -r cidr_pair || [ -n "$cidr_pair" ]; do
    [ -n "$cidr_pair" ] || continue
    runtime_cidrs="${runtime_cidrs:+$runtime_cidrs }${cidr_pair}"
  done <<EOF
$(nftables_runtime_cidr_pairs)
EOF
  printf '%s\n' "$runtime_cidrs"
}

nftables_managed_iface_value() {
  label=$1
  value=$2
  fallback=$3
  iface=${value:-$fallback}

  case "$iface" in
    ''|.|..|lo)
      installer_fatal "${label} must be a non-loopback interface name"
      ;;
  esac
  case "$iface" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
      installer_fatal "${label} contains unsupported characters: ${iface}"
      ;;
  esac
  [ "${#iface}" -le 15 ] || installer_fatal "${label} must be 15 characters or fewer: ${iface}"
  printf '%s\n' "$iface"
}

nftables_interface_placeholder_map() {
  ethernet_iface=$(nftables_managed_iface_value PRESEED_NETWORK_ETHERNET_IFACE "${PRESEED_NETWORK_ETHERNET_IFACE:-}" preeth0)
  wifi_iface=$(nftables_managed_iface_value PRESEED_NETWORK_WIFI_IFACE "${PRESEED_NETWORK_WIFI_IFACE:-}" prewifi0)

  [ "$ethernet_iface" != "$wifi_iface" ] ||
    installer_fatal "PRESEED_NETWORK_ETHERNET_IFACE and PRESEED_NETWORK_WIFI_IFACE must differ"

  printf 'PRESEED_NETWORK_ETHERNET_IFACE=%s\n' "$ethernet_iface"
  printf 'PRESEED_NETWORK_WIFI_IFACE=%s\n' "$wifi_iface"
}

nftables_validate_port_value() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0-9]*)
      installer_fatal "${label} must be a numeric TCP/UDP port"
      ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
    installer_fatal "${label} must be in range 1..65535"
}

nftables_validate_cidr_token() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0123456789abcdefABCDEF:./]*)
      installer_fatal "${label} contains unsupported CIDR characters: ${value:-unset}"
      ;;
  esac
  case "$value" in
    */*)
      ;;
    *)
      installer_fatal "${label} must be CIDR-formatted"
      ;;
  esac
}

nftables_yaml_inline_list() {
  if [ "$#" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  first=true
  printf '['
  for item in "$@"; do
    [ -n "$item" ] || continue
    if [ "$first" = true ]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$item"
  done
  if [ "$first" = true ]; then
    printf '[]\n'
    return 0
  fi
  printf ']\n'
}

nftables_merge_unique_tokens() {
  merged=
  for token in "$@"; do
    [ -n "$token" ] || continue
    case " $merged " in
      *" $token "*) ;;
      *) merged="${merged:+$merged }$token" ;;
    esac
  done
  printf '%s\n' "$merged"
}

nftables_ipv4_to_int() {
  addr=$1
  old_ifs=${IFS}
  IFS=.
  set -- $addr
  IFS=${old_ifs}
  [ "$#" -eq 4 ] || installer_fatal "invalid IPv4 address: ${addr}"
  for octet in "$@"; do
    case "$octet" in
      ''|*[!0-9]*)
        installer_fatal "invalid IPv4 address: ${addr}"
        ;;
    esac
    [ "$octet" -ge 0 ] && [ "$octet" -le 255 ] ||
      installer_fatal "invalid IPv4 address: ${addr}"
  done
  printf '%s\n' "$((($1 << 24) + ($2 << 16) + ($3 << 8) + $4))"
}

nftables_ipv4_from_int() {
  value=$1
  printf '%s.%s.%s.%s\n' \
    "$(((value >> 24) & 255))" \
    "$(((value >> 16) & 255))" \
    "$(((value >> 8) & 255))" \
    "$((value & 255))"
}

nftables_ipv4_network_cidr() {
  addr=$1
  prefix=$2

  nftables_validate_port_value IPv4_prefix_length "$prefix"
  [ "$prefix" -le 32 ] || installer_fatal "IPv4 prefix length must be 32 or lower"
  addr_int=$(nftables_ipv4_to_int "$addr")
  if [ "$prefix" -eq 0 ]; then
    mask=0
  else
    mask=$(((0xffffffff << (32 - prefix)) & 0xffffffff))
  fi
  network_int=$((addr_int & mask))
  printf '%s/%s\n' "$(nftables_ipv4_from_int "$network_int")" "$prefix"
}

nftables_ipv6_expand() {
  addr=$1
  has_double_colon=false
  head=${addr}
  tail=

  case "$addr" in
    *::*)
      has_double_colon=true
      head=${addr%%::*}
      tail=${addr#*::}
      ;;
  esac

  head_count=0
  tail_count=0
  head_words=
  tail_words=

  if [ -n "$head" ]; then
    head_words=$(printf '%s\n' "$head" | tr ':' ' ')
    set -- $head_words
    head_count=$#
  fi
  if [ -n "$tail" ]; then
    tail_words=$(printf '%s\n' "$tail" | tr ':' ' ')
    set -- $tail_words
    tail_count=$#
  fi

  if [ "$has_double_colon" = true ]; then
    missing=$((8 - head_count - tail_count))
    [ "$missing" -ge 0 ] || installer_fatal "invalid IPv6 address: ${addr}"
  else
    missing=0
    [ $((head_count + tail_count)) -eq 8 ] || installer_fatal "invalid IPv6 address: ${addr}"
  fi

  expanded=
  for field in $head_words; do
    [ -n "$field" ] || continue
    expanded="${expanded:+$expanded }$field"
  done
  while [ "$missing" -gt 0 ]; do
    expanded="${expanded:+$expanded }0"
    missing=$((missing - 1))
  done
  for field in $tail_words; do
    [ -n "$field" ] || continue
    expanded="${expanded:+$expanded }$field"
  done

  set -- $expanded
  [ "$#" -eq 8 ] || installer_fatal "invalid IPv6 address: ${addr}"
  for field in "$@"; do
    case "$field" in
      ''|*[!0123456789abcdefABCDEF]*)
        installer_fatal "invalid IPv6 address: ${addr}"
        ;;
    esac
    [ "${#field}" -le 4 ] || installer_fatal "invalid IPv6 address: ${addr}"
  done
  printf '%s\n' "$expanded"
}

nftables_ipv6_network_cidr() {
  addr=$1
  prefix=$2

  nftables_validate_port_value IPv6_prefix_length "$prefix"
  [ "$prefix" -le 128 ] || installer_fatal "IPv6 prefix length must be 128 or lower"
  [ $((prefix % 16)) -eq 0 ] ||
    installer_fatal "IPv6 prefix length must align to 16-bit boundaries for SSH nftables rendering"
  keep_hextets=$((prefix / 16))
  expanded=$(nftables_ipv6_expand "$addr")
  index=0
  network=
  for field in $expanded; do
    if [ "$index" -lt "$keep_hextets" ]; then
      network="${network:+$network:}$field"
    else
      network="${network:+$network:}0"
    fi
    index=$((index + 1))
  done
  printf '%s/%s\n' "$network" "$prefix"
}

nftables_ssh_allow_ipv4_cidrs() {
  if [ -n "${PRESEED_NETWORK_IPV4_NETWORK_CIDRS:-}" ]; then
    printf '%s\n' "$(nftables_merge_unique_tokens ${PRESEED_NETWORK_IPV4_NETWORK_CIDRS})"
    return 0
  fi
  if [ -n "${IPV4_STATIC_RANGE:-}" ] && [ -n "${IPV4_CIDR:-}" ]; then
    ipv4_seed=${IPV4_STATIC_RANGE%%/*}
    printf '%s\n' "$(nftables_ipv4_network_cidr "$ipv4_seed" "$IPV4_CIDR")"
    return 0
  fi
  printf '\n'
}

nftables_ssh_allow_ipv6_cidrs() {
  if [ -n "${PRESEED_NETWORK_IPV6_NETWORK_CIDRS:-}" ]; then
    printf '%s\n' "$(nftables_merge_unique_tokens ${PRESEED_NETWORK_IPV6_NETWORK_CIDRS})"
    return 0
  fi
  if [ -n "${IPV6_STATIC_RANGE:-}" ] && [ -n "${IPV6_PREFIXLEN:-}" ]; then
    ipv6_seed=${IPV6_STATIC_RANGE%%/*}
    printf '%s\n' "$(nftables_ipv6_network_cidr "$ipv6_seed" "$IPV6_PREFIXLEN")"
    return 0
  fi
  printf '\n'
}

nftables_ssh_service_placeholder_map() {
  ssh_allow_ipv4=$(nftables_ssh_allow_ipv4_cidrs)
  ssh_allow_ipv6=$(nftables_ssh_allow_ipv6_cidrs)

  runtime_apply_ssh_from_cmdline
  nftables_validate_port_value SSH_PORT "$SSH_PORT"
  while IFS= read -r cidr || [ -n "$cidr" ]; do
    [ -n "$cidr" ] || continue
    nftables_validate_cidr_token SSH_allow_ipv4 "$cidr"
  done <<EOF
$ssh_allow_ipv4
EOF
  while IFS= read -r cidr || [ -n "$cidr" ]; do
    [ -n "$cidr" ] || continue
    nftables_validate_cidr_token SSH_allow_ipv6 "$cidr"
  done <<EOF
$ssh_allow_ipv6
EOF

  nftables_interface_placeholder_map
  printf 'SSH_PORT=%s\n' "$SSH_PORT"
  printf 'NFTABLES_SSH_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $ssh_allow_ipv4)"
  printf 'NFTABLES_SSH_ALLOW_IPV6=%s\n' "$(nftables_yaml_inline_list $ssh_allow_ipv6)"
}

apparmor_managed_profile_files() {
  cat <<'EOF'
usr.bin.totem
usr.sbin.apt-cacher-ng
usr.sbin.avahi-daemon
EOF
}

stage_target_apparmor_profiles() {
  for apparmor_profile in $(apparmor_managed_profile_files); do
    stage_target_asset \
      "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/apparmor.d/${apparmor_profile}")" \
      "/etc/apparmor.d/${apparmor_profile}" \
      0644
  done
}

nftables_default_placeholder_map() {
  write_shell_config_var NFTABLES_LOG_LEVEL "${NFTABLES_LOG_LEVEL:-none}"
  write_shell_config_var NFT_PROFILE "${NFTABLES_DEFAULT_REQUESTED_PROFILE:-default}"
  write_shell_config_var NFT_SERVICES "${NFTABLES_DEFAULT_SELECTED_SERVICES_CSV:-none}"
  write_shell_config_var NFT_POLICY_PROFILE "/etc/nftables/profiles/${NFTABLES_DEFAULT_SELECTED_PROFILE:-default}.yml"
  write_shell_config_var NFT_POLICY_RESOLVED_PROFILE "${NFTABLES_DEFAULT_SELECTED_PROFILE:-default}"
  write_shell_config_var NFT_POLICY_DEFAULT_PROFILE /etc/nftables/profiles/default.yml
  write_shell_config_var NFT_POLICY_SERVICE_OVERLAYS "${NFTABLES_DEFAULT_SERVICE_OVERLAYS:-}"
  write_shell_config_var NFT_POLICY_RUNTIME_CIDRS "${NFTABLES_DEFAULT_RUNTIME_CIDRS:-}"
  write_shell_config_var NFT_POLICY_GENERATOR /usr/local/sbin/nft-policy-generate
}

clear_target_nftables_assets() {
  if [ -r /target/etc/nftables.conf ] &&
     grep -E -q 'Managed by (debian-preseed-di|nft-policy-generate[.]py)' /target/etc/nftables.conf; then
    rm -f /target/etc/nftables.conf
  fi

  rm -f \
    /target/etc/default/nft-policy-generate \
    /target/usr/local/sbin/nft-policy-generate \
    /target/etc/systemd/system/nftables.service.d/override.conf \
    /target/etc/nftables/README.md \
    /target/etc/nftables/profiles/baseline.yml \
    /target/etc/nftables/profiles/default.yml \
    /target/etc/nftables/profiles/desktop.yml \
    /target/etc/nftables/profiles/server.yml \
    /target/etc/nftables.d/00-defines.nft \
    /target/etc/nftables.d/10-base.nft \
    /target/etc/nftables.d/20-filter.nft \
    /target/etc/nftables.d/30-nat.nft \
    /target/etc/nftables.d/90-local.nft

  for service_asset in $(nftables_service_assets); do
    rm -f "/target/etc/nftables/services/${service_asset}.yml"
  done

  if command -v unstage_target_systemd_unit_enabled >/dev/null 2>&1; then
    unstage_target_systemd_unit_enabled nftables.service system
  fi
  rmdir /target/etc/systemd/system/nftables.service.d 2>/dev/null || true
  rmdir /target/etc/nftables/services /target/etc/nftables/profiles /target/etc/nftables /target/etc/nftables.d 2>/dev/null || true
}

write_target_nftables_default_config() {
  selected_profile=$1
  requested_profile=$2
  selected_services=$3
  runtime_cidrs=${4:-}

  old_ifs=$IFS
  IFS=' '
  # shellcheck disable=SC2086
  set -- $selected_services
  IFS=$old_ifs
  NFTABLES_DEFAULT_SELECTED_PROFILE=$selected_profile
  NFTABLES_DEFAULT_REQUESTED_PROFILE=$requested_profile
  NFTABLES_DEFAULT_SELECTED_SERVICES_CSV=$(printf '%s' "$selected_services" | tr ' ' ',')
  NFTABLES_DEFAULT_SERVICE_OVERLAYS=$(nftables_service_overlay_paths "$@")
  NFTABLES_DEFAULT_RUNTIME_CIDRS=$runtime_cidrs

  render_target_asset_with_placeholder_map \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/default/nft-policy-generate.tmpl)" \
    /etc/default/nft-policy-generate \
    0644 \
    nftables_default_placeholder_map

  unset \
    NFTABLES_DEFAULT_SELECTED_PROFILE \
    NFTABLES_DEFAULT_REQUESTED_PROFILE \
    NFTABLES_DEFAULT_SELECTED_SERVICES_CSV \
    NFTABLES_DEFAULT_SERVICE_OVERLAYS \
    NFTABLES_DEFAULT_RUNTIME_CIDRS
}

configure_target_nftables() {
  requested_profile=$(late_command_nftables_requested_profile)
  selected_profile=$(late_command_nftables_profile "$requested_profile")
  installer_info "nftables profile selection: raw=${NFT_PROFILE:-default} normalized=${requested_profile} selected=${selected_profile}"

  if [ "$selected_profile" = none ]; then
    installer_info "NFT_PROFILE=none; skipping nftables profile, service overlay, and unit staging"
    clear_target_nftables_assets
    return 0
  fi

  if command -v target_prepare_preseed_network_handoff_state >/dev/null 2>&1; then
    target_prepare_preseed_network_handoff_state
  elif command -v target_prepare_preseed_network_ipv6_handoff >/dev/null 2>&1; then
    target_prepare_preseed_network_ipv6_handoff
  fi

  selected_services=$(late_command_nftables_effective_services)
  runtime_cidrs=$(nftables_runtime_cidrs_env_value)

  install -d -m 0755 \
    /target/etc/default \
    /target/etc/nftables \
    /target/etc/nftables/profiles \
    /target/etc/nftables/services \
    /target/etc/nftables.d \
    /target/etc/systemd/system/nftables.service.d \
    /target/usr/local/sbin

  rm -f \
    /target/etc/nftables/profiles/baseline.yml \
    /target/etc/nftables/profiles/default.yml \
    /target/etc/nftables/profiles/desktop.yml \
    /target/etc/nftables/profiles/server.yml \
    /target/etc/nftables.d/00-defines.nft \
    /target/etc/nftables.d/10-base.nft \
    /target/etc/nftables.d/20-filter.nft \
    /target/etc/nftables.d/30-nat.nft \
    /target/etc/nftables.d/90-local.nft
  for service_asset in $(nftables_service_assets); do
    rm -f "/target/etc/nftables/services/${service_asset}.yml"
  done

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/nft-policy-generate.py)" "/usr/local/sbin/nft-policy-generate" 0755
  render_target_asset_with_placeholder_map "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/nftables/README.md)" "/etc/nftables/README.md" 0644 nftables_interface_placeholder_map
  stage_target_helper_doc nft-policy-generate.md nft-policy-generate.md
  stage_target_nftables_profile_assets
  render_target_asset_with_placeholder_map \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/nftables/profiles/${selected_profile}.yml")" \
    "/etc/nftables/profiles/default.yml" \
    0644 \
    nftables_interface_placeholder_map
  stage_target_nftables_all_service_assets
  write_target_nftables_default_config "$selected_profile" "${requested_profile:-default}" "$selected_services" "$runtime_cidrs"

  stage_target_asset \
    "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/nftables.service.d/override.conf)" \
    "/etc/systemd/system/nftables.service.d/override.conf" \
    0644

  require_in_target "nftables policy generation"
  set -- env "NFTABLES_LOG_LEVEL=${NFTABLES_LOG_LEVEL:-none}" /usr/local/sbin/nft-policy-generate \
    --profile "/etc/nftables/profiles/${selected_profile}.yml"
  for service_asset in $selected_services; do
    set -- "$@" --overlay "/etc/nftables/services/${service_asset}.yml"
  done
  for runtime_pair in $runtime_cidrs; do
    set -- "$@" --add-cidr "$runtime_pair"
  done
  set -- "$@" --write --summary
  run_in_target "generate ${requested_profile} nftables policy (${selected_profile} profile)" "$@"

  stage_target_systemd_unit_enabled nftables.service system

  [ -x /target/usr/local/sbin/nft-policy-generate ] || installer_fatal "staged nftables generator is missing"
  [ -r /target/etc/nftables.conf ] || installer_fatal "staged nftables entrypoint is missing"
  for fragment in 00-defines.nft 10-base.nft 20-filter.nft 30-nat.nft 90-local.nft; do
    [ -r "/target/etc/nftables.d/${fragment}" ] ||
      installer_fatal "staged nftables fragment is missing: ${fragment}"
  done
  [ -r "/target/etc/systemd/system/nftables.service.d/override.conf" ] ||
    installer_fatal "staged nftables systemd override is missing"
  [ -r "/target/etc/nftables/profiles/${selected_profile}.yml" ] ||
    installer_fatal "staged nftables default profile is missing"
  for profile_asset in baseline desktop server; do
    [ -r "/target/etc/nftables/profiles/${profile_asset}.yml" ] ||
      installer_fatal "staged nftables profile is missing: ${profile_asset}"
  done
  for service_asset in $(nftables_service_assets); do
    [ -r "/target/etc/nftables/services/${service_asset}.yml" ] ||
      installer_fatal "staged nftables service overlay is missing: ${service_asset}"
  done
  for service_asset in $selected_services; do
    [ -r "/target/etc/nftables/services/${service_asset}.yml" ] ||
      installer_fatal "selected nftables service overlay is missing: ${service_asset}"
  done
}

configure_target_apparmor_auditd() {
  security_class=$(late_command_security_class)

  case "$security_class" in
    standard|enhanced) ;;
    *) installer_fatal "unsupported security class for AppArmor/auditd configuration: ${security_class:-unset}" ;;
  esac

  install -d -m 0755 \
    /target/etc/apparmor.d \
    /target/etc/audit \
    /target/etc/audit/rules.d \
    /target/etc/audit/plugins.d \
    /target/etc/systemd/system/auditd.service.d \
    /target/etc/ssh \
    /target/usr/local/bin \
    /target/usr/local/sbin
  install -d -m 0700 /target/etc/security
  [ -e /target/etc/security/opasswd ] || : > /target/etc/security/opasswd
  chmod 0600 /target/etc/security/opasswd
  rm -f \
    /target/etc/audit/rules.d/10-security-standard.rules \
    /target/etc/audit/rules.d/10-security-enhanced.rules \
    /target/etc/audit/rules.d/zz-security-standard.rules \
    /target/etc/audit/rules.d/zz-security-enhanced.rules

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/75-auditd-storage.conf)" "/etc/tmpfiles.d/75-auditd-storage.conf" 0644
  normalize_target_tmpfiles_directory_policy "/etc/tmpfiles.d/75-auditd-storage.conf" "auditd storage"
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/default/apparmor)" "/etc/default/apparmor" 0644
  stage_target_apparmor_profiles
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/audit/${security_class}/auditd.conf")" "/etc/audit/auditd.conf" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/audit/${security_class}/rules.d/10-security-${security_class}.rules")" "/etc/audit/rules.d/zz-security-${security_class}.rules" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/audit/plugins.d/af_unix.conf)" "/etc/audit/plugins.d/af_unix.conf" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/audit/plugins.d/syslog.conf)" "/etc/audit/plugins.d/syslog.conf" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/augenrules-quiet)" "/usr/local/sbin/augenrules-quiet" 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/auditd.service.d/override.conf)" "/etc/systemd/system/auditd.service.d/override.conf" 0644

  [ -r /target/etc/default/apparmor ] || installer_fatal "staged AppArmor default file is missing"
  apparmor_profile_files=$(apparmor_managed_profile_files)
  for apparmor_profile in $apparmor_profile_files; do
    [ -r "/target/etc/apparmor.d/${apparmor_profile}" ] ||
      installer_fatal "staged AppArmor profile is missing: ${apparmor_profile}"
    if grep -Eq 'flags=.*(unconfined|default_allow)' "/target/etc/apparmor.d/${apparmor_profile}"; then
      installer_fatal "managed AppArmor profile must not use unconfined/default_allow mode: ${apparmor_profile}"
    fi
  done
  unset apparmor_profile
  [ -r /target/etc/audit/auditd.conf ] || installer_fatal "staged auditd.conf is missing"
  [ -r "/target/etc/audit/rules.d/zz-security-${security_class}.rules" ] || installer_fatal "staged audit rules are missing"
  [ -r /target/etc/audit/plugins.d/af_unix.conf ] || installer_fatal "staged audit af_unix plugin config is missing"
  [ -r /target/etc/audit/plugins.d/syslog.conf ] || installer_fatal "staged audit syslog plugin config is missing"
  [ -x /target/usr/local/sbin/augenrules-quiet ] || installer_fatal "staged augenrules wrapper is missing"
  [ -r /target/etc/systemd/system/auditd.service.d/override.conf ] || installer_fatal "staged auditd override is missing"
  invalid_audit_dir_filter=$(grep -n -m 1 -E '(^|[[:space:]])-F[[:space:]]+dir=/[^[:space:]]+/([[:space:]]|$)' \
    "/target/etc/audit/rules.d/zz-security-${security_class}.rules" || true)
  [ -z "$invalid_audit_dir_filter" ] || installer_fatal "audit rules must not use trailing slashes in dir= filters: ${invalid_audit_dir_filter}"
  invalid_audit_arch_filter=$(awk '
    /^[[:space:]]*-/ && /(^|[[:space:]])-F[[:space:]]+arch=/ && !/(^|[[:space:]])-S[[:space:]]+/ {
      print FNR ":" $0
      exit
    }
  ' "/target/etc/audit/rules.d/zz-security-${security_class}.rules" || true)
  [ -z "$invalid_audit_arch_filter" ] || installer_fatal "audit rules with arch= must include explicit syscall selectors: ${invalid_audit_arch_filter}"

  if test_in_target test -x /usr/sbin/apparmor_parser; then
    # shellcheck disable=SC2016
    run_in_target "validate managed AppArmor profile syntax" /bin/sh -c '
set -eu
for profile_name in "$@"; do
  apparmor_parser -q -Q -K -T "/etc/apparmor.d/${profile_name}"
done
' sh $apparmor_profile_files
  fi

  stage_target_systemd_unit_enabled apparmor.service system
  stage_target_systemd_unit_enabled auditd.service system
  configure_target_nftables
}
