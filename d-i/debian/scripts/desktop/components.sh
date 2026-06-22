#!/bin/sh
# Labwc target asset staging and service enablement helpers.

desktop_stage_role_asset() {
  role_relpath=$1
  target_path=$2
  mode=$3
  source_path=$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP "target/$role_relpath")

  stage_target_asset "$source_path" "$target_path" "$mode"
  desktop_log "staged_asset source=${source_path} target=${target_path} mode=${mode}"
}

desktop_double_quote_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

desktop_toml_escape() {
  desktop_double_quote_escape "$1"
}

desktop_xml_attribute_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

desktop_render_target_template() {
  source_path=$1
  target_path=$2
  mode=$3
  shift 3
  tmp_source="${TMP_ENV_DIR}/desktop-template.$$.src"
  tmp_rendered="${TMP_ENV_DIR}/desktop-template.$$.dst"

  [ $(( $# % 2 )) -eq 0 ] || installer_fatal "desktop template placeholders must be name/value pairs: ${source_path}"
  fetch_hook "$source_path" "$tmp_source"
  if ! installer_apply_scalar_placeholders "$tmp_source" "$tmp_rendered" "$@"; then
    rm -f "$tmp_source" "$tmp_rendered"
    installer_fatal "failed to render desktop template ${source_path}"
  fi
  ensure_target_asset_parent "$target_path"
  install -m "$mode" "$tmp_rendered" "/target${target_path}"
  rm -f "$tmp_source" "$tmp_rendered"
  desktop_log "rendered_template source=${source_path} target=${target_path} mode=${mode}"
}

desktop_render_role_target_template() {
  role_relpath=$1
  target_path=$2
  mode=$3
  shift 3
  source_path=$(installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP "target/$role_relpath")

  desktop_render_target_template "$source_path" "$target_path" "$mode" "$@"
}

desktop_render_shared_target_template() {
  shared_relpath=$1
  target_path=$2
  mode=$3
  shift 3
  source_path=$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "$shared_relpath")

  desktop_render_target_template "$source_path" "$target_path" "$mode" "$@"
}

desktop_write_target_file() {
  target_path=$1
  mode=$2
  content=$3
  tmp_path="/target${target_path}.tmp.$$"

  ensure_target_asset_parent "$target_path"
  printf '%s\n' "$content" >"$tmp_path"
  install -m "$mode" "$tmp_path" "/target${target_path}"
  rm -f "$tmp_path"
}

desktop_replace_block_placeholder_in_target() {
  target_path=$1
  placeholder=$2
  replacement=$3

  replace_placeholder_line_block "/target${target_path}" "$placeholder" "$replacement"
}

desktop_labwc_workspace_name_lines() {
  workspace_count=${LABWC_WORKSPACE_COUNT:-4}
  workspace_index=1

  while [ "$workspace_index" -le "$workspace_count" ]; do
    printf '      <name>%s</name>\n' "$workspace_index"
    workspace_index=$((workspace_index + 1))
  done
}

desktop_labwc_workspace_keybind_lines() {
  workspace_count=${LABWC_WORKSPACE_COUNT:-4}
  keybind_workspace_count=$workspace_count
  workspace_index=1

  if [ "$keybind_workspace_count" -gt 9 ]; then
    keybind_workspace_count=9
  fi

  while [ "$workspace_index" -le "$keybind_workspace_count" ]; do
    printf '    <keybind key="W-%s">\n' "$workspace_index"
    printf '      <action name="GoToDesktop" to="%s" />\n' "$workspace_index"
    printf '    </keybind>\n'
    printf '    <keybind key="W-S-%s">\n' "$workspace_index"
    printf '      <action name="SendToDesktop" to="%s" />\n' "$workspace_index"
    printf '    </keybind>\n'
    workspace_index=$((workspace_index + 1))
  done
}

desktop_require_absolute_account_home() {
  case "${ACCOUNT_HOME:-}" in
    /*) ;;
    *)
      installer_fatal "ACCOUNT_HOME must be an absolute path for desktop account configuration"
      ;;
  esac
  case "$ACCOUNT_HOME" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "ACCOUNT_HOME contains unsupported path syntax for desktop account configuration: ${ACCOUNT_HOME}"
      ;;
  esac
}

desktop_validate_required_cmdline_token() {
  label=$1
  key=$2
  value=$3
  seen=$4

  if [ "$seen" != true ] || [ -z "$value" ]; then
    installer_fatal "${label} is required on the kernel cmdline: ${key}=..."
  fi
  case "$value" in
    *[![:print:]]*|*[[:space:]]*)
      installer_fatal "${label} must be a single printable token without whitespace: ${key}=..."
      ;;
  esac
}

desktop_validate_iface_name() {
  label=$1
  value=$2

  case "$value" in
    ''|.|..|lo)
      desktop_fatal "${label} must be a non-loopback interface name"
      ;;
  esac
  case "$value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
      desktop_fatal "${label} contains unsupported characters: ${value}"
      ;;
  esac
  [ "${#value}" -le 15 ] || desktop_fatal "${label} must be 15 characters or fewer: ${value}"
}

desktop_target_preseed_network_default_value() {
  key=$1
  defaults_path=/target/etc/default/preseed-network

  [ -r "$defaults_path" ] || return 1
  sed -n "s/^${key}='\\([^']*\\)'$/\\1/p" "$defaults_path" | sed -n '1p'
}

desktop_wsdd_params() {
  defaults_path=/target/etc/default/preseed-network
  target_ethernet_iface=
  target_wifi_iface=

  if [ -r "$defaults_path" ]; then
    target_ethernet_iface=$(desktop_target_preseed_network_default_value PRESEED_NETWORK_ETHERNET_IFACE 2>/dev/null || true)
    target_wifi_iface=$(desktop_target_preseed_network_default_value PRESEED_NETWORK_WIFI_IFACE 2>/dev/null || true)
  else
    target_ethernet_iface=${PRESEED_NETWORK_ETHERNET_IFACE:-}
    target_wifi_iface=${PRESEED_NETWORK_WIFI_IFACE:-}
  fi

  wsdd_ifaces=

  for wsdd_iface in \
    "${target_ethernet_iface:-}" \
    "${target_wifi_iface:-}"
  do
    [ -n "$wsdd_iface" ] || continue
    desktop_validate_iface_name "wsdd interface" "$wsdd_iface"
    case " $wsdd_ifaces " in
      *" $wsdd_iface "*) ;;
      *) wsdd_ifaces="${wsdd_ifaces:+$wsdd_ifaces }$wsdd_iface" ;;
    esac
  done

  wsdd_params=
  for wsdd_iface in $wsdd_ifaces; do
    wsdd_params="${wsdd_params:+$wsdd_params }-i $wsdd_iface"
  done
  printf '%s' "$wsdd_params"
}

desktop_load_calendar_cmdline_tokens() {
  [ "${DESKTOP_CALENDAR_CMDLINE_TOKENS_READY:-0}" = 1 ] && return 0

  DESKTOP_FRUUX_USERNAME=
  DESKTOP_FRUUX_PASSWORD=
  desktop_fruux_username_seen=false
  desktop_fruux_password_seen=false

  for desktop_cmdline_arg in $(installer_cmdline); do
    case "$desktop_cmdline_arg" in
      fruux_username=*)
        if [ "$desktop_fruux_username_seen" != true ]; then
          DESKTOP_FRUUX_USERNAME=${desktop_cmdline_arg#*=}
          desktop_fruux_username_seen=true
        fi
        ;;
      fruux_password=*)
        if [ "$desktop_fruux_password_seen" != true ]; then
          DESKTOP_FRUUX_PASSWORD=${desktop_cmdline_arg#*=}
          desktop_fruux_password_seen=true
        fi
        ;;
    esac
  done

  desktop_validate_required_cmdline_token "Fruux username" fruux_username "$DESKTOP_FRUUX_USERNAME" "$desktop_fruux_username_seen"
  desktop_validate_required_cmdline_token "Fruux password" fruux_password "$DESKTOP_FRUUX_PASSWORD" "$desktop_fruux_password_seen"
  DESKTOP_CALENDAR_CMDLINE_TOKENS_READY=1
}

desktop_preflight_required_cmdline_tokens() {
  desktop_load_calendar_cmdline_tokens
  desktop_log "validated_required_cmdline_tokens fruux_username=set fruux_password=set"
}

desktop_install_primary_account_calendar_stack() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"

  desktop_require_absolute_account_home

  desktop_load_calendar_cmdline_tokens
  escaped_fruux_username=$(desktop_toml_escape "$DESKTOP_FRUUX_USERNAME")
  escaped_fruux_password=$(desktop_toml_escape "$DESKTOP_FRUUX_PASSWORD")
  account_home_path="${ACCOUNT_HOME}"
  target_account_home="/target${account_home_path}"
  config_root="${account_home_path}/.config"
  data_root="${account_home_path}/.local/share/calendars"
  state_root="${account_home_path}/.local/state"
  vdirsyncer_state_root="${state_root}/vdirsyncer"
  vdirsyncer_status_root="${vdirsyncer_state_root}/status"
  personal_dir="${data_root}/personal"
  tasks_dir="${data_root}/tasks"
  personal_displayname="${personal_dir}/displayname"
  personal_color="${personal_dir}/color"
  tasks_displayname="${tasks_dir}/displayname"
  tasks_color="${tasks_dir}/color"
  vdirsyncer_dir="${config_root}/vdirsyncer"
  khal_dir="${config_root}/khal"
  todoman_dir="${config_root}/todoman"
  vdirsyncer_config="${vdirsyncer_dir}/config"
  khal_config="${khal_dir}/config"
  todoman_config="${todoman_dir}/config.py"
  fruux_calendar_url="https://dav.fruux.com/calendars/a3298084101/05b2b2d2-6d85-43f5-bfcc-21d5903eea36/"
  fruux_tasks_url="https://dav.fruux.com/calendars/a3298084101/d3e6ec9b-c656-48d8-adab-21ed7cb0f92a/"
  account_ids=$(awk -F: -v wanted_user="$ACCOUNT_USERNAME" '$1 == wanted_user { print $3 ":" $4; exit }' /target/etc/passwd)
  [ -n "$account_ids" ] || installer_fatal "failed to resolve target uid/gid for ${ACCOUNT_USERNAME}"
  case "$account_ids" in
    [0-9]*:[0-9]*)
      case "$account_ids" in
        *:*:*|*[!0-9:]*)
          installer_fatal "target uid/gid for ${ACCOUNT_USERNAME} is not numeric: ${account_ids}"
          ;;
      esac
      ;;
    *)
      installer_fatal "target uid/gid for ${ACCOUNT_USERNAME} is not numeric: ${account_ids}"
      ;;
  esac
  account_uid=${account_ids%%:*}
  account_gid=${account_ids#*:}

  install -d -m 0755 \
    "${target_account_home}/.local" \
    "${target_account_home}/.local/share" \
    "${target_account_home}/.local/state"
  install -d -m 0700 \
    "/target${vdirsyncer_dir}" \
    "/target${khal_dir}" \
    "/target${todoman_dir}" \
    "/target${personal_dir}" \
    "/target${tasks_dir}" \
    "/target${vdirsyncer_status_root}"

  desktop_render_role_target_template \
    "etc/skel/.config/vdirsyncer/config.tmpl" \
    "$vdirsyncer_config" \
    0600 \
    FRUUX_CALENDAR_URL "$fruux_calendar_url" \
    FRUUX_TASKS_URL "$fruux_tasks_url" \
    FRUUX_USERNAME "$escaped_fruux_username" \
    FRUUX_PASSWORD "$escaped_fruux_password"
  desktop_stage_role_asset "etc/skel/.config/khal/config" "$khal_config" 0600
  desktop_stage_role_asset "etc/skel/.config/todoman/config.py" "$todoman_config" 0600
  desktop_stage_role_asset "etc/skel/.local/share/calendars/personal/displayname" "$personal_displayname" 0600
  desktop_stage_role_asset "etc/skel/.local/share/calendars/personal/color" "$personal_color" 0600
  desktop_stage_role_asset "etc/skel/.local/share/calendars/tasks/displayname" "$tasks_displayname" 0600
  desktop_stage_role_asset "etc/skel/.local/share/calendars/tasks/color" "$tasks_color" 0600

  chown "$account_uid:$account_gid" \
    "${target_account_home}/.local" \
    "${target_account_home}/.local/share" \
    "${target_account_home}/.local/state"
  chown -R "$account_uid:$account_gid" \
    "/target${vdirsyncer_dir}" \
    "/target${khal_dir}" \
    "/target${todoman_dir}" \
    "/target${data_root}" \
    "/target${vdirsyncer_state_root}"
  desktop_log "rendered_calendar_stack user=${ACCOUNT_USERNAME} vdirsyncer=${vdirsyncer_config} khal=${khal_config} todoman=${todoman_config}"
}

desktop_stage_user_unit_dropin() {
  unit=$1
  dropin_name=$2
  dropin_content=$3
  unit_path=$(target_systemd_unit_path "$unit" user 2>/dev/null || true)

  if [ -z "$unit_path" ]; then
    installer_warn "target user unit is unavailable; skipping drop-in: ${unit}"
    return 0
  fi

  dropin_path="${DIR_SYSTEMD_USER}/${unit}.d/${dropin_name}"
  desktop_write_target_file "$dropin_path" 0644 "$dropin_content"
  desktop_log "staged_user_unit_dropin unit=${unit} target=${dropin_path}"
}

desktop_stage_user_unit_environment_dropin() {
  unit=$1
  dropin_name=$2
  environment_line=$3

  desktop_stage_user_unit_dropin "$unit" "$dropin_name" "[Service]
${environment_line}"
}

desktop_stage_kwallet_portal_dbus_service() {
  # shellcheck disable=SC2016
  run_in_target "stage KWallet portal backend D-Bus environment" /bin/sh -c '
set -eu
session_service_dir=$1
local_service_dir=$2
service_name=org.freedesktop.impl.portal.desktop.kwallet.service
service_path="${session_service_dir}/${service_name}"
local_service_path="${local_service_dir}/${service_name}"
divert_path="${service_path}.distrib"
duplicate_removed=0

extract_name() {
  service_file=$1
  sed -n "s/^[[:space:]]*Name[[:space:]]*=[[:space:]]*//p" "$service_file" | sed -n "1p"
}

[ -r "$service_path" ] || [ -r "$divert_path" ] || exit 0
command -v dpkg-divert >/dev/null 2>&1 || {
  printf "fatal: dpkg-divert is required for the KWallet portal D-Bus service override\n" >&2
  exit 1
}
command -v ksecretd >/dev/null 2>&1 || {
  printf "fatal: ksecretd is required for the KWallet secret portal\n" >&2
  exit 1
}

if dpkg-divert --list "$service_path" 2>/dev/null | grep -Fq "$divert_path"; then
  source_service_path=$divert_path
else
  [ -r "$service_path" ] || {
    printf "fatal: KWallet portal D-Bus service is missing: %s\n" "$service_path" >&2
    exit 1
  }
  actual_name=$(extract_name "$service_path")
  [ "$actual_name" = "org.freedesktop.impl.portal.desktop.kwallet" ] || {
    printf "fatal: unexpected D-Bus Name in %s: got %s\n" "$service_path" "${actual_name:-unset}" >&2
    exit 1
  }
  dpkg-divert --quiet --rename --add --divert "$divert_path" "$service_path"
  source_service_path=$divert_path
fi

[ -r "$source_service_path" ] || {
  printf "fatal: diverted KWallet portal D-Bus service is missing: %s\n" "$source_service_path" >&2
  exit 1
}
actual_name=$(extract_name "$source_service_path")
[ "$actual_name" = "org.freedesktop.impl.portal.desktop.kwallet" ] || {
  printf "fatal: unexpected D-Bus Name in %s: got %s\n" "$source_service_path" "${actual_name:-unset}" >&2
  exit 1
}

install -d -m 0755 "$session_service_dir"
tmp_service="${service_path}.$$"
rm -f "$tmp_service"
trap '\''rm -f "$tmp_service"'\'' EXIT HUP INT TERM
{
  printf "%s\n" "[D-BUS Service]"
  printf "%s\n" "Name=org.freedesktop.impl.portal.desktop.kwallet"
  printf "%s\n" "Exec=/usr/bin/env QT_NO_XDG_DESKTOP_PORTAL=1 /usr/bin/ksecretd"
} >"$tmp_service"
install -m 0644 "$tmp_service" "$service_path"
rm -f "$tmp_service"
trap - EXIT HUP INT TERM

if [ -e "$local_service_path" ] || [ -L "$local_service_path" ]; then
  [ ! -d "$local_service_path" ] || {
    printf "fatal: legacy KWallet local D-Bus service path is a directory: %s\n" "$local_service_path" >&2
    exit 1
  }
  rm -f "$local_service_path"
  duplicate_removed=1
fi

printf "kwallet_portal_dbus_service_staged=%s source=%s duplicate_removed=%s\n" "$service_path" "$source_service_path" "$duplicate_removed"
' sh "${DIR_DBUS_SESSION_SERVICES}" "${DIR_DBUS_LOCAL_SESSION_SERVICES}"
}

desktop_stage_portal_wayland_condition() {
  unit=$1

  desktop_stage_user_unit_dropin "$unit" 10-preseed-wayland-ready.conf '[Unit]
ConditionEnvironment=WAYLAND_DISPLAY
PartOf=graphical-session.target labwc-session.target
After=graphical-session.target labwc-session.target

[Service]
ExecCondition=/usr/bin/systemctl --user --quiet is-active graphical-session.target'
}

desktop_stage_portal_wayland_conditions() {
  for unit in \
    xdg-desktop-portal.service \
    xdg-desktop-portal-gtk.service \
    xdg-desktop-portal-wlr.service \
    xdg-desktop-portal-lxqt.service \
    xdg-desktop-portal-xapp.service
  do
    desktop_stage_portal_wayland_condition "$unit"
  done
}

desktop_stage_portal_backend_environment() {
  # Keep the requested Labwc portal backends enabled, but keep backend daemons
  # from recursively registering themselves as host portal clients.
  desktop_stage_portal_wayland_conditions
  desktop_stage_user_unit_environment_dropin \
    xdg-desktop-portal-lxqt.service \
    10-preseed-portal-backend-env.conf \
    "Environment=QT_NO_XDG_DESKTOP_PORTAL=1"
  desktop_stage_kwallet_portal_dbus_service
}

desktop_stage_labwc_user_session_assets() {
  desktop_stage_role_asset \
    etc/skel/.config/systemd/user/labwc-session.target \
    /etc/skel/.config/systemd/user/labwc-session.target \
    0644

  for unit in \
    hyprpolkitagent.service \
    xdg-desktop-portal.service \
    xdg-desktop-portal-gtk.service \
    xdg-desktop-portal-wlr.service \
    xdg-desktop-portal-lxqt.service \
    xdg-desktop-portal-xapp.service
  do
    desktop_stage_role_asset \
      "etc/skel/.config/systemd/user/${unit}.d/10-labwc-session.conf" \
      "/etc/skel/.config/systemd/user/${unit}.d/10-labwc-session.conf" \
      0644
  done
}

desktop_render_greetd_config() {
  desktop_render_role_target_template \
    "etc/greetd/config.toml.tmpl" \
    "/etc/greetd/config.toml" \
    0644 \
    LABWC_GREETER_VT "${LABWC_GREETER_VT:-1}" \
    LABWC_GREETER_COMMAND_ESCAPED "$(desktop_toml_escape "${LABWC_GREETER_COMMAND:-/usr/local/bin/labwc-greeter-session}")" \
    LABWC_GREETER_USER_ESCAPED "$(desktop_toml_escape "${LABWC_GREETER_USER:-greeter}")"
  desktop_log "rendered_greetd_config user=${LABWC_GREETER_USER:-greeter} vt=${LABWC_GREETER_VT:-1}"
}

desktop_render_labwc_rc_xml() {
  workspace_count=${LABWC_WORKSPACE_COUNT:-4}
  rc_path=/etc/skel/.config/labwc/rc.xml

  desktop_render_role_target_template \
    "etc/skel/.config/labwc/rc.xml.tmpl" \
    "$rc_path" \
    0644 \
    LABWC_WORKSPACE_COUNT "$workspace_count" \
    LABWC_ICON_THEME "$(desktop_xml_attribute_escape "${LABWC_ICON_THEME:-Papirus-Dark}")" \
    LABWC_FILE_MANAGER_COMMAND "$(desktop_xml_attribute_escape "${LABWC_FILE_MANAGER_COMMAND:-thunar}")" \
    LABWC_AUDIO_CONTROL_COMMAND "$(desktop_xml_attribute_escape "${LABWC_AUDIO_CONTROL_COMMAND:-pavucontrol}")"
  desktop_replace_block_placeholder_in_target \
    "$rc_path" \
    "__INSTALLER_LABWC_WORKSPACE_NAME_LINES__" \
    "$(desktop_labwc_workspace_name_lines)"
  desktop_replace_block_placeholder_in_target \
    "$rc_path" \
    "__INSTALLER_LABWC_WORKSPACE_KEYBIND_LINES__" \
    "$(desktop_labwc_workspace_keybind_lines)"
  desktop_log "rendered_labwc_rc_xml workspaces=${workspace_count}"
}

desktop_nvidia_dgpu_enabled() {
  installer_selected_class_reference_is_selected addon/nvidia 2>/dev/null || return 1
  target_nvidia_modprobe="/target${FILE_MODPROBE_NVIDIA:-/etc/modprobe.d/nvidia.conf}"
  [ -r "$target_nvidia_modprobe" ] || return 1
  grep -q '^options nvidia_drm modeset=1$' "$target_nvidia_modprobe"
}

desktop_waybar_dgpu_modules_left_json() {
  if desktop_nvidia_dgpu_enabled; then
    printf ', "custom/dgpu"'
  fi
}

desktop_waybar_dgpu_module_definition_block() {
  if ! desktop_nvidia_dgpu_enabled; then
    return 0
  fi

  cat <<'EOF'
  "custom/dgpu": {
    "format": "GPU",
    "tooltip": false,
    "on-click": "labwc-dgpu-launcher"
  },
EOF
}

desktop_render_waybar_config() {
  waybar_path=/etc/skel/.config/waybar/config

  desktop_render_role_target_template \
    "etc/skel/.config/waybar/config.tmpl" \
    "$waybar_path" \
    0644 \
    LABWC_WAYBAR_DGPU_MODULES_LEFT "$(desktop_waybar_dgpu_modules_left_json)" \
    LABWC_FILE_MANAGER_COMMAND "$(desktop_double_quote_escape "${LABWC_FILE_MANAGER_COMMAND:-thunar}")" \
    LABWC_CALENDAR_COMMAND "$(desktop_double_quote_escape "${LABWC_CALENDAR_COMMAND:-labwc-calendar}")" \
    LABWC_AUDIO_CONTROL_COMMAND "$(desktop_double_quote_escape "${LABWC_AUDIO_CONTROL_COMMAND:-pavucontrol}")" \
    LABWC_BRIGHTNESS_CONTROL_COMMAND "$(desktop_double_quote_escape "${LABWC_BRIGHTNESS_CONTROL_COMMAND:-labwc-brightness-control}")" \
    LABWC_POWER_SETTINGS_COMMAND "$(desktop_double_quote_escape "${LABWC_POWER_SETTINGS_COMMAND:-labwc-power-settings}")"
  desktop_replace_block_placeholder_in_target \
    "$waybar_path" \
    "__INSTALLER_LABWC_WAYBAR_DGPU_MODULE_DEFINITION__" \
    "$(desktop_waybar_dgpu_module_definition_block)"
  desktop_log "rendered_waybar_config native_workspaces=true"
}

desktop_render_chromium_flags() {
  desktop_render_role_target_template \
    "etc/chromium.d/90-preseed-performance-flags.tmpl" \
    "/etc/chromium.d/90-preseed-performance-flags" \
    0644
  desktop_log "rendered_chromium_flags gpu_wayland_defaults=managed"
}

desktop_install_primary_account_slice_limits() {
  target_dropin=/etc/systemd/system/user-1000.slice.d/50-resource-limit.conf
  desktop_render_shared_target_template \
    "etc/systemd/system/user-1000.slice.d/50-resource-limit.conf" \
    "$target_dropin" \
    0644 \
    DEBIAN_SLICE_CPU_QUOTA "${DEBIAN_SLICE_CPU_QUOTA:-600%}" \
    DEBIAN_SLICE_MEMORY_HIGH "${DEBIAN_SLICE_MEMORY_HIGH:-80%}"

  # shellcheck disable=SC2016
  run_in_target "verify Labwc desktop user slice resource limits" /bin/sh -c '
set -eu
dropin=$1
cpu_quota=$2
memory_high=$3

[ -r "$dropin" ] || {
  printf "fatal: desktop user slice drop-in is missing: %s\n" "$dropin" >&2
  exit 1
}

grep -q "^CPUQuota=${cpu_quota}\$" "$dropin"
grep -q "^MemoryHigh=${memory_high}\$" "$dropin"
grep -q "^TasksMax=12288\$" "$dropin"
grep -q "^IOWeight=100\$" "$dropin"
  ' sh \
    "$target_dropin" \
    "${DEBIAN_SLICE_CPU_QUOTA:-600%}" \
    "${DEBIAN_SLICE_MEMORY_HIGH:-80%}"
  desktop_log "staged_user_slice_resource_limits slice=user-1000 target=${target_dropin}"
}

desktop_configure_greeter_access() {
  : "${LABWC_GREETER_USER:?LABWC_GREETER_USER must be set}"

  # The greeter runs before any real user session exists, so grant the
  # compositor access paths it needs up front.
  run_in_target "configure Labwc greeter seat and DRM access" /bin/sh -c '
set -eu
greeter_user=$1
requested_groups="seat render video"
existing_groups=
missing_groups=
current_groups=$(id -nG "$greeter_user")

for group_name in $requested_groups; do
  if getent group "$group_name" >/dev/null 2>&1; then
    existing_groups="${existing_groups:+$existing_groups,}$group_name"
    case " $current_groups " in
      *" $group_name "*) ;;
      *)
        missing_groups="${missing_groups:+$missing_groups,}$group_name"
        ;;
    esac
  fi
