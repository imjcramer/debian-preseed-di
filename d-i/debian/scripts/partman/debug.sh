#!/bin/sh
set -eu

host_profile=${1:-}
requested_seed_base=${2:-}
RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}

[ -s "$BOOTSTRAP_LIB" ] || {
  echo "fatal: installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}" >&2
  exit 1
}

# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "$requested_seed_base"

seed_base=$(installer_seed_base "$requested_seed_base")
helper_dest="${RUNTIME_DIR}/bootstrap/debug-detect-disk.sh"

installer_fetch_file "$seed_base" "$(installer_repo_join_var DIR_SCRIPTS_PARTMAN detect-disk.sh)" "$helper_dest" 0755
"$helper_dest" "$host_profile" >/dev/null 2>&1 || true
