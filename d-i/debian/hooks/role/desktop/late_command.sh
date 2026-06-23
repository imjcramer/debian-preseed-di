#!/bin/sh
set -eu

requested_seed_base=${1:-}
requested_host_profile=${2:-}
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
shared_late=${SHARED_LATE_COMMAND:-${runtime_dir}/bootstrap/shared-late.sh}

[ -s "$shared_late" ] || {
  printf '[late:role:desktop] fatal: shared late command module is unavailable: %s\n' "$shared_late" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$shared_late"

late_command_shared_init "$requested_seed_base" "$requested_host_profile" desktop
late_command_load_host_env

desktop_module_dir="${runtime_dir}/bootstrap/desktop-modules"
install -d -m 0700 "$desktop_module_dir"
for desktop_module in detect components labwc; do
  fetch_hook "scripts/desktop/${desktop_module}.sh" "${desktop_module_dir}/${desktop_module}.sh"
done
unset desktop_module

# shellcheck disable=SC1090,SC1091
. "${desktop_module_dir}/detect.sh"
# shellcheck disable=SC1090,SC1091
. "${desktop_module_dir}/components.sh"
# shellcheck disable=SC1090,SC1091
. "${desktop_module_dir}/labwc.sh"

run_desktop_late_command "$requested_seed_base" "$requested_host_profile"
installer_archive_logs_to_target copy || true
