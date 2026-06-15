#!/bin/sh
set -eu

target_root=${1:-/target}
[ -d "$target_root" ] || exit 0

devops_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

validate_devops_storage_path() {
  case "${1:-}" in
    /*) ;;
    *) devops_fatal "devops storage path must be absolute: ${1:-unset}" ;;
  esac
  case "$1" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      devops_fatal "devops storage path contains unsupported syntax: $1"
      ;;
  esac
}

target_passwd_ids() {
  awk -F: -v wanted_user="$1" '$1 == wanted_user { print $3 ":" $4; exit }' "${target_root}/etc/passwd" 2>/dev/null || true
}

account_env=${INSTALLER_LATE_ACCOUNT_ENV:-/tmp/install-env-late/account.env}
if [ -r "$account_env" ]; then
  # shellcheck disable=SC1090
  . "$account_env"
fi

host_env=${INSTALLER_LATE_HOST_ENV:-/tmp/install-env-late/host.env}
if [ -r "$host_env" ]; then
  # shellcheck disable=SC1090
  . "$host_env"
fi

runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
tmp_env_dir=${INSTALLER_LATE_TMP_ENV_DIR:-/tmp/install-env-late/devops}
profile_path="${target_root}/etc/profile.d/70-devops-storage.sh"
tmpfiles_path="${target_root}/etc/tmpfiles.d/80-devops-storage.conf"
profile_tmp="${tmp_env_dir}/70-devops-storage.sh"
tmpfiles_tmp="${tmp_env_dir}/80-devops-storage.conf"

install -d -m 0755 \
  "${target_root}/etc/profile.d" \
  "${target_root}/etc/tmpfiles.d"

[ -s "$bootstrap_lib" ] || {
  printf 'fatal: installer bootstrap library is unavailable: %s\n' "$bootstrap_lib" >&2
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_current_seed_base)
install -d -m 0700 "$tmp_env_dir"
bootstrap_fetch_seed_file "$seed_base" \
  "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/profile.d/70-devops-storage.sh)" \
  "$profile_tmp" \
  0644 \
  "devops storage profile"
bootstrap_fetch_seed_file "$seed_base" \
  "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/80-devops-storage.conf)" \
  "$tmpfiles_tmp" \
  0644 \
  "devops storage tmpfiles policy"

: "${DIR_POOL:?DIR_POOL must be set before staging devops helper assets}"
: "${DIR_POOL_BUILD:?DIR_POOL_BUILD must be set before staging devops helper assets}"
: "${DIR_POOL_CACHE:?DIR_POOL_CACHE must be set before staging devops helper assets}"
: "${DIR_POOL_DB:?DIR_POOL_DB must be set before staging devops helper assets}"

validate_devops_storage_path "$DIR_POOL"
validate_devops_storage_path "$DIR_POOL_BUILD"
validate_devops_storage_path "$DIR_POOL_CACHE"
validate_devops_storage_path "$DIR_POOL_DB"

installer_apply_scalar_placeholders \
  "$profile_tmp" \
  "${profile_tmp}.rendered" \
  DIR_POOL "$DIR_POOL" \
  DIR_POOL_BUILD "$DIR_POOL_BUILD" \
  DIR_POOL_CACHE "$DIR_POOL_CACHE" \
  DIR_POOL_DB "$DIR_POOL_DB"
mv "${profile_tmp}.rendered" "$profile_tmp"

installer_apply_scalar_placeholders \
  "$tmpfiles_tmp" \
  "${tmpfiles_tmp}.rendered" \
  DIR_POOL_BUILD "$DIR_POOL_BUILD" \
  DIR_POOL_CACHE "$DIR_POOL_CACHE" \
  DIR_POOL_DB "$DIR_POOL_DB"
mv "${tmpfiles_tmp}.rendered" "$tmpfiles_tmp"

install -m 0644 "$profile_tmp" "$profile_path"
install -m 0644 "$tmpfiles_tmp" "$tmpfiles_path"

for pool_dir in \
  "$DIR_POOL_BUILD" \
  "$DIR_POOL_CACHE" \
  "$DIR_POOL_DB"
do
  [ -d "${target_root}${pool_dir}" ] || devops_fatal "shared runtime storage root is missing before devops helper runs: ${target_root}${pool_dir}"
done
unset pool_dir

for user_name in root "${ACCOUNT_USERNAME:-}"; do
  [ -n "$user_name" ] || continue
  case "$user_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@-]*)
      devops_fatal "unsafe devops storage user name: ${user_name}"
      ;;
  esac
  install -d -m 0755 \
    "${target_root}${DIR_POOL_BUILD}/${user_name}" \
    "${target_root}${DIR_POOL_CACHE}/${user_name}" \
    "${target_root}${DIR_POOL_DB}/${user_name}"
  user_ids=$(target_passwd_ids "$user_name")
  if [ -n "$user_ids" ]; then
    chown "$user_ids" \
      "${target_root}${DIR_POOL_BUILD}/${user_name}" \
      "${target_root}${DIR_POOL_CACHE}/${user_name}" \
      "${target_root}${DIR_POOL_DB}/${user_name}"
  fi
done

printf '[late:devops] staged /pool-backed development storage policy target=%s\n' "$target_root" >&2
