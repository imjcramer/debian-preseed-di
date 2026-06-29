#!/bin/sh
# Labwc desktop target verification helpers.

desktop_verify_required_commands() {
  # shellcheck disable=SC2016
  run_in_target "verify Labwc desktop commands" /bin/sh -c '
set -eu
required_checked=0
optional_checked=0
optional_missing=

check_required() {
  cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || {
    printf "fatal: required desktop command is missing: %s\n" "$cmd" >&2
    exit 1
  }
  required_checked=$((required_checked + 1))
}

check_optional() {
  cmd=$1
  if command -v "$cmd" >/dev/null 2>&1; then
    optional_checked=$((optional_checked + 1))
    return 0
  fi
  optional_missing="${optional_missing:+$optional_missing }$cmd"
}

for cmd in \
  labwc \
  cage \
  gtkgreet \
  labwc-greeter-session \
  labwc-session \
  labwc-autostart \
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
  labwc-keyboard-layout \
  systemctl \
  dbus-update-activation-environment \
  khal \
  todoman \
  vdirsyncer
do
  check_required "$cmd"
done

for cmd in \
  crystal-dock \
  zsh \
  starship \
  btop \
  brightnessctl \
  ncdu \
  nmtui \
  fzf \
  wlr-randr \
  wlopm \
  wdisplays \
  waybar \
  kanshi \
  switcherooctl \
  vulkaninfo \
  vainfo \
  labwc-dock \
  labwc-dgpu-launcher \
  foot \
  kitty \
  wofi \
  mako \
  makoctl \
  swaylock \
  swaybg \
  swayidle \
  pgrep \
  pkill \
  grim \
  slurp \
  wpctl \
  wl-copy \
  thunar \
  nnn \
  mousepad \
  qimgv \
  zathura \
  xarchiver \
  nwg-look \
  pavucontrol \
  powerprofilesctl \
  xdg-terminal-exec \
  ikhal \
  pipewire \
  wireplumber \
  wsdd
do
  check_optional "$cmd"
done

printf "desktop_command_verification required_checked=%s optional_checked=%s optional_missing=%s\n" \
  "$required_checked" \
  "$optional_checked" \
  "${optional_missing:-none}"
' sh
}

