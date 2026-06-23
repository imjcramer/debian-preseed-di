#!/bin/sh
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

FIRSTBOOT_LOG_DIR=${FIRSTBOOT_LOG_DIR:-/var/lib/preseed/logs/firstboot}
FIRSTBOOT_DATA_DIR=${FIRSTBOOT_DATA_DIR:-${FIRSTBOOT_LOG_DIR}/data}
FIRSTBOOT_LOG_FILE=${FIRSTBOOT_LOG_FILE:-${FIRSTBOOT_LOG_DIR}/20-firstboot.log}
VALIDATION_FILE=${FIRSTBOOT_DATA_DIR}/validation-results.txt

mkdir -p "$FIRSTBOOT_LOG_DIR" "$FIRSTBOOT_DATA_DIR" 2>/dev/null || exit 0
: >>"$FIRSTBOOT_LOG_FILE" 2>/dev/null || exit 0
: >"$VALIDATION_FILE" 2>/dev/null || exit 0
chmod 0600 "$VALIDATION_FILE" 2>/dev/null || true

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s\n' unknown-time
}

log_line() {
  stage=$1
  level=$2
  component=$3
  shift 3
  printf '%s stage=%s level=%s component=%s %s\n' \
    "$(timestamp)" "$stage" "$level" "$component" "$*" >>"$FIRSTBOOT_LOG_FILE"
}

if [ -r /usr/local/lib/firstboot.d/logging.sh ]; then
  # shellcheck disable=SC1091
  . /usr/local/lib/firstboot.d/logging.sh
fi

record() {
  printf '%s\n' "$*" >>"$VALIDATION_FILE"
}

capture() {
  output_name=$1
  shift
  output_file="${FIRSTBOOT_DATA_DIR}/${output_name}"
  {
    printf '# command:'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
    "$@"
  } >"$output_file" 2>&1 || printf 'status=%s\n' "$?" >>"$output_file"
  chmod 0600 "$output_file" 2>/dev/null || true
}

failures=0

check_path() {
  label=$1
  path=$2
  if [ -e "$path" ]; then
    record "PASS ${label}: ${path}"
  else
    record "FAIL ${label}: missing ${path}"
    log_line validation error "$label" "missing=${path}"
    failures=$((failures + 1))
  fi
}

check_command() {
  label=$1
  shift
  if "$@" >>"$VALIDATION_FILE" 2>&1; then
    record "PASS ${label}"
  else
    status=$?
    record "FAIL ${label}: status=${status}"
    log_line validation error "$label" "status=${status}"
    failures=$((failures + 1))
  fi
}

bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

check_desktop_command_required() {
  command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    record "PASS desktop-command-${command_name}"
  else
    record "FAIL desktop-command-${command_name}: missing"
    log_line validation error desktop "missing_command=${command_name}"
    failures=$((failures + 1))
  fi
}

check_desktop_command_optional() {
  command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    record "PASS desktop-command-${command_name}"
  else
    record "WARN desktop-command-${command_name}: missing"
    log_line validation warn desktop "missing_optional_command=${command_name}"
  fi
}

validate_desktop_role() {
  if [ ! -r /etc/default/labwc-desktop ]; then
    log_line validation info desktop "desktop_role=not-selected"
    return 0
  fi

  record "desktop_role=selected"
  log_line validation info desktop "desktop_role=selected"
  for desktop_path in \
    /etc/default/labwc-desktop \
    /etc/environment.d/90-labwc-session.conf \
    /etc/pam.d/greetd \
    /etc/pam.d/greetd-greeter \
    /etc/greetd/config.toml \
    /etc/greetd/gtkgreet.css \
    /usr/share/wayland-sessions/labwc.desktop \
    /usr/local/bin/labwc-greeter-session \
    /usr/local/bin/labwc-session \
    /usr/local/bin/labwc-autostart \
    /usr/local/bin/labwc-admin-action \
    /usr/local/bin/labwc-calendar \
    /usr/local/bin/labwc-logout \
    /usr/local/bin/labwc-wofi \
    /usr/local/bin/labwc-terminal \
    /usr/local/bin/labwc-output-refresh \
    /usr/local/bin/labwc-output-watch \
    /usr/local/bin/labwc-run \
    /etc/skel/.profile \
    /etc/skel/.bash_profile \
    /etc/skel/.bashrc \
    /etc/skel/.zprofile \
    /etc/skel/.zshrc \
    /etc/skel/.config/labwc/rc.xml \
    /etc/skel/.config/labwc/menu.xml \
    /etc/skel/.config/systemd/user/labwc-session.target \
    /etc/skel/.config/mpv/mpv.conf \
    /etc/skel/.config/mpv/input.conf \
    /etc/systemd/user/labwc-calendar-sync.service \
    /etc/systemd/user/labwc-calendar-sync.timer \
    /etc/skel/.config/Thunar/uca.xml \
    /etc/skel/.config/user-dirs.dirs \
    /etc/xdg/gtk-3.0/settings.ini \
    /etc/xdg/gtk-4.0/settings.ini
  do
    check_path "desktop-path-${desktop_path}" "$desktop_path"
  done

  for desktop_command in \
    labwc \
    cage \
    gtkgreet \
    labwc-greeter-session \
    labwc-session \
    labwc-admin-action \
    labwc-calendar \
    labwc-logout \
    labwc-wofi \
	labwc-run \
	labwc-terminal \
	labwc-brightness-control \
	labwc-power-settings \
    labwc-power-menu \
	labwc-output-refresh \
    labwc-output-watch \
    dbus-update-activation-environment \
    khal \
    todoman \
    vdirsyncer
  do
    check_desktop_command_required "$desktop_command"
  done

  if grep -q "dbus-run-session" /usr/local/bin/labwc-greeter-session /usr/local/bin/labwc-session 2>/dev/null; then
    record "FAIL desktop-dbus-broker-wrappers: dbus-run-session present"
    log_line validation error desktop "dbus_run_session_present=true"
    failures=$((failures + 1))
  else
    record "PASS desktop-dbus-broker-wrappers"
  fi

  if grep -q "/usr/bin/cage -s -m last -- /usr/bin/gtkgreet -s /etc/greetd/gtkgreet.css" /usr/local/bin/labwc-greeter-session 2>/dev/null; then
    record "PASS desktop-greeter-cage-gtkgreet-command"
  else
    record "FAIL desktop-greeter-cage-gtkgreet-command"
    log_line validation error desktop "greeter_command_mismatch=true"
    failures=$((failures + 1))
  fi

  for desktop_command in \
    wofi \
    waybar \
    mako \
    makoctl \
    kanshi \
    thunar \
    nnn \
    mousepad \
    mpv \
    qimgv \
    zathura \
	    xarchiver \
	    nwg-look \
		    foot \
		    kitty \
		    brightnessctl \
		    powerprofilesctl \
		    xdg-terminal-exec \
		    crystal-dock
  do
    check_desktop_command_optional "$desktop_command"
  done

  if command -v systemctl >/dev/null 2>&1; then
    capture desktop-units.txt systemctl status greetd.service seatd.service NetworkManager.service pipewire.socket pipewire-pulse.socket wireplumber.service xdg-desktop-portal.service --no-pager --lines=40
    log_line validation info desktop "desktop_unit_status_collected=true"
  fi
}

