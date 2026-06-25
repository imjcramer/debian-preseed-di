#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/desktop-verify-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=48
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

make_stub() {
  stub_name=$1
  stub_path="$2/$stub_name"
  mkdir -p "$(dirname "$stub_path")"
  cat >"$stub_path" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 0755 "$stub_path"
}

run_verify_required() {
  mock_path=$1
  (
    set -eu
    run_in_target() {
      label=$1
      shift
      PATH="$mock_path" "$@"
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"
    desktop_verify_required_commands
  )
}

run_verify_inline_syntax() {
  (
    set -eu
    run_in_target() {
      label=$1
      shift
      [ "$#" -ge 3 ] || {
        printf 'fatal: %s did not pass a /bin/sh -c payload\n' "$label" >&2
        exit 1
      }
      [ "$1" = /bin/sh ] && [ "$2" = -c ] || {
        printf 'fatal: %s used unexpected target shell invocation: %s %s\n' "$label" "$1" "$2" >&2
        exit 1
      }
      if ! /bin/sh -n -c "$3"; then
        printf 'fatal: %s generated invalid /bin/sh -c payload\n' "$label" >&2
        exit 1
      fi
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"
    desktop_verify_required_commands
    desktop_verify_staged_files
    desktop_verify_optional_staged_files
    ACCOUNT_USERNAME=user ACCOUNT_HOME=/home/user desktop_verify_primary_user_files
    LABWC_GREETER_USER=greeter desktop_verify_greeter_access
    desktop_verify_primary_user_slice_limits
  )
}

run_calendar_token_preflight() {
  test_cmdline=$1
  fatal_message_path=$2
  (
    set -eu
    INSTALLER_CMDLINE=$test_cmdline
    installer_cmdline() {
      printf '%s\n' "$INSTALLER_CMDLINE"
    }
    installer_fatal() {
      printf '%s\n' "$*" >"$fatal_message_path"
      exit 1
    }
    desktop_log() {
      :
    }
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/debian/scripts/desktop/components.sh"
    desktop_preflight_required_cmdline_tokens
    [ "$DESKTOP_FRUUX_USERNAME" = "alice" ]
    [ "$DESKTOP_FRUUX_PASSWORD" = "secret-token" ]
  )
}

run_autostart_waybar_case() {
  pgrep_running=$1
  capture_path=$2
  case_dir="$TMP_DIR/autostart-waybar-${pgrep_running}"
  bin_dir="$case_dir/bin"
  home_dir="$case_dir/home"

  mkdir -p "$bin_dir" "$home_dir/.config/waybar"
  : >"$home_dir/.config/waybar/config"
  : >"$home_dir/.config/waybar/style.css"
  : >"$capture_path"

  cat >"$bin_dir/pgrep" <<'EOF'
#!/bin/sh
case "${PGREP_RUNNING:-false}" in
  true) exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod 0755 "$bin_dir/pgrep"

  cat >"$bin_dir/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 0755 "$bin_dir/systemctl"

  cat >"$bin_dir/waybar" <<'EOF'
#!/bin/sh
printf 'waybar-started\n' >>"$WAYBAR_CAPTURE"
exit 0
EOF
  chmod 0755 "$bin_dir/waybar"

  PATH="$bin_dir:/usr/bin:/bin" \
    HOME="$home_dir" \
    PGREP_RUNNING="$pgrep_running" \
    WAYBAR_CAPTURE="$capture_path" \
    LABWC_ENABLE_SWAYBG=false \
    LABWC_ENABLE_KANSHI=false \
    LABWC_ENABLE_MAKO=false \
    LABWC_ENABLE_POLKIT_AGENT=false \
    LABWC_ENABLE_CRYSTAL_DOCK=false \
    LABWC_ENABLE_SWAYIDLE=false \
    LABWC_ENABLE_WAYBAR=true \
    LABWC_WAYBAR_START_DELAY_SECONDS=0 \
    /bin/sh "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
}

printf '1..%s\n' "$TEST_COUNT"

required_desktop_commands='
labwc
cage
gtkgreet
labwc-greeter-session
labwc-session
labwc-autostart
labwc-admin-action
labwc-calendar
labwc-logout
labwc-wofi
labwc-run
labwc-terminal
labwc-brightness-control
labwc-power-settings
labwc-power-menu
labwc-output-refresh
labwc-output-watch
labwc-keyboard-layout
systemctl
dbus-update-activation-environment
khal
todoman
vdirsyncer
'

core_path="$TMP_DIR/core-bin"
for cmd in $required_desktop_commands; do
  make_stub "$cmd" "$core_path"
done

if run_verify_required "$core_path"; then
  pass "optional desktop commands do not fail target verification"
else
  fail "optional desktop commands do not fail target verification"
fi

missing_required_path="$TMP_DIR/missing-required-bin"
for cmd in $required_desktop_commands; do
  [ "$cmd" != labwc ] || continue
  make_stub "$cmd" "$missing_required_path"
done

if run_verify_required "$missing_required_path"; then
  fail "required desktop commands still fail target verification when absent"
else
  pass "required desktop commands still fail target verification when absent"
fi

if run_verify_inline_syntax; then
  pass "desktop in-target verification snippets are POSIX sh syntax-valid"
else
  fail "desktop in-target verification snippets are POSIX sh syntax-valid"
fi

desktop_packages_file="$ROOT_DIR/d-i/debian/classes/class-select/role/desktop.cfg"
if grep -Eq '(^|[[:space:]])gvfs-backends([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wsdd(/forky)?([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs the GVFS network backends and wsdd helper"
else
  fail "desktop package set installs the GVFS network backends and wsdd helper"
fi

apt_fragment_file="$ROOT_DIR/d-i/debian/fragments/apt.cfg"
if ! grep -Eq '(^|[[:space:]])xwayland([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])xkbcomp([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])x11-xkb-utils([[:space:]]|$)' "$apt_fragment_file" &&
   grep -Eq '(^|[[:space:]])xwayland([[:space:]]|$)' "$apt_fragment_file" &&
   grep -q '^desktop_verify_no_x11_payload() {$' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'xkbcomp must not be installed' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"; then
  pass "desktop role strips explicit X11 payloads and verifies they stay absent"
else
  fail "desktop role strips explicit X11 payloads and verifies they stay absent"
fi

intel_cpu_class="$ROOT_DIR/d-i/debian/classes/class-auto/cpu/intel.cfg"
intel_regdom_rule="$ROOT_DIR/d-i/debian/hooks/hardware/cpu/intel/target/etc/udev/rules.d/85-wifi-regdom.rules"
if grep -Eq '(^|[[:space:]])iw([[:space:]]|$)' "$intel_cpu_class" &&
   grep -q '/usr/sbin/iw reg set AU' "$intel_regdom_rule"; then
  pass "Intel hardware policy installs iw and uses the canonical usr-sbin callout path"
else
  fail "Intel hardware policy installs iw and uses the canonical usr-sbin callout path"
fi

if grep -Eq '(^|[[:space:]])libspa-0\.2-libcamera([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])vdirsyncer([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])khal([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])todoman(/trixie)?([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])gsimplecal([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs the calendar sync stack without gsimplecal"
else
  fail "desktop package set installs the calendar sync stack without gsimplecal"
fi

base_packages_file="$ROOT_DIR/d-i/debian/fragments/apt.cfg"
if grep -Eq '(^|[[:space:]])dosfstools([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '(^|[[:space:]])tpm2-tools([[:space:]]|$)' "$base_packages_file" &&
   grep -Eq '(^|[[:space:]])tpm-udev([[:space:]]|$)' "$base_packages_file"; then
  pass "base package set installs VFAT fsck and TPM support"
else
  fail "base package set installs VFAT fsck and TPM support"
fi

if grep -Eq '(^|[[:space:]])libpam-wtmpdb([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])wtmpdb([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])power-profiles-daemon([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])hyprpolkitagent([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])libmtp-runtime([[:space:]]|$)' "$desktop_packages_file" &&
   grep -Eq '(^|[[:space:]])xdg-terminal-exec([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])polkit-kde-agent-1([[:space:]]|$)' "$desktop_packages_file" &&
   ! grep -Eq '(^|[[:space:]])xfce4-power-manager([[:space:]]|$)' "$desktop_packages_file"; then
  pass "desktop package set installs PAM, power profiles, Hypr polkit, MTP runtime, and terminal-default helpers"
else
  fail "desktop package set installs PAM, power profiles, Hypr polkit, MTP runtime, and terminal-default helpers"
fi

if grep -q '^LABWC_GREETER_COMMAND="/usr/local/bin/labwc-greeter-session"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_CALENDAR_COMMAND="labwc-calendar"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_KEYBOARD_LAYOUTS="us se"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_KEYBOARD_DEFAULT_LAYOUT="us"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_WAYBAR_START_DELAY_SECONDS="0"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env"; then
  pass "desktop defaults use the dedicated greeter, calendar, keyboard, and direct Waybar policy"
else
  fail "desktop defaults use the dedicated greeter, calendar, keyboard, and direct Waybar policy"
fi

fruux_fatal_message="$TMP_DIR/fruux-fatal.txt"
if run_calendar_token_preflight 'classes=lab,desktop,standard,dhcp fruux_username=alice fruux_password=secret-token' "$fruux_fatal_message"; then
  pass "desktop role preflights Fruux cmdline tokens in one cached pass"
else
  fail "desktop role preflights Fruux cmdline tokens in one cached pass"
fi

if run_calendar_token_preflight 'classes=lab,desktop,standard,dhcp fruux_password=secret-token' "$fruux_fatal_message"; then
  fail "desktop role fails clearly when Fruux username is missing"
else
  if grep -q 'Fruux username is required on the kernel cmdline: fruux_username=' "$fruux_fatal_message"; then
    pass "desktop role fails clearly when Fruux username is missing"
  else
    fail "desktop role fails clearly when Fruux username is missing"
  fi
fi

wofi_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-wofi"
wofi_config_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/wofi/config.tmpl"
power_menu="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-power-menu"
power_settings="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-power-settings"
brightness_menu="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-brightness-control"
run_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-run"
admin_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-admin-action"
logout_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-logout"
if grep -q '^LABWC_LAUNCHER_COMMAND="labwc-wofi --show drun"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_MENU_COMMAND="labwc-wofi --show drun"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q 'launcher_command=${LABWC_LAUNCHER_COMMAND:-labwc-wofi --show drun}' "$run_wrapper" &&
   grep -q 'labwc-wofi --dmenu --prompt power' "$power_menu" &&
   grep -q 'exec labwc-logout' "$power_menu" &&
   grep -q 'exec labwc-admin-action suspend' "$power_menu" &&
   grep -q 'exec labwc-admin-action reboot' "$power_menu" &&
   grep -q 'exec labwc-admin-action poweroff' "$power_menu" &&
   grep -q 'CPU power profile' "$power_settings" &&
   grep -q 'exec powerprofilesctl set' "$power_settings" &&
   grep -q 'labwc-wofi --dmenu --prompt "Brightness' "$brightness_menu" &&
   grep -q 'allow_images=true' "$wofi_config_template" &&
   grep -q '^image_size=__INSTALLER_LABWC_WOFI_IMAGE_SIZE__$' "$wofi_config_template" &&
   grep -q 'exec wofi "\$@"' "$wofi_wrapper" &&
   grep -q '^systemctl_cmd=$(command -v systemctl)$' "$admin_wrapper" &&
   grep -q 'if "$@"; then' "$admin_wrapper" &&
   grep -q 'run_session_shutdown_hook' "$admin_wrapper" &&
   ! grep -q '/bin/sh -lc' "$admin_wrapper" &&
   grep -q 'loginctl terminate-session' "$logout_wrapper"; then
  pass "Wofi helpers keep icons and the power actions use the explicit wrappers"
else
  fail "Wofi helpers keep icons and the power actions use the explicit wrappers"
fi

if grep -q '^wifi\.scan-rand-mac-address=no$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/NetworkManager/conf.d/80-preseed-wifi-client.conf"; then
  pass "NetworkManager Wi-Fi policy keeps scan MAC stable"
else
  fail "NetworkManager Wi-Fi policy keeps scan MAC stable"
fi

if grep -q 'pam_systemd\.so class=greeter type=wayland desktop=cage' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/pam.d/greetd-greeter"; then
  pass "greeter PAM uses the managed greeter session class"
else
  fail "greeter PAM uses the managed greeter session class"
fi

if grep -q 'pam_systemd\.so class=user type=wayland desktop=labwc' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/pam.d/greetd"; then
  pass "desktop PAM keeps the real session as a normal Labwc user session"
else
  fail "desktop PAM keeps the real session as a normal Labwc user session"
fi

greetd_dropin="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/systemd/system/greetd.service.d/20-labwc-vt.conf"
if grep -q '^Wants=seatd.service dbus.socket$' "$greetd_dropin" &&
   grep -q '^After=systemd-user-sessions.service systemd-logind.service seatd.service dbus.socket$' "$greetd_dropin"; then
  pass "greetd waits for seatd and the system bus socket"
else
  fail "greetd waits for seatd and the system bus socket"
fi

if grep -q '^d __INSTALLER_DIR_POLKIT_RUNTIME_RULES_D__ 0755 root root -$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/tmpfiles.d/70-polkit-runtime.conf" &&
   grep -q '^d __INSTALLER_DIR_POLKIT_LOCAL_RULES_D__ 0755 root root -$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/tmpfiles.d/70-polkit-runtime.conf"; then
  pass "polkit tmpfiles create optional rules directories"
else
  fail "polkit tmpfiles create optional rules directories"
fi

greeter_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-greeter-session"
if grep -q 'mktemp -d "\${greeter_runtime_parent}/labwc-greeter\.\${greeter_uid}\.XXXXXX"' "$greeter_wrapper" &&
   grep -q 'export XDG_CACHE_HOME=' "$greeter_wrapper" &&
   grep -q 'export XDG_STATE_HOME=' "$greeter_wrapper" &&
   grep -q 'export XDG_CONFIG_HOME=' "$greeter_wrapper" &&
   grep -q 'export GNUPGHOME=' "$greeter_wrapper" &&
   grep -q '^export GIO_USE_VFS=local$' "$greeter_wrapper" &&
   grep -q '^export GVFS_DISABLE_FUSE=1$' "$greeter_wrapper"; then
  pass "greeter wrapper uses temporary private runtime state without GVFS"
else
  fail "greeter wrapper uses temporary private runtime state without GVFS"
fi

if ! grep -q 'dbus-run-session' "$greeter_wrapper" &&
   grep -q 'export LIBSEAT_BACKEND=seatd' "$greeter_wrapper" &&
   grep -q '^exec /usr/bin/cage -s -m last -- /usr/bin/gtkgreet -s /etc/greetd/gtkgreet.css -c "$session_command"$' "$greeter_wrapper" &&
   ! grep -q '/usr/bin/gtkgreet -l' "$greeter_wrapper"; then
  pass "greeter wrapper uses seatd and Cage without private dbus-run-session"
else
  fail "greeter wrapper uses seatd and Cage without private dbus-run-session"
fi

session_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-session"
if ! grep -q 'dbus-run-session' "$session_wrapper" &&
   grep -q 'DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"' "$session_wrapper"; then
  pass "Labwc session uses the dbus-broker user bus address"
else
  fail "Labwc session uses the dbus-broker user bus address"
fi

autostart_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-autostart"
if ! grep -q 'import-environment' "$autostart_wrapper" &&
   ! grep -q 'dbus-update-activation-environment' "$autostart_wrapper" &&
   ! grep -q 'activation_environment_names=' "$autostart_wrapper" &&
   grep -q '^systemctl_cmd=$(command -v systemctl' "$autostart_wrapper" &&
   grep -q 'start_labwc_session_target()' "$autostart_wrapper" &&
   grep -q -- '--no-block start labwc-session.target' "$autostart_wrapper" &&
   grep -q 'waybar_running()' "$autostart_wrapper" &&
   grep -q '^current_uid=$(id -u)$' "$autostart_wrapper" &&
   grep -q 'pgrep -U "$current_uid" -x "$process_name"' "$autostart_wrapper" &&
   grep -q 'start_waybar' "$autostart_wrapper" &&
   grep -q 'polkit_agent_running()' "$autostart_wrapper" &&
   grep -q 'find_first_executable()' "$autostart_wrapper" &&
   grep -q '^HYPRPOLKITAGENT_PATH=$' "$autostart_wrapper" &&
   grep -q 'require_non_negative_integer LABWC_WAYBAR_START_DELAY_SECONDS' "$autostart_wrapper" &&
   grep -q 'hyprpolkitagent.service' "$autostart_wrapper" &&
   grep -q 'QT_NO_XDG_DESKTOP_PORTAL=1 "$HYPRPOLKITAGENT_PATH"' "$autostart_wrapper" &&
   grep -q '/usr/libexec/hyprpolkitagent' "$autostart_wrapper" &&
   ! grep -q 'polkit-kde-authentication-agent-1' "$autostart_wrapper"; then
  pass "Labwc autostart delegates activation environment updates to Labwc and starts session components once"
else
  fail "Labwc autostart delegates activation environment updates to Labwc and starts session components once"
fi

waybar_capture="$TMP_DIR/waybar-started.txt"
if run_autostart_waybar_case false "$waybar_capture" &&
   grep -q '^waybar-started$' "$waybar_capture"; then
  pass "Labwc autostart starts Waybar when no same-user Waybar is running"
else
  fail "Labwc autostart starts Waybar when no same-user Waybar is running"
fi

waybar_capture="$TMP_DIR/waybar-skipped.txt"
if run_autostart_waybar_case true "$waybar_capture" &&
   [ ! -s "$waybar_capture" ]; then
  pass "Labwc autostart skips Waybar when a same-user Waybar is already running"
else
  fail "Labwc autostart skips Waybar when a same-user Waybar is already running"
fi

desktop_verify="$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"
if grep -q 'Hypr polkit user service is missing' "$desktop_verify" &&
   grep -q 'Hypr polkit agent executable is missing' "$desktop_verify" &&
   grep -q 'hyprpolkitagent.service' "$desktop_verify" &&
   grep -q '/usr/libexec/hyprpolkitagent' "$desktop_verify"; then
  pass "desktop target verification requires the managed Hypr polkit service and executable"
else
  fail "desktop target verification requires the managed Hypr polkit service and executable"
fi

desktop_components="$ROOT_DIR/d-i/debian/scripts/desktop/components.sh"
if grep -q 'requested_groups="seat render video"' "$desktop_components" &&
   grep -q 'missing_groups=' "$desktop_components" &&
   grep -q 'usermod -a -G "\$missing_groups" "\$greeter_user"' "$desktop_components"; then
  pass "desktop role grants the greeter seat and DRM access groups without repeating usermod when already aligned"
else
  fail "desktop role grants the greeter seat and DRM access groups without repeating usermod when already aligned"
fi

slice_template="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/user-1000.slice.d/50-resource-limit.conf"
if grep -q '^CPUQuota=__INSTALLER_DEBIAN_SLICE_CPU_QUOTA__$' "$slice_template" &&
   ! grep -q '^CPUAccounting=' "$slice_template" &&
   grep -q '^MemoryHigh=__INSTALLER_DEBIAN_SLICE_MEMORY_HIGH__$' "$slice_template" &&
   grep -q '^TasksMax=12288$' "$slice_template"; then
  pass "desktop user slice template renders resource limits without removed CPUAccounting"
else
  fail "desktop user slice template renders resource limits without removed CPUAccounting"
fi

waybar_generator="$ROOT_DIR/d-i/debian/scripts/desktop/components.sh"
waybar_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
labwc_rc_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
calendar_vdir_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/vdirsyncer/config.tmpl"
calendar_khal_config="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/khal/config"
calendar_todoman_config="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/todoman/config.py"
calendar_personal_displayname="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.local/share/calendars/personal/displayname"
calendar_tasks_displayname="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.local/share/calendars/tasks/displayname"
calendar_wrapper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-calendar"
if grep -Fq 'install -d "$HOME/Pictures"; grim "$HOME/Pictures/Screenshot-$(date +%Y%m%d-%H%M%S).png"' "$labwc_rc_template" &&
   grep -Fq 'grim -g "$(slurp)" "$HOME/Pictures/Screenshot-$(date +%Y%m%d-%H%M%S).png"' "$labwc_rc_template" &&
   ! grep -q 'allWorkspaces' "$labwc_rc_template" &&
   grep -q '<action name="NextWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q '<action name="PreviousWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q 'deprecated windowSwitcher allWorkspaces' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q '^username = "__INSTALLER_FRUUX_USERNAME__"$' "$calendar_vdir_template" &&
   grep -q '^password = "__INSTALLER_FRUUX_PASSWORD__"$' "$calendar_vdir_template" &&
   [ "$(grep -c '^collections = null$' "$calendar_vdir_template")" -eq 2 ] &&
   grep -q '^default_calendar = personal$' "$calendar_khal_config" &&
   grep -q '^longdateformat = %Y-%m-%d$' "$calendar_khal_config" &&
   grep -q '^longdatetimeformat = %Y-%m-%d %H:%M$' "$calendar_khal_config" &&
   grep -q '^default_list = "Tasks"$' "$calendar_todoman_config" &&
   grep -q '^Calendar$' "$calendar_personal_displayname" &&
   grep -q '^Tasks$' "$calendar_tasks_displayname" &&
   grep -q 'vdirsyncer_state_root="${state_root}/vdirsyncer"' "$desktop_components" &&
   grep -q '"/target${vdirsyncer_state_root}"' "$desktop_components" &&
   ! grep -Fq 'cat >"$vdirsyncer_config"' "$desktop_components" &&
   ! grep -Fq 'cat >"$khal_config"' "$desktop_components" &&
   ! grep -Fq 'cat >"$todoman_config"' "$desktop_components"; then
  pass "Desktop target config bodies live in staged templates and files rather than inline calendar heredocs"
else
  fail "Desktop target config bodies live in staged templates and files rather than inline calendar heredocs"
fi

if ! grep -q 'allWorkspaces' "$labwc_rc_template" &&
   ! grep -q '<windowSwitcher allWorkspaces' "$labwc_rc_template" &&
   grep -q '<action name="NextWindow" workspace="all" />' "$labwc_rc_template" &&
   grep -q '<action name="PreviousWindow" workspace="all" />' "$labwc_rc_template"; then
  pass "Labwc config avoids deprecated windowSwitcher allWorkspaces"
else
  fail "Labwc config avoids deprecated windowSwitcher allWorkspaces"
fi

if grep -q 'require_command todoman' "$calendar_wrapper" &&
   grep -q 'vdirsyncer discover "$calendar_pair"' "$calendar_wrapper" &&
   grep -q 'todoman list' "$calendar_wrapper" &&
   grep -q 'exec labwc-terminal -e todoman new -i' "$calendar_wrapper" &&
   grep -q 'exec todoman edit -i "\$task_id"' "$calendar_wrapper" &&
   ! grep -q '/bin/sh -lc' "$calendar_wrapper"; then
  pass "calendar wrapper uses installed tools and discovers vdirsyncer pairs before first sync"
else
  fail "calendar wrapper uses installed tools and discovers vdirsyncer pairs before first sync"
fi

wsdd_defaults_template="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/wsdd-server/defaults.tmpl"
if grep -q '^WSDD_PARAMS="__INSTALLER_WSDD_PARAMS__"$' "$wsdd_defaults_template" &&
   grep -q 'desktop_target_preseed_network_default_value PRESEED_NETWORK_ETHERNET_IFACE' "$desktop_components" &&
   grep -q 'desktop_target_preseed_network_default_value PRESEED_NETWORK_WIFI_IFACE' "$desktop_components" &&
   grep -q 'desktop_render_shared_target_template "etc/wsdd-server/defaults.tmpl" "/etc/wsdd-server/defaults" 0644' "$desktop_components" &&
   grep -q '/etc/wsdd-server/defaults' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"; then
  pass "desktop role renders wsdd defaults from the selected preseed network interfaces"
else
  fail "desktop role renders wsdd defaults from the selected preseed network interfaces"
fi

keyboard_helper="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-keyboard-layout"
if grep -q '"modules-center": \["clock"\]' "$waybar_template" &&
   grep -q '"modules-left": \["custom/launcher", "custom/dgpu", "ext/workspaces", "custom/files", "custom/terminal", "wlr/taskbar"\]' "$waybar_template" &&
   grep -q '"modules-right": \["custom/keyboard", "network", "pulseaudio"' "$waybar_template" &&
   grep -q '"exec": "labwc-keyboard-layout status"' "$waybar_template" &&
   grep -q '"on-click": "labwc-keyboard-layout toggle && pkill -RTMIN+7 waybar"' "$waybar_template" &&
   grep -q 'XKB_DEFAULT_LAYOUT=%s' "$keyboard_helper" &&
   grep -q '🇸🇪' "$keyboard_helper" &&
   grep -q '🇺🇸' "$keyboard_helper" &&
   grep -q '"sort-by-name": true' "$waybar_template" &&
   grep -q '"on-click": "activate"' "$waybar_template"; then
  pass "Waybar template keeps the clock centered and adds the keyboard toggle before network"
else
  fail "Waybar template keeps the clock centered and adds the keyboard toggle before network"
fi

if grep -q '"format-ethernet": "🖧 LAN"' "$waybar_template" &&
   grep -q '"format": "🔊 {volume}%"' "$waybar_template" &&
   grep -q '"format": "🖴 {percentage_used}%"' "$waybar_template" &&
   grep -q '"height": __INSTALLER_LABWC_WAYBAR_HEIGHT__' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_TASKBAR_ICON_SIZE__' "$waybar_template" &&
   grep -q '"icon-size": __INSTALLER_LABWC_WAYBAR_TRAY_ICON_SIZE__' "$waybar_template" &&
   grep -q '"spacing": 4' "$waybar_template" &&
   grep -q 'LABWC_WAYBAR_HEIGHT "${LABWC_WAYBAR_HEIGHT:-46}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TASKBAR_ICON_SIZE "${LABWC_WAYBAR_TASKBAR_ICON_SIZE:-20}"' "$waybar_generator" &&
   grep -q 'LABWC_WAYBAR_TRAY_ICON_SIZE "${LABWC_WAYBAR_TRAY_ICON_SIZE:-18}"' "$waybar_generator" &&
   grep -q '"on-click": "labwc-terminal -e btop"' "$waybar_template" &&
   grep -q '"on-click": "labwc-terminal -e ncdu /"' "$waybar_template" &&
   grep -q '"on-click": "labwc-terminal -e nmtui"' "$waybar_template" &&
   grep -q '"on-click-right": "labwc-calendar menu"' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_BRIGHTNESS_CONTROL_COMMAND__"' "$waybar_template" &&
   grep -q '"on-click": "__INSTALLER_LABWC_POWER_SETTINGS_COMMAND__"' "$waybar_template"; then
  pass "Waybar template wires the requested click actions and the larger panel sizing"
else
  fail "Waybar template wires the requested click actions and the larger panel sizing"
fi

waybar_style_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/waybar/style.css.tmpl"
if grep -q '#custom-keyboard' "$waybar_style_template" &&
   grep -q '#custom-dgpu' "$waybar_style_template" &&
   grep -q 'font-size: __INSTALLER_LABWC_WAYBAR_FONT_SIZE__px;' "$waybar_style_template" &&
   grep -q 'background-image: url("icons/nvidia.svg");' "$waybar_style_template" &&
   grep -q 'background-size: 9px 9px;' "$waybar_style_template" &&
   grep -q 'min-width: 56px;' "$waybar_style_template" &&
   grep -q 'margin-left: 1px;' "$waybar_style_template" &&
   grep -q 'background: rgba(248, 113, 113, 0.16);' "$waybar_style_template" &&
   grep -q '#custom-power:hover' "$waybar_style_template" &&
   grep -q '^LABWC_WAYBAR_FONT_SIZE="15"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q 'waybar/style.css.tmpl' "$waybar_generator"; then
  pass "Waybar styling stays compact and policy-driven through the managed template"
else
  fail "Waybar styling stays compact and policy-driven through the managed template"
fi

if grep -q 'monitor.bluez-midi = disabled' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf" &&
   ! grep -q 'monitor.libcamera = disabled' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf"; then
  pass "WirePlumber keeps BlueZ MIDI disabled without disabling libcamera"
else
  fail "WirePlumber keeps BlueZ MIDI disabled without disabling libcamera"
fi

if grep -q '^\[colors-dark\]$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini" &&
   ! grep -q '^\[colors\]$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/foot/foot.ini"; then
  pass "Foot config uses the current colors-dark section"
else
  fail "Foot config uses the current colors-dark section"
fi

dgpu_launcher="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-dgpu-launcher"
chromium_flags="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/chromium.d/90-preseed-performance-flags.tmpl"
if grep -q 'launch_argv = \["switcherooctl", "launch", "--"\]' "$dgpu_launcher" &&
   grep -q 'drun-print_desktop_file=true' "$dgpu_launcher" &&
   grep -q 'resolve_selection' "$dgpu_launcher" &&
   grep -q 'expand_exec_tokens' "$dgpu_launcher" &&
   grep -q 'desktop entry has no Exec command' "$dgpu_launcher" &&
   grep -q 'env\["__NV_PRIME_RENDER_OFFLOAD"\] = "1"' "$dgpu_launcher" &&
   grep -q 'env\["__GLX_VENDOR_LIBRARY_NAME"\] = "nvidia"' "$dgpu_launcher" &&
   grep -q '^CHROMIUM_FLAGS=.*--ozone-platform-hint=auto' "$chromium_flags" &&
   grep -q 'AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxZeroCopyGL' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*VaapiOnNvidiaGPUs' "$chromium_flags" &&
   grep -q '^width=__INSTALLER_LABWC_WOFI_WIDTH__$' "$wofi_config_template" &&
   grep -q '^height=__INSTALLER_LABWC_WOFI_HEIGHT__$' "$wofi_config_template" &&
   grep -q '^lines=12$' "$wofi_config_template" &&
   grep -q '^image_size=__INSTALLER_LABWC_WOFI_IMAGE_SIZE__$' "$wofi_config_template" &&
   grep -q 'etc/skel/.config/wofi/config.tmpl' "$desktop_components" &&
   grep -q 'etc/skel/.config/wofi/style.css.tmpl' "$desktop_components" &&
   grep -q '^LABWC_WOFI_WIDTH="720"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_WOFI_HEIGHT="580"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env" &&
   grep -q '^LABWC_WOFI_IMAGE_SIZE="22"$' "$ROOT_DIR/d-i/debian/hosts/shared/desktop.env"; then
  pass "dGPU launcher, Chromium flags, and policy-driven Wofi defaults are staged coherently"
else
  fail "dGPU launcher, Chromium flags, and policy-driven Wofi defaults are staged coherently"
fi

gtk3_settings_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/gtk-3.0/settings.ini.tmpl"
gtk4_settings_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/gtk-4.0/settings.ini.tmpl"
wlr_labwc_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
wofi_style_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/wofi/style.css.tmpl"
shared_desktop_env="$ROOT_DIR/d-i/debian/hosts/shared/desktop.env"
if grep -q '^gtk-font-name=Noto Sans __INSTALLER_LABWC_GTK_FONT_SIZE__$' "$gtk3_settings_template" &&
   grep -q '^gtk-font-name=Noto Sans __INSTALLER_LABWC_GTK_FONT_SIZE__$' "$gtk4_settings_template" &&
   grep -q '__INSTALLER_LABWC_FONT_WINDOW_SIZE__' "$wlr_labwc_template" &&
   grep -q '__INSTALLER_LABWC_FONT_MENU_SIZE__' "$wlr_labwc_template" &&
   grep -q '__INSTALLER_LABWC_FONT_OSD_SIZE__' "$wlr_labwc_template" &&
   grep -q '^LABWC_FONT_WINDOW_SIZE="12"$' "$shared_desktop_env" &&
   grep -q '^LABWC_FONT_MENU_SIZE="13"$' "$shared_desktop_env" &&
   grep -q '^LABWC_FONT_OSD_SIZE="13"$' "$shared_desktop_env" &&
   grep -q '^LABWC_GTK_FONT_SIZE="12"$' "$shared_desktop_env" &&
   grep -q '^LABWC_WOFI_FONT_SIZE="15"$' "$shared_desktop_env" &&
   grep -q '^  font-size: __INSTALLER_LABWC_WOFI_FONT_SIZE__px;$' "$wofi_style_template"; then
  pass "GTK, Labwc, and Wofi text defaults are policy-driven without scaling"
else
  fail "GTK, Labwc, and Wofi text defaults are policy-driven without scaling"
fi

profile_file="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.profile"
bash_profile_file="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.bash_profile"
bashrc_file="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.bashrc"
zprofile_file="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.zprofile"
zshrc_file="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.zshrc"
if ! grep -q '^alias ' "$profile_file" &&
   sh -n "$profile_file" &&
   bash -n "$bash_profile_file" &&
   bash -n "$bashrc_file" &&
   ! grep -q '\. "\$HOME/\.bashrc"' "$profile_file" &&
   ! grep -q '\. "\$HOME/\.zshrc"' "$profile_file" &&
   grep -q '\. "\$HOME/\.profile"' "$bash_profile_file" &&
   grep -q '\. "\$HOME/\.bashrc"' "$bash_profile_file" &&
   grep -q '\. "\$HOME/\.profile"' "$bashrc_file" &&
   ! grep -q 'luks-mok-' "$bashrc_file" &&
   grep -q 'starship init bash' "$bashrc_file" &&
   grep -q '\. "\$HOME/\.profile"' "$zprofile_file" &&
   grep -q '\. "\$HOME/\.profile"' "$zshrc_file" &&
   ! grep -q 'luks-mok-' "$zshrc_file" &&
   grep -q 'starship init zsh' "$zshrc_file"; then
  pass "desktop shell dotfiles keep shared login env in .profile, stay syntax-valid, and avoid managed MOK aliases"
else
  fail "desktop shell dotfiles keep shared login env in .profile, stay syntax-valid, and avoid managed MOK aliases"
fi

if grep -q '^TerminalEmulator=foot$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/xfce4/helpers.rc" &&
   grep -q '^foot.desktop$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/xdg-terminals.list" &&
   grep -q '^X-XFCE-Category=TerminalEmulator$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/share/xfce4/helpers/foot.desktop"; then
  pass "Foot is registered as the XFCE and xdg terminal default"
else
  fail "Foot is registered as the XFCE and xdg terminal default"
fi

thunar_uca="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/Thunar/uca.xml"
labwc_menu="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
if grep -q '\.config/Thunar' "$desktop_components" &&
   grep -q '<icon>__INSTALLER_LABWC_ICON_THEME__</icon>' "$labwc_rc_template" &&
   grep -q '<showIcons>yes</showIcons>' "$labwc_rc_template" &&
   grep -q '/etc/skel/.config/Thunar/uca.xml' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'label="Terminal" icon="utilities-terminal"' "$labwc_menu" &&
   grep -q 'label="Applications" icon="applications-system"' "$labwc_menu" &&
   grep -q 'label="Files" icon="system-file-manager"' "$labwc_menu" &&
   grep -q 'label="Text Editor" icon="org.xfce.mousepad"' "$labwc_menu" &&
   grep -q 'label="PDF Viewer" icon="org.pwmt.zathura"' "$labwc_menu" &&
   grep -q 'label="System Monitor" icon="utilities-system-monitor"' "$labwc_menu" &&
   grep -q 'label="Audio" icon="multimedia-volume-control"' "$labwc_menu" &&
   grep -q 'label="Appearance" icon="preferences-desktop-theme"' "$labwc_menu" &&
   grep -q 'label="Calendar" icon="office-calendar"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar"' "$labwc_menu" &&
   grep -q 'label="Tasks" icon="view-calendar-tasks"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar tasks"' "$labwc_menu" &&
   grep -q 'label="Calendar Actions" icon="view-calendar-day"' "$labwc_menu" &&
   grep -q 'command="labwc-calendar menu"' "$labwc_menu" &&
   grep -q 'label="Refresh Outputs" icon="view-refresh"' "$labwc_menu" &&
   grep -q 'label="Restart Dock" icon="view-refresh"' "$labwc_menu" &&
   grep -q 'label="Lock" icon="system-lock-screen"' "$labwc_menu" &&
   grep -q 'label="Power" icon="system-shutdown"' "$labwc_menu" &&
   grep -q 'label="Reconfigure" icon="preferences-system"' "$labwc_menu" &&
   grep -q 'label="Close Window" icon="window-close"' "$labwc_menu" &&
   grep -q 'label="Logout" icon="system-log-out"' "$labwc_menu" &&
   grep -q 'command="labwc-logout"' "$labwc_menu" &&
   grep -q '<icon>utilities-terminal</icon>' "$thunar_uca" &&
   grep -q '<icon>package-x-generic</icon>' "$thunar_uca"; then
  pass "Labwc and Thunar context menus are staged with explicit icon coverage"
else
  fail "Labwc and Thunar context menus are staged with explicit icon coverage"
fi

portal_conf="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/xdg/xdg-desktop-portal/labwc-portals.conf"
shutdown_hook="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/labwc/shutdown"
labwc_user_target="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/systemd/user/labwc-session.target"
portal_dropin="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/systemd/user/xdg-desktop-portal.service.d/10-labwc-session.conf"
hypr_dropin="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf"
if grep -q '^org.freedesktop.impl.portal.ScreenCast=wlr$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Screenshot=wlr$' "$portal_conf" &&
   grep -q '^default=none$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.RemoteDesktop=wlr$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.FileChooser=lxqt$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Secret=kwallet$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Notification=gtk$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.Settings=xapp$' "$portal_conf" &&
   grep -q '^org.freedesktop.impl.portal.DynamicLauncher=gtk$' "$portal_conf" &&
   grep -q 'desktop_stage_user_unit_environment_dropin' "$desktop_components" &&
   grep -q 'desktop_stage_portal_wayland_conditions' "$desktop_components" &&
   grep -q 'desktop_stage_labwc_user_session_assets' "$desktop_components" &&
   grep -q 'ConditionEnvironment=WAYLAND_DISPLAY' "$desktop_components" &&
   grep -q 'PartOf=graphical-session.target labwc-session.target' "$desktop_components" &&
   grep -q 'ExecCondition=/usr/bin/systemctl --user --quiet is-active graphical-session.target' "$desktop_components" &&
   grep -q 'verify_account_session_dropin hyprpolkitagent.service' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'xdg-desktop-portal-lxqt.service' "$desktop_components" &&
   grep -q 'Exec=/usr/bin/env QT_NO_XDG_DESKTOP_PORTAL=1 /usr/bin/ksecretd' "$desktop_components" &&
   grep -q '^BindsTo=graphical-session.target$' "$labwc_user_target" &&
   grep -q '^PartOf=graphical-session.target labwc-session.target$' "$portal_dropin" &&
   grep -q '^ExecCondition=/usr/bin/systemctl --user --quiet is-active graphical-session.target$' "$portal_dropin" &&
   grep -q '^PartOf=graphical-session.target labwc-session.target$' "$hypr_dropin" &&
   grep -q '^Environment=QT_NO_XDG_DESKTOP_PORTAL=1$' "$hypr_dropin" &&
   grep -q 'KWallet portal backend D-Bus override is missing' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'KWallet portal backend must not leave a duplicate local D-Bus service' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'xdg-desktop-portal-lxqt.service' "$shutdown_hook" &&
   grep -q 'xdg-desktop-portal-xapp.service' "$shutdown_hook" &&
   grep -q 'hyprpolkitagent.service' "$shutdown_hook" &&
   grep -q 'ksecretd' "$shutdown_hook" &&
   grep -q 'unmount_gvfs_fuse' "$shutdown_hook" &&
   ! grep -q 'gvfs-daemon.service' "$shutdown_hook" &&
   ! grep -q 'desktop_enable_unit_if_available xdg-desktop-portal.service user' "$desktop_components" &&
   ! grep -q 'desktop_enable_unit_if_available xdg-desktop-portal-gtk.service user' "$desktop_components"; then
  pass "Labwc portal preferences preserve WLR, LXQt, XApp, KWallet, and Hypr agent isolation"
else
  fail "Labwc portal preferences preserve WLR, LXQt, XApp, KWallet, and Hypr agent isolation"
fi

if grep -q 'xdg-desktop-portal.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-gtk.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-wlr.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-lxqt.service' "$desktop_components" &&
   grep -q 'xdg-desktop-portal-xapp.service' "$desktop_components" &&
   grep -q 'verify_session_dropin "$portal_unit"' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh" &&
   grep -q 'portal user unit must wait for Labwc session readiness' "$ROOT_DIR/d-i/debian/scripts/desktop/verify.sh"; then
  pass "portal user units are gated on Labwc session readiness"
else
  fail "portal user units are gated on Labwc session readiness"
fi

if grep -q '^ConfigurationDirectoryMode=0755$' "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/systemd/system/bluetooth.service.d/10-preseed-directory-mode.conf"; then
  pass "bluetooth drop-in matches the managed configuration directory mode"
else
  fail "bluetooth drop-in matches the managed configuration directory mode"
fi

bluetooth_main="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/bluetooth/main.conf"
if grep -q '^AutoEnable=false$' "$bluetooth_main" &&
   grep -q '^KernelExperimental = false$' "$bluetooth_main" &&
   grep -q 'desktop_enable_unit_if_available bluetooth.service system' "$desktop_components" &&
   ! grep -q 'desktop_stage_bluetooth_dbus_activation' "$desktop_components" &&
   ! grep -q 'unstage_target_systemd_unit_enabled bluetooth.service system' "$desktop_components"; then
  pass "Bluetooth service is available without eager controller power-on"
else
  fail "Bluetooth service is available without eager controller power-on"
fi

output_refresh="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-output-refresh"
if head -n 1 "$output_refresh" | grep -q '^#!/usr/bin/env perl$'; then
  pass "labwc output refresh helper is implemented in Perl"
else
  fail "labwc output refresh helper is implemented in Perl"
fi

terminal_capture_dir="$TMP_DIR/terminal-capture"
mkdir -p "$terminal_capture_dir"
cat >"$terminal_capture_dir/kitty" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$TERMINAL_CAPTURE_FILE"
exit 0
EOF
chmod 0755 "$terminal_capture_dir/kitty"
terminal_capture_file="$TMP_DIR/terminal-args.txt"
if TERMINAL_CAPTURE_FILE="$terminal_capture_file" \
   PATH="$terminal_capture_dir:/usr/bin:/bin" \
   LABWC_TERMINAL_PRIMARY="kitty" \
   LABWC_TERMINAL_FALLBACK="kitty" \
   /bin/sh "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-terminal" -e btop &&
   [ "$(cat "$terminal_capture_file")" = "btop" ]; then
  pass "labwc-terminal normalizes xterm-style execute flags for kitty"
else
  fail "labwc-terminal normalizes xterm-style execute flags for kitty"
fi

cat >"$terminal_capture_dir/x-terminal-emulator" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$TERMINAL_CAPTURE_FILE"
exit 0
EOF
chmod 0755 "$terminal_capture_dir/x-terminal-emulator"
if TERMINAL_CAPTURE_FILE="$terminal_capture_file" \
   PATH="$terminal_capture_dir:/usr/bin:/bin" \
   LABWC_TERMINAL_PRIMARY="x-terminal-emulator" \
   LABWC_TERMINAL_FALLBACK="x-terminal-emulator" \
   /bin/sh "$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-terminal" -e btop &&
   [ "$(cat "$terminal_capture_file")" = "-e
btop" ]; then
  pass "labwc-terminal preserves xterm-style execute flags for xterm-like fallbacks"
else
  fail "labwc-terminal preserves xterm-style execute flags for xterm-like fallbacks"
fi

[ "$FAIL_COUNT" -eq 0 ]
