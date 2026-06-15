#!/bin/sh
set -eu

redacted_cmdline() {
  redacted=
  if [ -r /proc/cmdline ]; then
    for arg in $(cat /proc/cmdline 2>/dev/null || true); do
      case "$arg" in
        fruux_username=*|fruux_password=*|netcfg/wireless_wpa=*|wireless_wpa=*|wifi_wpa=*|*[Pp][Aa][Ss][Ss]*=*|*[Ss][Ee][Cc][Rr][Ee][Tt]*=*|*[Tt][Oo][Kk][Ee][Nn]*=*|*[Kk][Ee][Yy]*=*)
          arg=${arg%%=*}=REDACTED
          ;;
      esac
      redacted="${redacted:+$redacted }$arg"
    done
  fi
  printf '%s\n' "$redacted"
}

printf '[early:debug] host-profile=%s seed-base=%s\n' "${1:-}" "${2:-}" >&2
printf '[early:debug] cmdline=%s\n' "$(redacted_cmdline)" >&2