done

[ -n "$existing_groups" ] || {
  printf "fatal: no greeter access groups are available for %s\n" "$greeter_user" >&2
  exit 1
}

if [ -n "$missing_groups" ]; then
  usermod -a -G "$missing_groups" "$greeter_user"
  current_groups=$(id -nG "$greeter_user")
fi
printf "desktop_greeter_access user=%s requested=%s current=%s\n" \
  "$greeter_user" \
  "$existing_groups" \
  "$current_groups"
' sh "$LABWC_GREETER_USER"
  desktop_log "configured_greeter_access user=${LABWC_GREETER_USER}"
}

desktop_stage_target_assets() {
  wsdd_params=$(desktop_wsdd_params)

  desktop_stage_role_asset etc/environment.d/90-labwc-session.conf /etc/environment.d/90-labwc-session.conf 0644
  desktop_stage_role_asset etc/pam.d/greetd /etc/pam.d/greetd 0644
  desktop_stage_role_asset etc/pam.d/greetd-greeter /etc/pam.d/greetd-greeter 0644
  desktop_stage_role_asset usr/local/bin/labwc-greeter-session /usr/local/bin/labwc-greeter-session 0755
  desktop_stage_role_asset usr/local/bin/labwc-session /usr/local/bin/labwc-session 0755
  desktop_stage_role_asset usr/local/bin/labwc-autostart /usr/local/bin/labwc-autostart 0755
  desktop_stage_role_asset usr/local/bin/labwc-admin-action /usr/local/bin/labwc-admin-action 0755
  desktop_stage_role_asset usr/local/bin/labwc-calendar /usr/local/bin/labwc-calendar 0755
  desktop_stage_role_asset usr/local/bin/labwc-logout /usr/local/bin/labwc-logout 0755
  desktop_stage_role_asset usr/local/bin/labwc-wofi /usr/local/bin/labwc-wofi 0755
  desktop_stage_role_asset usr/local/bin/labwc-dgpu-launcher /usr/local/bin/labwc-dgpu-launcher 0755
  desktop_stage_role_asset usr/local/bin/labwc-output-refresh /usr/local/bin/labwc-output-refresh 0755
  desktop_stage_role_asset usr/local/bin/labwc-output-watch /usr/local/bin/labwc-output-watch 0755
  desktop_stage_role_asset usr/local/bin/labwc-lock /usr/local/bin/labwc-lock 0755
  desktop_stage_role_asset usr/local/bin/labwc-terminal /usr/local/bin/labwc-terminal 0755
  desktop_stage_role_asset usr/local/bin/labwc-brightness-control /usr/local/bin/labwc-brightness-control 0755
  desktop_stage_role_asset usr/local/bin/labwc-power-settings /usr/local/bin/labwc-power-settings 0755
  desktop_stage_role_asset usr/local/bin/labwc-run /usr/local/bin/labwc-run 0755
  desktop_stage_role_asset usr/local/bin/labwc-power-menu /usr/local/bin/labwc-power-menu 0755
  desktop_stage_role_asset usr/local/bin/labwc-keyboard-layout /usr/local/bin/labwc-keyboard-layout 0755
  desktop_stage_role_asset usr/local/bin/labwc-dock /usr/local/bin/labwc-dock 0755

  desktop_stage_role_asset usr/share/wayland-sessions/labwc.desktop /usr/share/wayland-sessions/labwc.desktop 0644
  desktop_stage_role_asset etc/greetd/gtkgreet.css /etc/greetd/gtkgreet.css 0644
  desktop_stage_role_asset etc/bluetooth/main.conf /etc/bluetooth/main.conf 0644
  desktop_stage_role_asset etc/systemd/system/greetd.service.d/20-labwc-vt.conf /etc/systemd/system/greetd.service.d/20-labwc-vt.conf 0644
  desktop_stage_role_asset etc/systemd/system/bluetooth.service.d/10-preseed-directory-mode.conf /etc/systemd/system/bluetooth.service.d/10-preseed-directory-mode.conf 0644
  desktop_stage_portal_backend_environment
  desktop_render_shared_target_template "etc/wsdd-server/defaults.tmpl" "/etc/wsdd-server/defaults" 0644 \
    WSDD_PARAMS "$(desktop_double_quote_escape "$wsdd_params")"
  desktop_stage_role_asset etc/xdg/xdg-desktop-portal/labwc-portals.conf /etc/xdg/xdg-desktop-portal/labwc-portals.conf 0644
  desktop_stage_role_asset etc/systemd/user/labwc-calendar-sync.service /etc/systemd/user/labwc-calendar-sync.service 0644
  desktop_stage_role_asset etc/systemd/user/labwc-calendar-sync.timer /etc/systemd/user/labwc-calendar-sync.timer 0644

  desktop_stage_role_asset usr/share/backgrounds/labwc/wallpapers/wall-labwall2-1920x1080.png /usr/share/backgrounds/labwc/wallpapers/wall-labwall2-1920x1080.png 0644
  desktop_stage_role_asset usr/share/backgrounds/labwc/wallpapers/lock-labwall2-1920x1080.png /usr/share/backgrounds/labwc/wallpapers/lock-labwall2-1920x1080.png 0644
  desktop_stage_role_asset usr/share/backgrounds/labwc/wallpapers/regreet-labwall2-1920x1080.png /usr/share/backgrounds/labwc/wallpapers/regreet-labwall2-1920x1080.png 0644
  desktop_stage_role_asset usr/share/backgrounds/labwc/wallpapers/regreet-000-greeter-purple.svg /usr/share/backgrounds/labwc/wallpapers/regreet-000-greeter-purple.svg 0644

  desktop_stage_role_asset etc/skel/.config/labwc/environment /etc/skel/.config/labwc/environment 0644
  desktop_stage_role_asset etc/skel/.config/labwc/environment.d/10-wayland.env /etc/skel/.config/labwc/environment.d/10-wayland.env 0644
  desktop_stage_role_asset etc/skel/.config/labwc/autostart /etc/skel/.config/labwc/autostart 0755
  desktop_stage_role_asset etc/skel/.config/labwc/shutdown /etc/skel/.config/labwc/shutdown 0755
  desktop_stage_labwc_user_session_assets
  remove_target_asset /etc/skel/.config/labwc/xinitrc
  remove_target_asset /etc/skel/.config/gsimplecal/config
  desktop_stage_role_asset etc/skel/.config/labwc/themerc-override /etc/skel/.config/labwc/themerc-override 0644
  desktop_render_labwc_rc_xml
  desktop_stage_role_asset etc/skel/.config/labwc/menu.xml /etc/skel/.config/labwc/menu.xml 0644
  desktop_render_waybar_config
  desktop_stage_role_asset etc/skel/.config/waybar/style.css /etc/skel/.config/waybar/style.css 0644
  desktop_stage_role_asset etc/skel/.config/waybar/icons/nvidia.svg /etc/skel/.config/waybar/icons/nvidia.svg 0644
  desktop_stage_role_asset etc/skel/.config/kanshi/config /etc/skel/.config/kanshi/config 0644
  desktop_stage_role_asset etc/skel/.config/foot/foot.ini /etc/skel/.config/foot/foot.ini 0644
  desktop_stage_role_asset etc/skel/.config/kitty/kitty.conf /etc/skel/.config/kitty/kitty.conf 0644
  desktop_stage_role_asset etc/skel/.config/xdg-terminals.list /etc/skel/.config/xdg-terminals.list 0644
  desktop_stage_role_asset etc/skel/.config/xfce4/helpers.rc /etc/skel/.config/xfce4/helpers.rc 0644
  desktop_stage_role_asset usr/share/xfce4/helpers/foot.desktop /usr/share/xfce4/helpers/foot.desktop 0644
  desktop_stage_role_asset etc/skel/.profile /etc/skel/.profile 0644
  desktop_stage_role_asset etc/skel/.bash_profile /etc/skel/.bash_profile 0644
  desktop_stage_role_asset etc/skel/.bashrc /etc/skel/.bashrc 0644
  desktop_stage_role_asset etc/skel/.zprofile /etc/skel/.zprofile 0644
  desktop_stage_role_asset etc/skel/.zshrc /etc/skel/.zshrc 0644
  desktop_stage_role_asset etc/skel/.config/starship.toml /etc/skel/.config/starship.toml 0644
  desktop_stage_role_asset etc/skel/btop/btop.conf /etc/skel/.config/btop/btop.conf 0644
  desktop_stage_role_asset etc/skel/fzf/default-opts /etc/skel/.config/fzf/default-opts 0644
  desktop_stage_role_asset etc/skel/.config/wofi/config /etc/skel/.config/wofi/config 0644
  desktop_stage_role_asset etc/skel/.config/wofi/style.css /etc/skel/.config/wofi/style.css 0644
  desktop_stage_role_asset etc/skel/.config/wofi/colors /etc/skel/.config/wofi/colors 0644
  desktop_stage_role_asset etc/skel/.config/Thunar/uca.xml /etc/skel/.config/Thunar/uca.xml 0644
  desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/appearance.conf /etc/skel/.config/crystal-dock/labwc/appearance.conf 0644
  desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/panel_1.conf /etc/skel/.config/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/appearance.conf /etc/xdg/crystal-dock/labwc/appearance.conf 0644
  desktop_stage_role_asset etc/skel/.config/crystal-dock/labwc/panel_1.conf /etc/xdg/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset etc/skel/.config/mako/config /etc/skel/.config/mako/config 0644
  desktop_stage_role_asset etc/skel/.config/swaylock/config /etc/skel/.config/swaylock/config 0644
  desktop_stage_role_asset etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf /etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644
  desktop_stage_role_asset etc/skel/.config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini 0644
  desktop_stage_role_asset etc/skel/.config/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini 0644
  desktop_stage_role_asset etc/skel/.config/gtk-3.0/settings.ini /etc/xdg/gtk-3.0/settings.ini 0644
  desktop_stage_role_asset etc/skel/.config/gtk-4.0/settings.ini /etc/xdg/gtk-4.0/settings.ini 0644
  desktop_stage_role_asset etc/skel/.config/qt6ct/qt6ct.conf /etc/skel/.config/qt6ct/qt6ct.conf 0644
  desktop_stage_role_asset etc/skel/.config/kwalletrc /etc/skel/.config/kwalletrc 0644
  desktop_stage_role_asset etc/skel/.config/xdg-desktop-portal/portals.conf /etc/skel/.config/xdg-desktop-portal/portals.conf 0644
  desktop_stage_role_asset etc/skel/.config/user-dirs.dirs /etc/skel/.config/user-dirs.dirs 0644
  desktop_render_chromium_flags
}