desktop_verify_staged_files() {
  # shellcheck disable=SC2016
  run_in_target "verify Labwc desktop staged files" /bin/sh -c '
set -eu
fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

require_readable() {
  path=$1
  [ -r "$path" ] || fatal "staged desktop file is missing: $path"
}

require_executable() {
  path=$1
  [ -x "$path" ] || fatal "staged desktop executable is missing: $path"
}

verify_session_dropin() {
  unit=$1
  dropin="/etc/skel/.config/systemd/user/${unit}.d/10-labwc-session.conf"
  [ -r "$dropin" ] || fatal "user session drop-in is missing: ${unit}"
}

readable_count=0
executable_count=0
for path in \
  /etc/default/labwc-desktop \
  /etc/environment.d/90-labwc-session.conf \
  /etc/pam.d/greetd \
  /etc/pam.d/greetd-greeter \
  /etc/greetd/config.toml \
  /etc/greetd/gtkgreet.css \
  /etc/wsdd-server/defaults \
  /etc/systemd/system/greetd.service.d/20-labwc-vt.conf \
  /usr/share/wayland-sessions/labwc.desktop \
  /etc/skel/.config/labwc/rc.xml \
  /etc/skel/.config/labwc/menu.xml \
  /etc/skel/.config/labwc/autostart \
  /etc/skel/.config/labwc/shutdown \
  /etc/skel/.config/labwc/environment \
  /etc/skel/.config/labwc/environment.d/10-wayland.env \
  /etc/skel/.config/labwc/themerc-override \
  /etc/skel/.config/systemd/user/labwc-session.target \
  /etc/skel/.config/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf \
  /etc/skel/.config/systemd/user/xdg-desktop-portal.service.d/10-labwc-session.conf \
  /etc/skel/.config/systemd/user/xdg-desktop-portal-gtk.service.d/10-labwc-session.conf \
  /etc/skel/.config/systemd/user/xdg-desktop-portal-wlr.service.d/10-labwc-session.conf \
  /etc/skel/.config/systemd/user/xdg-desktop-portal-lxqt.service.d/10-labwc-session.conf \
  /etc/skel/.config/systemd/user/xdg-desktop-portal-xapp.service.d/10-labwc-session.conf
do
  require_readable "$path"
  readable_count=$((readable_count + 1))
done
for path in \
  /usr/local/bin/labwc-greeter-session \
  /usr/local/bin/labwc-session \
  /usr/local/bin/labwc-autostart \
  /usr/local/bin/labwc-admin-action \
  /usr/local/bin/labwc-calendar \
  /usr/local/bin/labwc-logout \
  /usr/local/bin/labwc-wofi \
  /usr/local/bin/labwc-terminal \
  /usr/local/bin/labwc-brightness-control \
  /usr/local/bin/labwc-power-settings \
  /usr/local/bin/labwc-output-refresh \
  /usr/local/bin/labwc-output-watch \
  /usr/local/bin/labwc-run \
  /usr/local/bin/labwc-lock \
  /usr/local/bin/labwc-power-menu \
  /usr/local/bin/labwc-keyboard-layout
do
  require_executable "$path"
  executable_count=$((executable_count + 1))
done

if [ ! -r /usr/lib/systemd/user/hyprpolkitagent.service ] &&
   [ ! -r /lib/systemd/user/hyprpolkitagent.service ]; then
  fatal "Hypr polkit user service is missing"
fi
if [ ! -x /usr/libexec/hyprpolkitagent ] &&
   [ ! -x /usr/lib/hyprpolkitagent ] &&
   [ ! -x /usr/lib64/hyprpolkitagent ]; then
  fatal "Hypr polkit agent executable is missing"
fi

verify_session_dropin hyprpolkitagent.service
for portal_unit in \
  xdg-desktop-portal.service \
  xdg-desktop-portal-gtk.service \
  xdg-desktop-portal-wlr.service \
  xdg-desktop-portal-lxqt.service \
  xdg-desktop-portal-xapp.service
do
  verify_session_dropin "$portal_unit"
  if [ -r "/usr/lib/systemd/user/${portal_unit}" ]; then
    portal_dropin="/etc/systemd/user/${portal_unit}.d/10-preseed-wayland-ready.conf"
    [ -r "$portal_dropin" ] || fatal "portal user unit must wait for Labwc session readiness: ${portal_unit}"
  fi
done

if [ -r /usr/lib/systemd/user/xdg-desktop-portal-lxqt.service ]; then
  lxqt_portal_dropin=/etc/systemd/user/xdg-desktop-portal-lxqt.service.d/10-preseed-portal-backend-env.conf
  [ -r "$lxqt_portal_dropin" ] || fatal "LXQt portal backend environment drop-in is missing"
fi

if [ -r /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service ]; then
  kwallet_portal_service=/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service
  kwallet_portal_source=/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service.distrib
  kwallet_legacy_local=/usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service
  [ -r "$kwallet_portal_service" ] || fatal "KWallet portal backend D-Bus override is missing"
  [ -r "$kwallet_portal_source" ] || fatal "KWallet portal backend D-Bus source diversion is missing"
  [ ! -e "$kwallet_legacy_local" ] && [ ! -L "$kwallet_legacy_local" ] || {
    fatal "KWallet portal backend must not leave a duplicate local D-Bus service"
  }
fi

printf "desktop_staged_file_verification readable=%s executable=%s\n" "$readable_count" "$executable_count"
' sh
}

desktop_verify_optional_staged_files() {
  # shellcheck disable=SC2016
  run_in_target "verify optional Labwc desktop staged files" /bin/sh -c '
set -eu
checked=0
missing=

check_optional_path() {
  path=$1
  if [ -e "$path" ]; then
    checked=$((checked + 1))
    return 0
  fi
  missing="${missing:+$missing }$path"
}

for path in \
  /usr/share/backgrounds/labwc/wallpapers/wall-labwall2-1920x1080.png \
  /usr/share/backgrounds/labwc/wallpapers/lock-labwall2-1920x1080.png \
  /etc/skel/.config/waybar/config \
  /etc/skel/.config/waybar/style.css \
  /etc/skel/.config/waybar/icons/nvidia.svg \
  /etc/skel/.config/kanshi/config \
  /etc/skel/.config/foot/foot.ini \
  /etc/skel/.config/kitty/kitty.conf \
  /etc/skel/.config/xdg-terminals.list \
  /etc/skel/.config/xfce4/helpers.rc \
  /usr/share/xfce4/helpers/foot.desktop \
  /etc/skel/.profile \
  /etc/skel/.bash_profile \
  /etc/skel/.bashrc \
  /etc/skel/.zprofile \
  /etc/skel/.zshrc \
  /etc/skel/.config/starship.toml \
  /etc/skel/.config/btop/btop.conf \
  /etc/skel/.config/fzf/default-opts \
  /etc/skel/.config/wofi/config \
  /etc/skel/.config/wofi/style.css \
  /etc/skel/.config/wofi/colors \
  /etc/skel/.config/Thunar/uca.xml \
  /etc/skel/.config/crystal-dock/labwc/appearance.conf \
  /etc/skel/.config/crystal-dock/labwc/panel_1.conf \
  /etc/xdg/crystal-dock/labwc/appearance.conf \
  /etc/xdg/crystal-dock/labwc/panel_1.conf \
  /etc/skel/.config/mako/config \
  /etc/skel/.config/swaylock/config \
  /etc/skel/.config/gtk-3.0/settings.ini \
  /etc/skel/.config/gtk-4.0/settings.ini \
  /etc/xdg/gtk-3.0/settings.ini \
  /etc/xdg/gtk-4.0/settings.ini \
  /etc/skel/.config/qt6ct/qt6ct.conf \
  /etc/skel/.config/kwalletrc \
  /etc/skel/.config/user-dirs.dirs \
  /etc/skel/.config/xdg-desktop-portal/portals.conf \
  /etc/xdg/xdg-desktop-portal/labwc-portals.conf \
  /etc/bluetooth/main.conf \
  /etc/chromium.d/90-preseed-performance-flags \
  /etc/systemd/user/labwc-calendar-sync.service \
  /etc/systemd/user/labwc-calendar-sync.timer \
  /etc/systemd/system/bluetooth.service.d/10-preseed-directory-mode.conf \
  /usr/local/bin/labwc-dgpu-launcher \
  /etc/skel/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf
do
  check_optional_path "$path"
done
printf "desktop_optional_staged_file_verification checked=%s missing=%s\n" "$checked" "${missing:-none}"
' sh
}

