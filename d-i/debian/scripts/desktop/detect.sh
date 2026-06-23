#!/bin/sh
# Labwc desktop installer-side detection and policy rendering helpers.

desktop_fatal() {
  installer_fatal "$@"
}

desktop_policy_enabled() {
  case "${LABWC_DESKTOP_ENABLE:-true}" in
    true|yes|1|on) return 0 ;;
    false|no|0|off) return 1 ;;
    *) desktop_fatal "invalid LABWC_DESKTOP_ENABLE: ${LABWC_DESKTOP_ENABLE}" ;;
  esac
}

desktop_validate_bool() {
  var_name=$1
  var_value=$2

  case "$var_value" in
    true|false|yes|no|1|0|on|off) ;;
    *) desktop_fatal "${var_name} must be boolean-like, got: ${var_value:-unset}" ;;
  esac
}

desktop_validate_uint_range() {
  var_name=$1
  var_value=$2
  min_value=$3
  max_value=$4

  case "$var_value" in
    ''|*[!0-9]*) desktop_fatal "${var_name} must be numeric, got: ${var_value:-unset}" ;;
  esac
  [ "$var_value" -ge "$min_value" ] || desktop_fatal "${var_name} must be >= ${min_value}"
  [ "$var_value" -le "$max_value" ] || desktop_fatal "${var_name} must be <= ${max_value}"
}

desktop_validate_optional_uint_range() {
  var_name=$1
  var_value=$2
  min_value=$3
  max_value=$4

  [ -n "$var_value" ] || return 0
  desktop_validate_uint_range "$var_name" "$var_value" "$min_value" "$max_value"
}

desktop_validate_percent_string() {
  var_name=$1
  var_value=$2
  min_value=$3
  max_value=$4

  case "$var_value" in
    [0-9]*%)
      numeric_value=${var_value%%%}
      ;;
    *)
      desktop_fatal "${var_name} must be an integer percentage like 80%%, got: ${var_value:-unset}"
      ;;
  esac
  case "$numeric_value" in
    ''|*[!0-9]*)
      desktop_fatal "${var_name} must be an integer percentage like 80%%, got: ${var_value:-unset}"
      ;;
  esac
  [ "$numeric_value" -ge "$min_value" ] || desktop_fatal "${var_name} must be >= ${min_value}%"
  [ "$numeric_value" -le "$max_value" ] || desktop_fatal "${var_name} must be <= ${max_value}%"
}

desktop_validate_decimal_range() {
  var_name=$1
  var_value=$2
  min_value=$3
  max_value=$4

  printf '%s\n' "$var_value" | LC_ALL=C grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
    desktop_fatal "${var_name} must be a decimal value, got: ${var_value:-unset}"
  awk "BEGIN { exit !($var_value >= $min_value && $var_value <= $max_value) }" || \
    desktop_fatal "${var_name} must be between ${min_value} and ${max_value}"
}

desktop_validate_output_mode_policy() {
  output_width=${LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH:-}
  output_height=${LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT:-}
  output_refresh=${LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ:-}

  case "${output_width}:${output_height}" in
    :)
      [ -z "$output_refresh" ] ||
        desktop_fatal "LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ requires preferred width and height"
      ;;
    *:)
      desktop_fatal "LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT is required when preferred width is set"
      ;;
    :*)
      desktop_fatal "LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH is required when preferred height is set"
      ;;
  esac
}