desktop_install_user_config() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"

  desktop_log "installing primary account desktop config user=${ACCOUNT_USERNAME} home=${ACCOUNT_HOME}"
  # shellcheck disable=SC2016
  run_in_target "install Labwc desktop config for primary account" /bin/sh -c '
set -eu
account_user=$1
account_home=$2
copied_dirs=0
copied_files=0

case "$account_home" in
  /*) ;;
  *) printf "fatal: account home must be absolute\n" >&2; exit 1 ;;
esac
case "$account_home" in
  /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
    printf "fatal: account home contains unsupported path syntax: %s\n" "$account_home" >&2
    exit 1
    ;;
esac

uid=$(id -u "$account_user")
gid=$(id -g "$account_user")

  install -d -m 0755 "$account_home" "$account_home/.config"
  for rel in \
    .config/labwc \
    .config/waybar \
    .config/kanshi \
    .config/foot \
    .config/kitty \
    .config/xfce4 \
    .config/btop \
    .config/fzf \
    .config/wofi \
    .config/Thunar \
    .config/crystal-dock \
    .config/mako \
    .config/swaylock \
    .config/wireplumber \
    .config/gtk-3.0 \
    .config/gtk-4.0 \
    .config/qt6ct \
    .config/systemd \
    .config/xdg-desktop-portal
  do
  src="/etc/skel/${rel}"
  dst="${account_home}/${rel}"
  [ -d "$src" ] || { printf "fatal: missing skel source: %s\n" "$src" >&2; exit 1; }
  install -d -m 0755 "$dst"
  cp -a "$src/." "$dst/"
  chown -R "$uid:$gid" "$dst"
  copied_dirs=$((copied_dirs + 1))
done
rm -f "$account_home/.config/labwc/xinitrc"
  for rel_file in .profile .bash_profile .bashrc .zprofile .zshrc .config/kwalletrc .config/starship.toml .config/xdg-terminals.list .config/user-dirs.dirs; do
  src="/etc/skel/${rel_file}"
  dst="${account_home}/${rel_file}"
  [ -r "$src" ] || { printf "fatal: missing skel source: %s\n" "$src" >&2; exit 1; }
  install -d -m 0755 "$(dirname "$dst")"
  install -m 0644 "$src" "$dst"
  chown "$uid:$gid" "$dst"
  copied_files=$((copied_files + 1))
done
zsh_path=$(command -v zsh 2>/dev/null || true)
if [ -n "$zsh_path" ]; then
  usermod -s "$zsh_path" "$account_user"
fi
chown "$uid:$gid" "$account_home" "$account_home/.config"
account_shell=$(getent passwd "$account_user" | cut -d: -f7)
printf "desktop_account_config user=%s home=%s copied_dirs=%s copied_files=%s shell=%s\n" "$account_user" "$account_home" "$copied_dirs" "$copied_files" "$account_shell"
' sh "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
  desktop_install_primary_account_calendar_stack
  desktop_log "installed primary account desktop config user=${ACCOUNT_USERNAME}"
}

desktop_unit_has_install_entry() {
  unit=$1
  scope=$2
  unit_path=$3

  for install_key in WantedBy RequiredBy Alias Also; do
    for install_value in $(target_systemd_install_values "$unit_path" "$install_key"); do
      [ -n "$install_value" ] || continue
      return 0
    done
  done
  installer_info "target ${scope} unit has no [Install] entry; leaving static unit unmanaged: ${unit}"
  return 1
}

desktop_enable_unit_if_available() {
  unit=$1
  scope=$2
  unit_path=$(target_systemd_unit_path "$unit" "$scope" 2>/dev/null || true)

  if [ -z "$unit_path" ]; then
    installer_warn "target ${scope} unit is unavailable; skipping enablement: ${unit}"
    return 0
  fi
  desktop_unit_has_install_entry "$unit" "$scope" "$unit_path" || return 0
  stage_target_systemd_unit_enabled "$unit" "$scope"
  desktop_log "staged_${scope}_unit_enabled unit=${unit} unit_path=${unit_path}"
}

desktop_enable_target_services() {
  desktop_enable_unit_if_available greetd.service system
  desktop_enable_unit_if_available seatd.service system
  desktop_enable_unit_if_available bluetooth.service system
  desktop_enable_unit_if_available rtkit-daemon.service system
  desktop_enable_unit_if_available upower.service system
  desktop_enable_unit_if_available power-profiles-daemon.service system
  desktop_enable_unit_if_available switcheroo-control.service system
  desktop_enable_unit_if_available udisks2.service system
  desktop_enable_unit_if_available NetworkManager.service system
  desktop_enable_unit_if_available NetworkManager-dispatcher.service system

  desktop_enable_unit_if_available pipewire.socket user
  desktop_enable_unit_if_available pipewire-pulse.socket user
  desktop_enable_unit_if_available wireplumber.service user
  # Let portals start by D-Bus activation after labwc exports WAYLAND_DISPLAY.
  desktop_enable_unit_if_available labwc-calendar-sync.timer user

  stage_target_default_systemd_unit "${LABWC_DESKTOP_DEFAULT_TARGET:-graphical.target}"
  desktop_log "staged_default_target target=${LABWC_DESKTOP_DEFAULT_TARGET:-graphical.target}"
}