desktop_verify_primary_user_files() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"

  # shellcheck disable=SC2016
  run_in_target "verify Labwc primary account config" /bin/sh -c '
set -eu
fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

account_user=$1
account_home=$2
uid=$(id -u "$account_user")
gid=$(id -g "$account_user")
required_checked=0
optional_checked=0
optional_missing=

check_required_owned() {
  path=$1
  [ -r "$path" ] || {
    printf "fatal: missing account desktop file: %s\n" "$path" >&2
    exit 1
  }
  owner=$(stat -c "%u:%g" "$path")
  [ "$owner" = "$uid:$gid" ] || {
    printf "fatal: account desktop file owner mismatch for %s: %s\n" "$path" "$owner" >&2
    exit 1
  }
  required_checked=$((required_checked + 1))
}

check_required_owned_dir() {
  path=$1
  [ -d "$path" ] || {
    printf "fatal: missing account desktop directory: %s\n" "$path" >&2
    exit 1
  }
  owner=$(stat -c "%u:%g" "$path")
  [ "$owner" = "$uid:$gid" ] || {
    printf "fatal: account desktop directory owner mismatch for %s: %s\n" "$path" "$owner" >&2
    exit 1
  }
  required_checked=$((required_checked + 1))
}

check_optional_owned() {
  path=$1
  [ -r "$path" ] || {
    optional_missing="${optional_missing:+$optional_missing }$path"
    return 0
  }
  optional_checked=$((optional_checked + 1))
}

verify_account_session_dropin() {
  unit=$1
  dropin="$account_home/.config/systemd/user/${unit}.d/10-labwc-session.conf"
  [ -r "$dropin" ] || fatal "primary account user session drop-in is missing: ${unit}"
}

for path in \
  "$account_home/.config/labwc/rc.xml" \
  "$account_home/.config/labwc/menu.xml" \
  "$account_home/.config/labwc/autostart" \
  "$account_home/.config/labwc/shutdown" \
  "$account_home/.config/labwc/environment" \
  "$account_home/.config/labwc/themerc-override" \
  "$account_home/.config/systemd/user/labwc-session.target" \
  "$account_home/.config/systemd/user/hyprpolkitagent.service.d/10-labwc-session.conf" \
  "$account_home/.config/systemd/user/xdg-desktop-portal.service.d/10-labwc-session.conf" \
  "$account_home/.config/systemd/user/xdg-desktop-portal-gtk.service.d/10-labwc-session.conf" \
  "$account_home/.config/systemd/user/xdg-desktop-portal-wlr.service.d/10-labwc-session.conf" \
  "$account_home/.config/systemd/user/xdg-desktop-portal-lxqt.service.d/10-labwc-session.conf" \
  "$account_home/.config/systemd/user/xdg-desktop-portal-xapp.service.d/10-labwc-session.conf"
do
  check_required_owned "$path"
done

verify_account_session_dropin hyprpolkitagent.service

for path in \
  "$account_home/Desktop" \
  "$account_home/Documents" \
  "$account_home/Downloads" \
  "$account_home/Music" \
  "$account_home/Pictures" \
  "$account_home/Public" \
  "$account_home/Templates" \
  "$account_home/Videos" \
  "$account_home/Workspace"