desktop_validate_absolute_path() {
  var_name=$1
  var_value=$2

  case "$var_value" in
    /*) ;;
    *) desktop_fatal "${var_name} must be an absolute path" ;;
  esac
  case "$var_value" in
    *..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+@%=:,/-]*)
      desktop_fatal "${var_name} contains unsupported path characters: ${var_value}"
      ;;
  esac
}

desktop_validate_command_string() {
  var_name=$1
  var_value=$2

  [ -n "$var_value" ] || desktop_fatal "${var_name} must not be empty"
  case "$var_value" in
    *'
'*)
      desktop_fatal "${var_name} must be a single-line command"
      ;;
  esac
  case "$var_value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+@%=:,/\ -]*)
      desktop_fatal "${var_name} contains unsupported command characters: ${var_value}"
      ;;
  esac
}

desktop_validate_identifier_list() {
  var_name=$1
  var_value=$2

  case "$var_value" in
    *'
'*)
      desktop_fatal "${var_name} must be a single-line identifier list"
      ;;
  esac
  case "$var_value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:@%+=,\ -]*)
      desktop_fatal "${var_name} contains unsupported identifier characters: ${var_value}"
      ;;
  esac
}

desktop_validate_unit_name() {
  var_name=$1
  var_value=$2

  [ -n "$var_value" ] || desktop_fatal "${var_name} must not be empty"
  case "$var_value" in
    *'
'*)
      desktop_fatal "${var_name} must be a single-line unit name"
      ;;
  esac
  case "$var_value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@:-]*)
      desktop_fatal "${var_name} contains unsupported unit name characters: ${var_value}"
      ;;
  esac
  case "$var_value" in
    *.target) ;;
    *) desktop_fatal "${var_name} must be a systemd target unit name, got: ${var_value}" ;;
  esac
}

desktop_validate_wayland_backend() {
  var_name=$1
  var_value=$2

  case "$var_value" in
    wayland) ;;
    *)
      desktop_fatal "${var_name} must stay native Wayland-only, got: ${var_value:-unset}"
      ;;
  esac
}

desktop_validate_keyboard_layout_policy() {
  layouts=${LABWC_KEYBOARD_LAYOUTS:-us se}
  default_layout=${LABWC_KEYBOARD_DEFAULT_LAYOUT:-us}
  default_found=false

  desktop_validate_identifier_list LABWC_KEYBOARD_LAYOUTS "$layouts"
  desktop_validate_identifier_list LABWC_KEYBOARD_DEFAULT_LAYOUT "$default_layout"
  for layout in $layouts; do
    case "$layout" in
      us|se) ;;
      *) desktop_fatal "LABWC_KEYBOARD_LAYOUTS supports only us and se, got: ${layout}" ;;
    esac
    [ "$layout" != "$default_layout" ] || default_found=true
  done
  [ "$default_found" = true ] || desktop_fatal "LABWC_KEYBOARD_DEFAULT_LAYOUT must be included in LABWC_KEYBOARD_LAYOUTS"
}

desktop_validate_policy_env() {
  desktop_validate_bool LABWC_ENABLE_WAYBAR "${LABWC_ENABLE_WAYBAR:-true}"
  desktop_validate_bool LABWC_ENABLE_KANSHI "${LABWC_ENABLE_KANSHI:-true}"
  desktop_validate_bool LABWC_ENABLE_MAKO "${LABWC_ENABLE_MAKO:-true}"
  desktop_validate_bool LABWC_ENABLE_SWAYIDLE "${LABWC_ENABLE_SWAYIDLE:-true}"
  desktop_validate_bool LABWC_ENABLE_SWAYBG "${LABWC_ENABLE_SWAYBG:-true}"
  desktop_validate_bool LABWC_ENABLE_POLKIT_AGENT "${LABWC_ENABLE_POLKIT_AGENT:-true}"
  desktop_validate_bool LABWC_ENABLE_XDG_DESKTOP_PORTAL "${LABWC_ENABLE_XDG_DESKTOP_PORTAL:-true}"
  desktop_validate_bool LABWC_ENABLE_CRYSTAL_DOCK "${LABWC_ENABLE_CRYSTAL_DOCK:-true}"

  desktop_validate_uint_range LABWC_GREETER_VT "${LABWC_GREETER_VT:-1}" 1 12
  desktop_validate_optional_uint_range LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH "${LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH:-}" 640 16384
  desktop_validate_optional_uint_range LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT "${LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT:-}" 480 8640
  desktop_validate_optional_uint_range LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ "${LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ:-}" 24 1000
  desktop_validate_output_mode_policy
  desktop_validate_decimal_range LABWC_OUTPUT_SCALE "${LABWC_OUTPUT_SCALE:-1}" 0.5 3
  desktop_validate_decimal_range LABWC_OUTPUT_INTERNAL_SCALE "${LABWC_OUTPUT_INTERNAL_SCALE:-1}" 0.5 3
  desktop_validate_decimal_range LABWC_OUTPUT_EXTERNAL_SCALE "${LABWC_OUTPUT_EXTERNAL_SCALE:-1.80}" 0.5 3
  desktop_validate_uint_range LABWC_OUTPUT_FALLBACK_REFRESH_HZ "${LABWC_OUTPUT_FALLBACK_REFRESH_HZ:-60}" 24 1000
  desktop_validate_uint_range LABWC_OUTPUT_HOTPLUG_DEBOUNCE_SECONDS "${LABWC_OUTPUT_HOTPLUG_DEBOUNCE_SECONDS:-2}" 0 30
  desktop_validate_uint_range LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS "${LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS:-1}" 0 30
  desktop_validate_uint_range LABWC_IDLE_LOCK_SECONDS "${LABWC_IDLE_LOCK_SECONDS:-900}" 60 86400
  desktop_validate_uint_range LABWC_IDLE_DPMS_SECONDS "${LABWC_IDLE_DPMS_SECONDS:-1200}" 60 86400
  desktop_validate_uint_range LABWC_IDLE_SUSPEND_SECONDS "${LABWC_IDLE_SUSPEND_SECONDS:-0}" 0 86400
  desktop_validate_uint_range LABWC_WAYBAR_START_DELAY_SECONDS "${LABWC_WAYBAR_START_DELAY_SECONDS:-0}" 0 30
  desktop_validate_uint_range LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS "${LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS:-1}" 0 30
  desktop_validate_uint_range LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS "${LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS:-4}" 0 30
  desktop_validate_uint_range LABWC_WORKSPACE_COUNT "${LABWC_WORKSPACE_COUNT:-4}" 1 12
  desktop_validate_percent_string DEBIAN_SLICE_CPU_QUOTA "${DEBIAN_SLICE_CPU_QUOTA:-600%}" 1 10000
  desktop_validate_percent_string DEBIAN_SLICE_MEMORY_HIGH "${DEBIAN_SLICE_MEMORY_HIGH:-80%}" 1 100

  desktop_validate_unit_name LABWC_DESKTOP_DEFAULT_TARGET "${LABWC_DESKTOP_DEFAULT_TARGET:-graphical.target}"
  desktop_validate_identifier_list LABWC_OUTPUT_INTERNAL_PREFIXES "${LABWC_OUTPUT_INTERNAL_PREFIXES:-eDP LVDS DSI}"
  desktop_validate_identifier_list LABWC_GREETER_USER_CANDIDATES "${LABWC_GREETER_USER_CANDIDATES:-_greetd greeter greetd}"
  desktop_validate_absolute_path LABWC_DESKTOP_DEFAULTS_FILE "${LABWC_DESKTOP_DEFAULTS_FILE:-/etc/default/labwc-desktop}"
  desktop_validate_absolute_path LABWC_DESKTOP_SESSION_COMMAND "${LABWC_DESKTOP_SESSION_COMMAND:-/usr/local/bin/labwc-session}"
  desktop_validate_absolute_path LABWC_WALLPAPER_PATH "${LABWC_WALLPAPER_PATH:-/usr/share/backgrounds/labwc/wallpapers/wall-labwall2-1920x1080.png}"
  desktop_validate_absolute_path LABWC_LOCK_BACKGROUND_PATH "${LABWC_LOCK_BACKGROUND_PATH:-/usr/share/backgrounds/labwc/wallpapers/lock-labwall2-1920x1080.png}"
  desktop_validate_absolute_path LABWC_GREETER_BACKGROUND_PATH "${LABWC_GREETER_BACKGROUND_PATH:-/usr/share/backgrounds/labwc/wallpapers/regreet-labwall2-1920x1080.png}"
  desktop_validate_command_string LABWC_GREETER_COMMAND "${LABWC_GREETER_COMMAND:-/usr/local/bin/labwc-greeter-session}"
  desktop_validate_command_string LABWC_CRYSTAL_DOCK_COMMAND "${LABWC_CRYSTAL_DOCK_COMMAND:-crystal-dock}"
  desktop_validate_command_string LABWC_LAUNCHER_COMMAND "${LABWC_LAUNCHER_COMMAND:-labwc-wofi --show drun}"
  desktop_validate_command_string LABWC_MENU_COMMAND "${LABWC_MENU_COMMAND:-labwc-wofi --show drun}"
  desktop_validate_command_string LABWC_FILE_MANAGER_COMMAND "${LABWC_FILE_MANAGER_COMMAND:-thunar}"
  desktop_validate_command_string LABWC_AUDIO_CONTROL_COMMAND "${LABWC_AUDIO_CONTROL_COMMAND:-pavucontrol}"
  desktop_validate_command_string LABWC_DISPLAY_CONTROL_COMMAND "${LABWC_DISPLAY_CONTROL_COMMAND:-wdisplays}"
  desktop_validate_command_string LABWC_CALENDAR_COMMAND "${LABWC_CALENDAR_COMMAND:-labwc-calendar}"
  desktop_validate_command_string LABWC_BRIGHTNESS_CONTROL_COMMAND "${LABWC_BRIGHTNESS_CONTROL_COMMAND:-labwc-brightness-control}"
  desktop_validate_command_string LABWC_POWER_SETTINGS_COMMAND "${LABWC_POWER_SETTINGS_COMMAND:-labwc-power-settings}"
  desktop_validate_wayland_backend LABWC_GDK_BACKEND "${LABWC_GDK_BACKEND:-wayland}"
  desktop_validate_wayland_backend LABWC_QT_QPA_PLATFORM "${LABWC_QT_QPA_PLATFORM:-wayland}"
  desktop_validate_wayland_backend LABWC_SDL_VIDEODRIVER "${LABWC_SDL_VIDEODRIVER:-wayland}"
  desktop_validate_wayland_backend LABWC_CLUTTER_BACKEND "${LABWC_CLUTTER_BACKEND:-wayland}"
  desktop_validate_keyboard_layout_policy

  case "${LABWC_OUTPUT_POLICY:-external-only}" in
    external-only) ;;
    *) desktop_fatal "unsupported LABWC_OUTPUT_POLICY: ${LABWC_OUTPUT_POLICY}" ;;
  esac
}

desktop_is_internal_output() {
  output_name=$1

  for output_prefix in ${LABWC_OUTPUT_INTERNAL_PREFIXES:-eDP LVDS DSI}; do
    case "$output_name" in
      "${output_prefix}"-*|"${output_prefix}"[0-9]*)
        return 0
        ;;
    esac
  done
  return 1
}

desktop_detect_connected_drm_outputs() {
  LABWC_DETECTED_OUTPUTS=
  LABWC_DETECTED_INTERNAL_OUTPUTS=
  LABWC_DETECTED_EXTERNAL_OUTPUTS=

  for status_path in /sys/class/drm/card*-*/status; do
    [ -r "$status_path" ] || continue
    status_value=$(sed -n '1p' "$status_path" 2>/dev/null || true)
    [ "$status_value" = connected ] || continue
    connector_name=${status_path%/status}
    connector_name=${connector_name##*/}
    connector_name=${connector_name#card*-}
    [ -n "$connector_name" ] || continue

    LABWC_DETECTED_OUTPUTS="${LABWC_DETECTED_OUTPUTS:+$LABWC_DETECTED_OUTPUTS }$connector_name"
    if desktop_is_internal_output "$connector_name"; then
      LABWC_DETECTED_INTERNAL_OUTPUTS="${LABWC_DETECTED_INTERNAL_OUTPUTS:+$LABWC_DETECTED_INTERNAL_OUTPUTS }$connector_name"
    else
      LABWC_DETECTED_EXTERNAL_OUTPUTS="${LABWC_DETECTED_EXTERNAL_OUTPUTS:+$LABWC_DETECTED_EXTERNAL_OUTPUTS }$connector_name"
    fi
  done

  LABWC_DETECTED_PRIMARY_OUTPUT=
  for output_name in $LABWC_DETECTED_EXTERNAL_OUTPUTS; do
    LABWC_DETECTED_PRIMARY_OUTPUT=$output_name
    break
  done
  if [ -z "$LABWC_DETECTED_PRIMARY_OUTPUT" ]; then
    for output_name in $LABWC_DETECTED_INTERNAL_OUTPUTS; do
      LABWC_DETECTED_PRIMARY_OUTPUT=$output_name
      break
    done
  fi
}

desktop_resolve_greeter_user() {
  LABWC_GREETER_USER=
  for greeter_user in ${LABWC_GREETER_USER_CANDIDATES:-_greetd greeter greetd}; do
    [ -n "$greeter_user" ] || continue
    case "$greeter_user" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
        desktop_fatal "unsafe greeter user candidate: ${greeter_user}"
        ;;
    esac
    if grep -q "^${greeter_user}:" /target/etc/passwd 2>/dev/null; then
      LABWC_GREETER_USER=$greeter_user
      break
    fi
  done
  [ -n "$LABWC_GREETER_USER" ] || desktop_fatal "no target greetd greeter user found in candidates: ${LABWC_GREETER_USER_CANDIDATES:-_greetd greeter greetd}"
}

desktop_write_default_config() {
  defaults_path=${LABWC_DESKTOP_DEFAULTS_FILE:-/etc/default/labwc-desktop}
  install -d -m 0755 "$(dirname "/target${defaults_path}")"
  {
    printf '# Generated by the Debian preseed desktop role.\n'
    write_shell_config_var LABWC_DESKTOP_SESSION_NAME "${LABWC_DESKTOP_SESSION_NAME:-Labwc}"
    write_shell_config_var LABWC_DESKTOP_SESSION_COMMAND "${LABWC_DESKTOP_SESSION_COMMAND:-/usr/local/bin/labwc-session}"
    write_shell_config_var LABWC_WORKSPACE_COUNT "${LABWC_WORKSPACE_COUNT:-4}"
    write_shell_config_var LABWC_WALLPAPER_PATH "${LABWC_WALLPAPER_PATH:-/usr/share/backgrounds/labwc/wallpapers/wall-labwall2-1920x1080.png}"
    write_shell_config_var LABWC_LOCK_BACKGROUND_PATH "${LABWC_LOCK_BACKGROUND_PATH:-/usr/share/backgrounds/labwc/wallpapers/lock-labwall2-1920x1080.png}"
    write_shell_config_var LABWC_GREETER_BACKGROUND_PATH "${LABWC_GREETER_BACKGROUND_PATH:-/usr/share/backgrounds/labwc/wallpapers/regreet-labwall2-1920x1080.png}"
    write_shell_config_var LABWC_OUTPUT_POLICY "${LABWC_OUTPUT_POLICY:-external-only}"
    write_shell_config_var LABWC_OUTPUT_INTERNAL_PREFIXES "${LABWC_OUTPUT_INTERNAL_PREFIXES:-eDP LVDS DSI}"
    write_shell_config_var LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH "${LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH:-}"
    write_shell_config_var LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT "${LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT:-}"
    write_shell_config_var LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ "${LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ:-}"
    write_shell_config_var LABWC_OUTPUT_FALLBACK_REFRESH_HZ "${LABWC_OUTPUT_FALLBACK_REFRESH_HZ:-60}"
    write_shell_config_var LABWC_OUTPUT_SCALE "${LABWC_OUTPUT_SCALE:-1}"
    write_shell_config_var LABWC_OUTPUT_INTERNAL_SCALE "${LABWC_OUTPUT_INTERNAL_SCALE:-1}"
    write_shell_config_var LABWC_OUTPUT_EXTERNAL_SCALE "${LABWC_OUTPUT_EXTERNAL_SCALE:-1.80}"
    write_shell_config_var LABWC_OUTPUT_HOTPLUG_DEBOUNCE_SECONDS "${LABWC_OUTPUT_HOTPLUG_DEBOUNCE_SECONDS:-2}"
    write_shell_config_var LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS "${LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS:-1}"
    write_shell_config_var LABWC_DETECTED_OUTPUTS "${LABWC_DETECTED_OUTPUTS:-}"
    write_shell_config_var LABWC_DETECTED_INTERNAL_OUTPUTS "${LABWC_DETECTED_INTERNAL_OUTPUTS:-}"
    write_shell_config_var LABWC_DETECTED_EXTERNAL_OUTPUTS "${LABWC_DETECTED_EXTERNAL_OUTPUTS:-}"
    write_shell_config_var LABWC_DETECTED_PRIMARY_OUTPUT "${LABWC_DETECTED_PRIMARY_OUTPUT:-}"
    write_shell_config_var LABWC_GREETER_USER "${LABWC_GREETER_USER:-greeter}"
    write_shell_config_var LABWC_GREETER_VT "${LABWC_GREETER_VT:-1}"
    write_shell_config_var LABWC_GREETER_COMMAND "${LABWC_GREETER_COMMAND:-/usr/local/bin/labwc-greeter-session}"
    write_shell_config_var LABWC_TERMINAL_PRIMARY "${LABWC_TERMINAL_PRIMARY:-foot}"
    write_shell_config_var LABWC_TERMINAL_FALLBACK "${LABWC_TERMINAL_FALLBACK:-kitty}"
    write_shell_config_var LABWC_LAUNCHER_COMMAND "${LABWC_LAUNCHER_COMMAND:-labwc-wofi --show drun}"
    write_shell_config_var LABWC_MENU_COMMAND "${LABWC_MENU_COMMAND:-labwc-wofi --show drun}"
    write_shell_config_var LABWC_FILE_MANAGER_COMMAND "${LABWC_FILE_MANAGER_COMMAND:-thunar}"
    write_shell_config_var LABWC_AUDIO_CONTROL_COMMAND "${LABWC_AUDIO_CONTROL_COMMAND:-pavucontrol}"
    write_shell_config_var LABWC_DISPLAY_CONTROL_COMMAND "${LABWC_DISPLAY_CONTROL_COMMAND:-wdisplays}"
    write_shell_config_var LABWC_CALENDAR_COMMAND "${LABWC_CALENDAR_COMMAND:-labwc-calendar}"
    write_shell_config_var LABWC_BRIGHTNESS_CONTROL_COMMAND "${LABWC_BRIGHTNESS_CONTROL_COMMAND:-labwc-brightness-control}"
    write_shell_config_var LABWC_POWER_SETTINGS_COMMAND "${LABWC_POWER_SETTINGS_COMMAND:-labwc-power-settings}"
    write_shell_config_var LABWC_KEYBOARD_LAYOUTS "${LABWC_KEYBOARD_LAYOUTS:-us se}"
    write_shell_config_var LABWC_KEYBOARD_DEFAULT_LAYOUT "${LABWC_KEYBOARD_DEFAULT_LAYOUT:-us}"
    write_shell_config_var LABWC_ENABLE_WAYBAR "${LABWC_ENABLE_WAYBAR:-true}"
    write_shell_config_var LABWC_ENABLE_KANSHI "${LABWC_ENABLE_KANSHI:-true}"
    write_shell_config_var LABWC_ENABLE_MAKO "${LABWC_ENABLE_MAKO:-true}"
    write_shell_config_var LABWC_ENABLE_SWAYIDLE "${LABWC_ENABLE_SWAYIDLE:-true}"
    write_shell_config_var LABWC_ENABLE_SWAYBG "${LABWC_ENABLE_SWAYBG:-true}"
    write_shell_config_var LABWC_ENABLE_POLKIT_AGENT "${LABWC_ENABLE_POLKIT_AGENT:-true}"
    write_shell_config_var LABWC_ENABLE_XDG_DESKTOP_PORTAL "${LABWC_ENABLE_XDG_DESKTOP_PORTAL:-true}"
    write_shell_config_var LABWC_ENABLE_CRYSTAL_DOCK "${LABWC_ENABLE_CRYSTAL_DOCK:-true}"
    write_shell_config_var LABWC_IDLE_LOCK_SECONDS "${LABWC_IDLE_LOCK_SECONDS:-900}"
    write_shell_config_var LABWC_IDLE_DPMS_SECONDS "${LABWC_IDLE_DPMS_SECONDS:-1200}"
    write_shell_config_var LABWC_IDLE_SUSPEND_SECONDS "${LABWC_IDLE_SUSPEND_SECONDS:-0}"
    write_shell_config_var DEBIAN_SLICE_CPU_QUOTA "${DEBIAN_SLICE_CPU_QUOTA:-600%}"
    write_shell_config_var DEBIAN_SLICE_MEMORY_HIGH "${DEBIAN_SLICE_MEMORY_HIGH:-80%}"
    write_shell_config_var LABWC_WAYBAR_START_DELAY_SECONDS "${LABWC_WAYBAR_START_DELAY_SECONDS:-0}"
    write_shell_config_var LABWC_CRYSTAL_DOCK_COMMAND "${LABWC_CRYSTAL_DOCK_COMMAND:-crystal-dock}"
    write_shell_config_var LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS "${LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS:-1}"
    write_shell_config_var LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS "${LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS:-4}"
    write_shell_config_var LABWC_CURSOR_THEME "${LABWC_CURSOR_THEME:-Adwaita}"
    write_shell_config_var LABWC_CURSOR_SIZE "${LABWC_CURSOR_SIZE:-24}"
    write_shell_config_var LABWC_GTK_THEME "${LABWC_GTK_THEME:-Adwaita}"
    write_shell_config_var LABWC_GDK_BACKEND "${LABWC_GDK_BACKEND:-wayland}"
    write_shell_config_var LABWC_QT_QPA_PLATFORM "${LABWC_QT_QPA_PLATFORM:-wayland}"
    write_shell_config_var LABWC_SDL_VIDEODRIVER "${LABWC_SDL_VIDEODRIVER:-wayland}"
    write_shell_config_var LABWC_CLUTTER_BACKEND "${LABWC_CLUTTER_BACKEND:-wayland}"
    write_shell_config_var LABWC_ICON_THEME "${LABWC_ICON_THEME:-Papirus-Dark}"
    write_shell_config_var LABWC_QT_PLATFORMTHEME "${LABWC_QT_PLATFORMTHEME:-qt6ct}"
    write_shell_config_var LABWC_QT_STYLE_OVERRIDE "${LABWC_QT_STYLE_OVERRIDE:-adwaita-dark}"
  } >"/target${defaults_path}"
  chmod 0644 "/target${defaults_path}"
}