record "timestamp=$(timestamp)"
record "hostname=$(hostname 2>/dev/null || printf unknown)"
record "kernel=$(uname -r 2>/dev/null || printf unknown)"

if bool_is_true "${INSTALLER_DEBUG_LOGS:-0}"; then
  check_path installer-logs /var/lib/preseed/logs/installer
  for required_log in \
    01-boot.log \
    02-preseed.log \
    03-network.log \
    04-disk.log \
    05-partman.log \
    06-apt.log \
    07-packages.log \
    08-bootloader.log \
    09-late.log \
    10-desktop.log
  do
    check_path "installer-log-${required_log}" "/var/lib/preseed/logs/installer/${required_log}"
  done
else
  record "SKIP installer-logs: debug class not selected"
  log_line validation info installer-logs "debug_class_selected=false"
fi

check_path initramfs-health-log-dir /var/lib/preseed/logs/initramfs
check_path initramfs-health-init-top-log /var/lib/preseed/logs/initramfs/01-init-top.log
check_path initramfs-health-init-bottom-log /var/lib/preseed/logs/initramfs/05-init-bottom.log

if command -v findmnt >/dev/null 2>&1; then
  check_command findmnt-verify findmnt --verify
  check_command root-mounted findmnt /
  if [ -d /sys/firmware/efi ]; then
    check_command efi-mounted findmnt /boot/efi
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  system_state=$(systemctl is-system-running 2>/dev/null || true)
  record "system_state=${system_state:-unknown}"
  case "$system_state" in
    degraded|failed|maintenance|emergency)
      log_line validation error systemd "system_state=${system_state}"
      failures=$((failures + 1))
      ;;
  esac
  failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | sed -n '1,20p' || true)
  if [ -n "$failed_units" ]; then
    record "FAIL failed-units-present"
    printf '%s\n' "$failed_units" >>"$VALIDATION_FILE"
    log_line validation error systemd "failed_units_present=true"
    failures=$((failures + 1))
  else
    record "PASS failed-units-absent"
  fi
fi

validate_desktop_role

if command -v mokutil >/dev/null 2>&1; then
  capture secureboot-state.txt mokutil --sb-state
  capture mok-enrollment.txt mokutil --list-enrolled
  log_line enrollment info secureboot "mokutil_collected=true"
else
  log_line enrollment warn secureboot "mokutil=missing"
fi

if command -v systemctl >/dev/null 2>&1; then
  capture security-baseline-units.txt systemctl status apparmor.service auditd.service nftables.service ssh.service sshd.service --no-pager --lines=40
  log_line security-baseline info systemd "security_unit_status_collected=true"
fi

if [ -r /boot/grub/grub.cfg ]; then
  record "PASS grub-cfg-readable"
else
  record "FAIL grub-cfg-readable: /boot/grub/grub.cfg"
  log_line validation error bootloader "missing=/boot/grub/grub.cfg"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  record "validation_status=pass"
  log_line validation info validation "validation_status=pass"
  exit 0
fi

record "validation_status=fail failures=${failures}"
log_line validation error validation "validation_status=fail failures=${failures}"
exit 1