do
  check_required_owned_dir "$path"
done

for path in \
  "$account_home/.config/waybar/config" \
  "$account_home/.config/foot/foot.ini" \
  "$account_home/.config/kitty/kitty.conf" \
  "$account_home/.config/xdg-terminals.list" \
  "$account_home/.config/xfce4/helpers.rc" \
  "$account_home/.config/wofi/config" \
  "$account_home/.config/wofi/style.css" \
  "$account_home/.config/wofi/colors" \
  "$account_home/.config/Thunar/uca.xml" \
  "$account_home/.config/crystal-dock/labwc/appearance.conf" \
  "$account_home/.config/crystal-dock/labwc/panel_1.conf" \
  "$account_home/.config/mako/config" \
  "$account_home/.config/kanshi/config" \
  "$account_home/.config/swaylock/config" \
  "$account_home/.profile" \
  "$account_home/.bash_profile" \
  "$account_home/.bashrc" \
  "$account_home/.zprofile" \
  "$account_home/.zshrc" \
  "$account_home/.config/starship.toml" \
  "$account_home/.config/btop/btop.conf" \
  "$account_home/.config/fzf/default-opts" \
  "$account_home/.config/gtk-3.0/settings.ini" \
  "$account_home/.config/gtk-4.0/settings.ini" \
  "$account_home/.config/vdirsyncer/config" \
  "$account_home/.config/khal/config" \
  "$account_home/.config/todoman/config.py" \
  "$account_home/.local/share/calendars/personal/displayname" \
  "$account_home/.local/share/calendars/tasks/displayname" \
  "$account_home/.config/qt6ct/qt6ct.conf" \
  "$account_home/.config/user-dirs.dirs" \
  "$account_home/.config/xdg-desktop-portal/portals.conf" \
  "$account_home/.config/kwalletrc"
do
  check_optional_owned "$path"
done

zsh_path=$(command -v zsh 2>/dev/null || true)
account_shell=$(getent passwd "$account_user" | cut -d: -f7)
shell_status=not-checked
if [ -n "$zsh_path" ]; then
  if [ "$account_shell" = "$zsh_path" ]; then
    shell_status=matches-zsh
  else
    shell_status=mismatch
  fi
fi

printf "desktop_primary_account_verification user=%s home=%s required_files=%s optional_files=%s optional_missing=%s shell=%s shell_status=%s\n" \
  "$account_user" \
  "$account_home" \
  "$required_checked" \
  "$optional_checked" \
  "${optional_missing:-none}" \
  "$account_shell" \
  "$shell_status"
' sh "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
}

desktop_verify_greeter_access() {
  : "${LABWC_GREETER_USER:?LABWC_GREETER_USER must be set}"

  # shellcheck disable=SC2016
  run_in_target "verify Labwc greeter seat and DRM access" /bin/sh -c '
set -eu
greeter_user=$1
checked=0
present=
missing=
greeter_groups=$(id -nG "$greeter_user")

for group_name in seat render video; do
  if ! getent group "$group_name" >/dev/null 2>&1; then
    missing="${missing:+$missing }$group_name"
    continue
  fi
  case " $greeter_groups " in
    *" $group_name "*) ;;
    *)
      printf "fatal: greeter user %s is missing required group %s\n" "$greeter_user" "$group_name" >&2
      exit 1
      ;;
  esac
  checked=$((checked + 1))
  present="${present:+$present }$group_name"
done

printf "desktop_greeter_access_verification user=%s checked=%s present=%s missing=%s\n" \
  "$greeter_user" \
  "$checked" \
  "${present:-none}" \
  "${missing:-none}"
' sh "$LABWC_GREETER_USER"
}

desktop_verify_primary_user_slice_limits() {
  # shellcheck disable=SC2016
  run_in_target "verify Labwc primary account user slice resource limits" /bin/sh -c '
set -eu
dropin=$1

[ -r "$dropin" ] || {
  printf "fatal: missing desktop user slice drop-in: %s\n" "$dropin" >&2
  exit 1
}

printf "desktop_user_slice_verification slice=%s dropin=%s\n" user-1000 "$dropin"
' sh \
    /etc/systemd/system/user-1000.slice.d/50-resource-limit.conf \
    "${DEBIAN_SLICE_CPU_QUOTA:-600%}" \
    "${DEBIAN_SLICE_MEMORY_HIGH:-80%}"
}

desktop_verify_target_staging() {
  desktop_verify_required_commands
  desktop_verify_staged_files
  desktop_verify_optional_staged_files
  desktop_verify_greeter_access
  desktop_verify_primary_user_files
  desktop_verify_primary_user_slice_limits
}
