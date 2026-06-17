#!/bin/sh
# GitLab Runner service staging helpers. This file is sourced by shared late_command.

gitlab_runner_service_is_selected() {
  installer_selected_class_reference_is_selected service/gitlab-runner 2>/dev/null
}

gitlab_runner_require_abs_path() {
  podman_require_abs_path "$@"
}

gitlab_runner_validate_username() {
  podman_validate_username "$@"
}

gitlab_runner_target_passwd_record() {
  target_user=$1
  awk -F: -v wanted_user="$target_user" '$1 == wanted_user { print $3 ":" $4 ":" $6; exit }' /target/etc/passwd
}

gitlab_runner_target_group_gid() {
  target_group=$1
  awk -F: -v wanted_group="$target_group" '$1 == wanted_group { print $3; exit }' /target/etc/group
}

gitlab_runner_target_user_unit_paths() {
  target_user=$1
  base_dir=$2
  home_dir=$3

  GITLAB_RUNNER_MANAGED_UNIT_DIR="${base_dir}/systemd/user"
  GITLAB_RUNNER_MANAGED_UNIT_FILE="${GITLAB_RUNNER_MANAGED_UNIT_DIR}/gitlab-runner.service"
  GITLAB_RUNNER_BACKUP_UNIT_DIR="${base_dir}/backups/systemd"
  GITLAB_RUNNER_HOME_UNIT_DIR="${home_dir}/.config/systemd/user"
  GITLAB_RUNNER_HOME_UNIT_FILE="${GITLAB_RUNNER_HOME_UNIT_DIR}/gitlab-runner.service"
  GITLAB_RUNNER_HOME_WANTS_DIR="${home_dir}/.config/systemd/user/default.target.wants"
  GITLAB_RUNNER_HOME_WANTS_FILE="${GITLAB_RUNNER_HOME_WANTS_DIR}/gitlab-runner.service"
}

gitlab_runner_fetch_env() {
  source_relpath=$1
  dest_path=$2
  fetch_hook "$(installer_repo_join_var DIR_HOSTS_SERVICES "$source_relpath")" "$dest_path"
  [ -r "$dest_path" ] || installer_fatal "GitLab runner env is missing after fetch: ${source_relpath}"
}

gitlab_runner_load_envs() {
  [ "${GITLAB_RUNNER_ENVS_LOADED:-0}" = 1 ] && return 0

  GITLAB_RUNNER_SHARED_SOURCE_ENV="${TMP_ENV_DIR}/gitlab-runner-shared.env"
  GITLAB_RUNNER_APTLY_SOURCE_ENV="${TMP_ENV_DIR}/gitlab-runner-aptly.env"
  GITLAB_RUNNER_BUILD_SOURCE_ENV="${TMP_ENV_DIR}/gitlab-runner-build.env"
  GITLAB_RUNNER_TASK_SOURCE_ENV="${TMP_ENV_DIR}/gitlab-runner-task.env"

  gitlab_runner_fetch_env gitlab/gitlab-runner-shared.env "$GITLAB_RUNNER_SHARED_SOURCE_ENV"
  gitlab_runner_fetch_env gitlab/gitlab-runner-aptly.env "$GITLAB_RUNNER_APTLY_SOURCE_ENV"
  gitlab_runner_fetch_env gitlab/gitlab-runner-build.env "$GITLAB_RUNNER_BUILD_SOURCE_ENV"
  gitlab_runner_fetch_env gitlab/gitlab-runner-task.env "$GITLAB_RUNNER_TASK_SOURCE_ENV"

  # shellcheck disable=SC1090,SC1091
  . "$GITLAB_RUNNER_SHARED_SOURCE_ENV"
  # shellcheck disable=SC1090,SC1091
  . "$GITLAB_RUNNER_APTLY_SOURCE_ENV"
  # shellcheck disable=SC1090,SC1091
  . "$GITLAB_RUNNER_BUILD_SOURCE_ENV"
  # shellcheck disable=SC1090,SC1091
  . "$GITLAB_RUNNER_TASK_SOURCE_ENV"

  gitlab_runner_require_abs_path GITLAB_RUNNER_ENV_DIR "${GITLAB_RUNNER_ENV_DIR:-}"
  gitlab_runner_require_abs_path GITLAB_RUNNER_STATE_BASE "${GITLAB_RUNNER_STATE_BASE:-}"
  gitlab_runner_require_abs_path GITLAB_RUNNER_USER_HOME_BASE "${GITLAB_RUNNER_USER_HOME_BASE:-}"
  gitlab_runner_require_abs_path GITLAB_RUNNER_PODMAN_CONFIG_BASE "${GITLAB_RUNNER_PODMAN_CONFIG_BASE:-}"
  gitlab_runner_require_abs_path GITLAB_RUNNER_PODMAN_STATE_BASE "${GITLAB_RUNNER_PODMAN_STATE_BASE:-}"
  gitlab_runner_require_abs_path GITLAB_RUNNER_PODMAN_TMP_BASE "${GITLAB_RUNNER_PODMAN_TMP_BASE:-}"
  [ -n "${GITLAB_RUNNER_CACHE_DIR_NAMES:-}" ] || installer_fatal "GITLAB_RUNNER_CACHE_DIR_NAMES must not be empty"
  podman_require_positive_uint GITLAB_RUNNER_START_TIMEOUT_SECONDS "${GITLAB_RUNNER_START_TIMEOUT_SECONDS:-1200}"
  gitlab_runner_validate_username GITLAB_RUNNER_APTLY_USERNAME "${GITLAB_RUNNER_APTLY_USERNAME:-}"
  gitlab_runner_validate_username GITLAB_RUNNER_APTLY_OWNER_USERNAME "${GITLAB_RUNNER_APTLY_OWNER_USERNAME:-}"
  gitlab_runner_validate_username GITLAB_RUNNER_BUILD_USERNAME "${GITLAB_RUNNER_BUILD_USERNAME:-}"
  gitlab_runner_validate_username GITLAB_RUNNER_TASK_USERNAME "${GITLAB_RUNNER_TASK_USERNAME:-}"
  [ -n "${GITLAB_RUNNER_CONFIG_GROUP:-}" ] || installer_fatal "GITLAB_RUNNER_CONFIG_GROUP must not be empty"
  case "${GITLAB_RUNNER_CONTROL_DIR_MODE:-0750}" in
    [0-7][0-7][0-7][0-7]|[0-7][0-7][0-7]) ;;
    *) installer_fatal "GITLAB_RUNNER_CONTROL_DIR_MODE must be an octal mode" ;;
  esac
  case "${GITLAB_RUNNER_CONTROL_FILE_MODE:-0640}" in
    [0-7][0-7][0-7][0-7]|[0-7][0-7][0-7]) ;;
    *) installer_fatal "GITLAB_RUNNER_CONTROL_FILE_MODE must be an octal mode" ;;
  esac
  [ "${GITLAB_RUNNER_BUILD_USERNAME}" = "${GITLAB_RUNNER_TASK_USERNAME}" ] ||
    installer_fatal "gitlab build and task runners must share the same managed user"
  GITLAB_RUNNER_ENVS_LOADED=1
}

gitlab_runner_ensure_locked_service_account() {
  service_user=$1
  service_home=$2
  service_shell=$3
  service_comment=$4

  gitlab_runner_validate_username service_user "$service_user"
  gitlab_runner_require_abs_path service_home "$service_home"

  run_in_target "ensure managed service account ${service_user}" /bin/sh -eu -c '
set -eu
service_user=$1
service_home=$2
service_shell=$3
service_comment=$4

uid_min=$(awk '"'"'$1 == "UID_MIN" && $2 ~ /^[0-9]+$/ { print $2; exit }'"'"' /etc/login.defs 2>/dev/null || true)
[ -n "$uid_min" ] || uid_min=1000

if getent passwd "$service_user" >/dev/null 2>&1; then
  passwd_entry=$(getent passwd "$service_user")
  current_uid=$(printf "%s\n" "$passwd_entry" | cut -d: -f3)
  current_gid=$(printf "%s\n" "$passwd_entry" | cut -d: -f4)
  current_home=$(printf "%s\n" "$passwd_entry" | cut -d: -f6)
  current_shell=$(printf "%s\n" "$passwd_entry" | cut -d: -f7)
  current_group=$(getent group "$current_gid" | cut -d: -f1)
  [ "$current_uid" -lt "$uid_min" ] || {
    printf "fatal: refusing to reuse login-class account for managed service user: %s\n" "$service_user" >&2
    exit 1
  }
  [ "$current_group" = "$service_user" ] || {
    printf "fatal: managed service user primary group must be %s, found %s\n" "$service_user" "$current_group" >&2
    exit 1
  }
  [ "$current_home" = "$service_home" ] || usermod -d "$service_home" -- "$service_user"
  [ "$current_shell" = "$service_shell" ] || usermod -s "$service_shell" -- "$service_user"
  gecos=$(printf "%s\n" "$passwd_entry" | cut -d: -f5)
  [ "$gecos" = "$service_comment" ] || usermod -c "$service_comment" -- "$service_user"
else
  groupadd --force --system -- "$service_user"
  useradd --system -g "$service_user" -M -d "$service_home" -s "$service_shell" -c "$service_comment" -- "$service_user"
fi

install -d -m 0700 -o "$service_user" -g "$service_user" "$service_home"

shadow_hash=$(awk -F: -v wanted_user="$service_user" '"'"'$1 == wanted_user { print $2; found=1; exit } END { if (!found) exit 1 }'"'"' /etc/shadow 2>/dev/null || true)
[ -n "$shadow_hash" ] || {
  printf "fatal: managed service user shadow entry is missing: %s\n" "$service_user" >&2
  exit 1
}

case "$shadow_hash" in
  '!'*|'*')
    ;;
  *)
    usermod -p "!" -- "$service_user"
    ;;
esac
' sh \
    "$service_user" \
    "$service_home" \
    "$service_shell" \
    "$service_comment"
}

gitlab_runner_mask_target_system_service() {
  unit_name=$1
  mask_path="/target/etc/systemd/system/${unit_name}"

  validate_systemd_unit_name "$unit_name"
  install -d -m 0755 /target/etc/systemd/system
  rm -f "/target/etc/systemd/system/multi-user.target.wants/${unit_name}"
  rm -f "/target/etc/systemd/system/default.target.wants/${unit_name}"
  ln -sfn /dev/null "$mask_path"
  [ -L "$mask_path" ] || installer_fatal "masked target unit symlink is missing: ${mask_path}"
  [ "$(readlink "$mask_path")" = "/dev/null" ] || installer_fatal "masked target unit must point to /dev/null: ${mask_path}"
}

gitlab_runner_remove_target_package_identity() {
  run_in_target "remove package-created gitlab-runner account" /bin/sh -c '
set -eu
if getent passwd gitlab-runner >/dev/null 2>&1; then
  userdel --force --remove gitlab-runner >/dev/null 2>&1 || userdel --remove gitlab-runner >/dev/null 2>&1 || true
fi
if getent group gitlab-runner >/dev/null 2>&1; then
  groupdel gitlab-runner >/dev/null 2>&1 || true
fi
' sh
}

gitlab_runner_stage_target_envs() {
  install -d -m 0755 "/target${GITLAB_RUNNER_ENV_DIR}"

  stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab/README.md)" "${GITLAB_RUNNER_ENV_DIR}/README.md" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab/gitlab-runner-shared.env)" "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-shared.env" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab/gitlab-runner-aptly.env)" "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-aptly.env" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab/gitlab-runner-build.env)" "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-build.env" 0640
  stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab/gitlab-runner-task.env)" "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-task.env" 0640

  chown root:root "/target${GITLAB_RUNNER_ENV_DIR}/README.md"
  chown root:root "/target${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-shared.env"
  chown "root:${GITLAB_RUNNER_APTLY_GID}" "/target${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-aptly.env"
  chown "root:${GITLAB_RUNNER_SHARED_GID}" "/target${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-build.env" "/target${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-task.env"
}

gitlab_runner_verify_target_env_path() {
  target_path=$1
  expected_gid=$2
  expected_mode=$3

  run_in_target "verify staged GitLab runner env ${target_path}" /bin/sh -eu -c '
path=$1
expected_gid=$2
expected_mode=$3
 [ -f "$path" ] || {
  printf "fatal: managed GitLab runner env file is missing: %s\n" "$path" >&2
  exit 1
}
[ ! -L "$path" ] || {
  printf "fatal: managed GitLab runner env file must not be a symlink: %s\n" "$path" >&2
  exit 1
}
set -- $(stat -c "%u %g %a" "$path")
env_uid=$1
env_gid=$2
env_mode=$3

[ "$env_uid" = 0 ] || {
  printf "fatal: managed GitLab runner env file owner must be root: %s\n" "$path" >&2
  exit 1
}
[ "$env_gid" = "$expected_gid" ] || {
  printf "fatal: managed GitLab runner env file group drifted for %s: expected %s, found %s\n" "$path" "$expected_gid" "$env_gid" >&2
  exit 1
}
[ "$env_mode" = "$expected_mode" ] || {
  printf "fatal: managed GitLab runner env file mode drifted for %s: expected %s, found %s\n" "$path" "$expected_mode" "$env_mode" >&2
  exit 1
}
' sh "$target_path" "$expected_gid" "$expected_mode"
}

gitlab_runner_verify_target_envs() {
  run_in_target "verify staged GitLab runner env dir ${GITLAB_RUNNER_ENV_DIR}" /bin/sh -eu -c '
path=$1
[ -d "$path" ] || {
  printf "fatal: managed GitLab runner env dir is missing: %s\n" "$path" >&2
  exit 1
}
[ ! -L "$path" ] || {
  printf "fatal: managed GitLab runner env dir must not be a symlink: %s\n" "$path" >&2
  exit 1
}
set -- $(stat -c "%u %g %a" "$path")
env_dir_uid=$1
env_dir_gid=$2
env_dir_mode=$3
[ "$env_dir_uid" = 0 ] || {
  printf "fatal: managed GitLab runner env dir owner must be root: %s\n" "$path" >&2
  exit 1
}
[ "$env_dir_gid" = 0 ] || {
  printf "fatal: managed GitLab runner env dir group must be root: %s\n" "$path" >&2
  exit 1
}
[ "$env_dir_mode" = 755 ] || {
  printf "fatal: managed GitLab runner env dir mode drifted: %s\n" "$path" >&2
  exit 1
}
' sh "$GITLAB_RUNNER_ENV_DIR"

  gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-shared.env" 0 644
  gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-aptly.env" "$GITLAB_RUNNER_APTLY_GID" 640
  gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-build.env" "$GITLAB_RUNNER_SHARED_GID" 640
  gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-task.env" "$GITLAB_RUNNER_SHARED_GID" 640
}

gitlab_runner_stage_service_assets() {
  install -d -m 0755 "/target${GITLAB_RUNNER_STATE_BASE}" "/target${GITLAB_RUNNER_STATE_BASE}/templates"
  chown root:root "/target${GITLAB_RUNNER_STATE_BASE}" "/target${GITLAB_RUNNER_STATE_BASE}/templates"

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/usr/local/sbin/aptly-managed)" /usr/local/sbin/aptly-managed 0750
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/usr/local/sbin/aptly-bridge-processor)" /usr/local/sbin/aptly-bridge-processor 0750
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/usr/local/libexec/aptly-publish-managed)" /usr/local/libexec/aptly-publish-managed 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/usr/local/sbin/glab-helper)" /usr/local/sbin/glab-helper 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/usr/local/sbin/gitlab-runner-managed)" /usr/local/sbin/gitlab-runner-managed 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/data/config/runners/templates/gitlab-runner.service.tmpl)" "${GITLAB_RUNNER_STATE_BASE}/templates/gitlab-runner.service.tmpl" 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/etc/systemd/system/aptly-bridge.service)" /etc/systemd/system/aptly-bridge.service 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/etc/systemd/system/aptly-bridge.path)" /etc/systemd/system/aptly-bridge.path 0644

  render_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/etc/tmpfiles.d/80-gitlab-runner-storage.conf.tmpl)" "/etc/tmpfiles.d/80-gitlab-runner-storage.conf" 0644
  target_asset_assert_no_unresolved_installer_placeholders \
    /target/etc/tmpfiles.d/80-gitlab-runner-storage.conf \
    "GitLab runner aptly storage tmpfiles policy"
  normalize_target_tmpfiles_directory_policy "/etc/tmpfiles.d/80-gitlab-runner-storage.conf" "GitLab runner aptly storage"

  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/pool/aptly/Containerfile)" /pool/aptly/Containerfile 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/pool/aptly/.aptly.conf.template.json)" /pool/aptly/.aptly.conf.template.json 0644
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/pool/aptly/bin/prepare-aptly-env.sh)" /pool/aptly/bin/prepare-aptly-env.sh 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/pool/aptly/bin/aptly)" /pool/aptly/bin/aptly 0755
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SERVICES_GITLAB target/pool/aptly/bin/aptly-bridge)" /pool/aptly/bin/aptly-bridge 0755

  install -d -m 0755 /target/etc/systemd/system/multi-user.target.wants
  ln -sfn /etc/systemd/system/aptly-bridge.path /target/etc/systemd/system/multi-user.target.wants/aptly-bridge.path

  chown root:root \
    /target/usr/local/sbin/aptly-managed \
    /target/usr/local/sbin/aptly-bridge-processor \
    /target/usr/local/libexec/aptly-publish-managed \
    /target/etc/systemd/system/aptly-bridge.service \
    /target/etc/systemd/system/aptly-bridge.path \
    /target/pool/aptly/Containerfile \
    /target/pool/aptly/.aptly.conf.template.json \
    /target/pool/aptly/bin/prepare-aptly-env.sh \
    /target/pool/aptly/bin/aptly \
    /target/pool/aptly/bin/aptly-bridge
}

gitlab_runner_configure_podman_user() {
  podman_user=$1
  podman_comment="${GITLAB_PODMAN_USER_COMMENT_PREFIX} ${podman_user}"
  podman_home="${GITLAB_RUNNER_USER_HOME_BASE}/${podman_user}"
  podman_config_root="${GITLAB_RUNNER_PODMAN_CONFIG_BASE}/${podman_user}"
  podman_state_root="${GITLAB_RUNNER_PODMAN_STATE_BASE}/${podman_user}"
  podman_tmp_root="${GITLAB_RUNNER_PODMAN_TMP_BASE}/${podman_user}"
  podman_tls_root="${podman_config_root}/tls"

  (
    PODMAN_USER=$podman_user
    PODMAN_USER_COMMENT=$podman_comment
    PODMAN_USER_HOME=$podman_home
    PODMAN_USER_SHELL=$GITLAB_PODMAN_USER_SHELL
    PODMAN_USER_LOCK=$GITLAB_PODMAN_USER_LOCK
    PODMAN_USER_LINGER=$GITLAB_PODMAN_USER_LINGER
    PODMAN_USER_DAEMON=$GITLAB_PODMAN_USER_DAEMON
    PODMAN_USER_DOCKER_HOST=${GITLAB_PODMAN_USER_DOCKER_HOST:-0}
    PODMAN_USER_CONTAINER_HOST=${GITLAB_PODMAN_USER_CONTAINER_HOST:-0}
    PODMAN_USER_STRIP_GROUPS=$GITLAB_PODMAN_USER_STRIP_GROUPS
    PODMAN_USER_ALLOWED_GROUPS=$GITLAB_PODMAN_USER_ALLOWED_GROUPS
    PODMAN_SERVICE_SLICE_ENABLE=$GITLAB_PODMAN_SERVICE_SLICE_ENABLE
    PODMAN_SERVICE_SLICE_CPU_WEIGHT=$GITLAB_PODMAN_SERVICE_SLICE_CPU_WEIGHT
    PODMAN_SERVICE_SLICE_IO_WEIGHT=$GITLAB_PODMAN_SERVICE_SLICE_IO_WEIGHT
    PODMAN_SERVICE_SLICE_TASKS_MAX=$GITLAB_PODMAN_SERVICE_SLICE_TASKS_MAX
    PODMAN_ENABLE_ROOTLESS_SYSCTL=$GITLAB_PODMAN_ENABLE_ROOTLESS_SYSCTL
    PODMAN_ROOTLESS_USERNS_CLONE=$GITLAB_PODMAN_ROOTLESS_USERNS_CLONE
    PODMAN_ROOTLESS_MAX_USER_NAMESPACES=$GITLAB_PODMAN_ROOTLESS_MAX_USER_NAMESPACES
    PODMAN_USER_CONFIG_BASE=$podman_config_root
    PODMAN_ROOTLESS_STATE_BASE=$podman_state_root
    PODMAN_ROOTLESS_TMP_BASE=$podman_tmp_root
    PODMAN_TLS_PKI_BASE=$podman_tls_root
    PODMAN_TLS_KEY_PASSPHRASE_FILE="${podman_tls_root}/private/passphrase.txt"
    PODMAN_STORAGE_DRIVER=$GITLAB_PODMAN_STORAGE_DRIVER
    PODMAN_RUNTIME=$GITLAB_PODMAN_RUNTIME
    PODMAN_EVENTS_LOGGER=$GITLAB_PODMAN_EVENTS_LOGGER
    PODMAN_CGROUP_MANAGER=$GITLAB_PODMAN_CGROUP_MANAGER
    PODMAN_NETWORK_BACKEND=$GITLAB_PODMAN_NETWORK_BACKEND
    PODMAN_FIREWALL_DRIVER=$GITLAB_PODMAN_FIREWALL_DRIVER
    PODMAN_ROOTLESS_NETWORK_CMD=$GITLAB_PODMAN_ROOTLESS_NETWORK_CMD
    PODMAN_CONTAINERS_LOG_DRIVER=$GITLAB_PODMAN_CONTAINERS_LOG_DRIVER
    PODMAN_CONTAINERS_CGROUPNS=$GITLAB_PODMAN_CONTAINERS_CGROUPNS
    PODMAN_CONTAINERS_UTSNS=$GITLAB_PODMAN_CONTAINERS_UTSNS
    PODMAN_SHORT_NAME_MODE=$GITLAB_PODMAN_SHORT_NAME_MODE
    PODMAN_UNQUALIFIED_SEARCH_REGISTRIES=$GITLAB_PODMAN_UNQUALIFIED_SEARCH_REGISTRIES
    PODMAN_BLOCKED_REGISTRIES=$GITLAB_PODMAN_BLOCKED_REGISTRIES
    PODMAN_ROOTLESS_BUILDAH_ISOLATION=$GITLAB_PODMAN_ROOTLESS_BUILDAH_ISOLATION
    PODMAN_TLS_ENABLE=$GITLAB_PODMAN_TLS_ENABLE
    PODMAN_TLS_REGISTRIES=$GITLAB_PODMAN_TLS_REGISTRIES
    PODMAN_TLS_CA_COMMON_NAME=$GITLAB_PODMAN_TLS_CA_COMMON_NAME
    PODMAN_TLS_CA_DAYS=$GITLAB_PODMAN_TLS_CA_DAYS
    PODMAN_TLS_CERT_DAYS=$GITLAB_PODMAN_TLS_CERT_DAYS
    PODMAN_TLS_RSA_BITS=$GITLAB_PODMAN_TLS_RSA_BITS
    PODMAN_LINGER_UNIT_NAME="podman-rootless-linger-${podman_user}.service"
    PODMAN_LINGER_MARKER="/var/lib/preseed/firstboot/podman-rootless-linger-${podman_user}.done"
    export \
      PODMAN_USER \
      PODMAN_USER_COMMENT \
      PODMAN_USER_HOME \
      PODMAN_USER_SHELL \
      PODMAN_USER_LOCK \
      PODMAN_USER_LINGER \
      PODMAN_USER_DAEMON \
      PODMAN_USER_DOCKER_HOST \
      PODMAN_USER_CONTAINER_HOST \
      PODMAN_USER_STRIP_GROUPS \
      PODMAN_USER_ALLOWED_GROUPS \
      PODMAN_SERVICE_SLICE_ENABLE \
      PODMAN_SERVICE_SLICE_CPU_WEIGHT \
      PODMAN_SERVICE_SLICE_IO_WEIGHT \
      PODMAN_SERVICE_SLICE_TASKS_MAX \
      PODMAN_ENABLE_ROOTLESS_SYSCTL \
      PODMAN_ROOTLESS_USERNS_CLONE \
      PODMAN_ROOTLESS_MAX_USER_NAMESPACES \
      PODMAN_USER_CONFIG_BASE \
      PODMAN_ROOTLESS_STATE_BASE \
      PODMAN_ROOTLESS_TMP_BASE \
      PODMAN_TLS_PKI_BASE \
      PODMAN_TLS_KEY_PASSPHRASE_FILE \
      PODMAN_STORAGE_DRIVER \
      PODMAN_RUNTIME \
      PODMAN_EVENTS_LOGGER \
      PODMAN_CGROUP_MANAGER \
      PODMAN_NETWORK_BACKEND \
      PODMAN_FIREWALL_DRIVER \
      PODMAN_ROOTLESS_NETWORK_CMD \
      PODMAN_CONTAINERS_LOG_DRIVER \
      PODMAN_CONTAINERS_CGROUPNS \
      PODMAN_CONTAINERS_UTSNS \
      PODMAN_SHORT_NAME_MODE \
      PODMAN_UNQUALIFIED_SEARCH_REGISTRIES \
      PODMAN_BLOCKED_REGISTRIES \
      PODMAN_ROOTLESS_BUILDAH_ISOLATION \
      PODMAN_TLS_ENABLE \
      PODMAN_TLS_REGISTRIES \
      PODMAN_TLS_CA_COMMON_NAME \
      PODMAN_TLS_CA_DAYS \
      PODMAN_TLS_CERT_DAYS \
      PODMAN_TLS_RSA_BITS \
      PODMAN_LINGER_UNIT_NAME \
      PODMAN_LINGER_MARKER
    configure_target_rootless_podman_without_podbin
  )
}

gitlab_runner_ensure_target_tree() {
  target_path=$1
  target_mode=$2
  target_uid=$3
  target_gid=$4

  install -d -m "$target_mode" "/target${target_path}"
  chown "$target_uid:$target_gid" "/target${target_path}"
  chmod "$target_mode" "/target${target_path}"
}

gitlab_runner_parent_dir() {
  target_path=$1
  case "$target_path" in
    /*/*) printf '%s\n' "${target_path%/*}" ;;
    /*) printf '%s\n' / ;;
    *) installer_fatal "cannot derive parent for non-absolute path: ${target_path:-unset}" ;;
  esac
}

gitlab_runner_validate_cache_dir_name() {
  cache_name=$1
  case "$cache_name" in
    ''|/*|.*|*/.*|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+/-]*)
      installer_fatal "invalid GitLab runner cache directory name: ${cache_name:-unset}"
      ;;
  esac
}

gitlab_runner_prepare_runner_root() {
  runner_user=$1
  runner_uid=$2
  runner_gid=$3
  base_dir="${GITLAB_RUNNER_STATE_BASE}/${runner_user}"
  work_dir="${base_dir}/work"
  job_home="${base_dir}/home"
  backup_root="${base_dir}/backups"
  backup_dir="${backup_root}/systemd"
  system_id_path="${base_dir}/${GITLAB_RUNNER_SYSTEM_ID_BASENAME}"

  gitlab_runner_ensure_target_tree "$base_dir" "${GITLAB_RUNNER_CONTROL_DIR_MODE}" 0 "$GITLAB_RUNNER_CONTROL_GID"
  gitlab_runner_ensure_target_tree "$backup_root" "${GITLAB_RUNNER_CONTROL_DIR_MODE}" 0 "$GITLAB_RUNNER_CONTROL_GID"
  gitlab_runner_ensure_target_tree "$backup_dir" "${GITLAB_RUNNER_CONTROL_DIR_MODE}" 0 "$GITLAB_RUNNER_CONTROL_GID"
  gitlab_runner_ensure_target_tree "${base_dir}/systemd" "${GITLAB_RUNNER_CONTROL_DIR_MODE}" 0 "$GITLAB_RUNNER_CONTROL_GID"
  gitlab_runner_ensure_target_tree "${base_dir}/systemd/user" "${GITLAB_RUNNER_CONTROL_DIR_MODE}" 0 "$GITLAB_RUNNER_CONTROL_GID"
  gitlab_runner_ensure_target_tree "$work_dir" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "$job_home" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "${job_home}/.config" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "${job_home}/.config/systemd" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "${job_home}/.config/systemd/user" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "${job_home}/.config/systemd/user/default.target.wants" 0700 "$runner_uid" "$runner_gid"
  : >"/target${system_id_path}"
  chown "$runner_uid:$runner_gid" "/target${system_id_path}"
  chmod 0600 "/target${system_id_path}"
}

gitlab_runner_add_managed_users_to_devops_group() {
  run_in_target "add managed GitLab runner users to devops" /bin/sh -eu -c '
group_name=$1
shift
getent group "$group_name" >/dev/null 2>&1 || {
  printf "fatal: required target group is missing: %s\n" "$group_name" >&2
  exit 1
}
seen=" "
for runner_user in "$@"; do
  [ -n "$runner_user" ] || continue
  case "$seen" in
    *" $runner_user "*) continue ;;
  esac
  seen="${seen}${runner_user} "
  usermod -a -G "$group_name" -- "$runner_user"
done
' sh devops \
    "$GITLAB_RUNNER_APTLY_USERNAME" \
    "$GITLAB_RUNNER_BUILD_USERNAME" \
    "$GITLAB_RUNNER_TASK_USERNAME"
}

gitlab_runner_prepare_cache_root() {
  cache_root=$1
  runner_uid=$2
  runner_gid=$3

  gitlab_runner_ensure_target_tree "$cache_root" 0700 "$runner_uid" "$runner_gid"
  while IFS= read -r cache_name || [ -n "$cache_name" ]; do
    [ -n "$cache_name" ] || continue
    gitlab_runner_validate_cache_dir_name "$cache_name"
    gitlab_runner_ensure_target_tree "${cache_root}/${cache_name}" 0700 "$runner_uid" "$runner_gid"
  done <<EOF
${GITLAB_RUNNER_CACHE_DIR_NAMES}
EOF
}

gitlab_runner_prepare_runner_paths() {
  runner_user=$1
  runner_uid=$2
  runner_gid=$3
  builds_dir=$4
  gitlab_cache_dir=$5
  cache_root=$6

  gitlab_runner_require_abs_path builds_dir "$builds_dir"
  gitlab_runner_require_abs_path gitlab_cache_dir "$gitlab_cache_dir"
  gitlab_runner_require_abs_path cache_root "$cache_root"
  gitlab_cache_parent=$(gitlab_runner_parent_dir "$gitlab_cache_dir")
  gitlab_runner_ensure_target_tree "$builds_dir" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "$gitlab_cache_parent" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_ensure_target_tree "$gitlab_cache_dir" 0700 "$runner_uid" "$runner_gid"
  gitlab_runner_prepare_cache_root "$cache_root" "$runner_uid" "$runner_gid"
}

gitlab_runner_render_unit() {
  runner_user=$1
  runner_uid=$2
  runner_gid=$3
  runner_home=$4
  description=$5
  read_write_paths=$6
  read_only_paths=$7
  base_dir="${GITLAB_RUNNER_STATE_BASE}/${runner_user}"
  work_dir="${base_dir}/work"
  config_path="${base_dir}/${GITLAB_RUNNER_CONFIG_BASENAME}"
  system_id_path="${base_dir}/${GITLAB_RUNNER_SYSTEM_ID_BASENAME}"
  tmp_dir="/run/user/${runner_uid}/gitlab-runner/tmp"
  buildah_tmpdir="${GITLAB_RUNNER_PODMAN_TMP_BASE}/${runner_user}/tmp"
  template_src="/target${GITLAB_RUNNER_STATE_BASE}/templates/gitlab-runner.service.tmpl"
  rendered_tmp="${TMP_ENV_DIR}/gitlab-runner.${runner_user}.service"

  gitlab_runner_target_user_unit_paths "$runner_user" "$base_dir" "$runner_home"
  # ExecStartPre preflight and ensure-images create and verify BUILDAH_TMPDIR
  # inside the unit sandbox, so it must stay writable even though the broader
  # Podman service configuration remains external to this unit.
  read_write_paths="${read_write_paths} ${buildah_tmpdir} ${system_id_path}"
  installer_apply_scalar_placeholders "$template_src" "$rendered_tmp" \
    GITLAB_RUNNER_DESCRIPTION "$description" \
    GITLAB_RUNNER_USER "$runner_user" \
    GITLAB_RUNNER_UID "$runner_uid" \
    GITLAB_RUNNER_BASE_DIR "$base_dir" \
    GITLAB_RUNNER_WORK_DIR "$work_dir" \
    GITLAB_RUNNER_HOME_DIR "$runner_home" \
    GITLAB_RUNNER_XDG_CONFIG_HOME "${runner_home}/.config" \
    GITLAB_RUNNER_XDG_DATA_HOME "${runner_home}/.local/share" \
    GITLAB_RUNNER_XDG_CACHE_HOME "${runner_home}/.cache" \
    GITLAB_RUNNER_XDG_STATE_HOME "${runner_home}/.local/state" \
    GITLAB_RUNNER_CONFIG_PATH "$config_path" \
    GITLAB_RUNNER_TMP_DIR "$tmp_dir" \
    GITLAB_RUNNER_BUILDAH_ISOLATION "${GITLAB_PODMAN_ROOTLESS_BUILDAH_ISOLATION}" \
    GITLAB_RUNNER_BUILDAH_TMPDIR "$buildah_tmpdir" \
    GITLAB_RUNNER_MEMORY_HIGH "${GITLAB_RUNNER_MEMORY_HIGH}" \
    GITLAB_RUNNER_MEMORY_MAX "${GITLAB_RUNNER_MEMORY_MAX}" \
    GITLAB_RUNNER_CPU_QUOTA "${GITLAB_RUNNER_CPU_QUOTA}" \
    GITLAB_RUNNER_CPU_WEIGHT "${GITLAB_RUNNER_CPU_WEIGHT}" \
    GITLAB_RUNNER_TASKS_MAX "${GITLAB_RUNNER_TASKS_MAX}" \
    GITLAB_RUNNER_START_TIMEOUT "${GITLAB_RUNNER_START_TIMEOUT_SECONDS}s" \
    GITLAB_RUNNER_SERVICE_UMASK "${GITLAB_RUNNER_SERVICE_UMASK}" \
    GITLAB_RUNNER_READ_WRITE_PATHS "$read_write_paths" \
    GITLAB_RUNNER_READ_ONLY_PATHS "$read_only_paths"

  install -m "${GITLAB_RUNNER_CONTROL_FILE_MODE}" "$rendered_tmp" "/target${GITLAB_RUNNER_MANAGED_UNIT_FILE}"
  chown "root:${GITLAB_RUNNER_CONTROL_GID}" "/target${GITLAB_RUNNER_MANAGED_UNIT_FILE}"

  podman_install_symlink_with_backup "/target${GITLAB_RUNNER_HOME_UNIT_FILE}" "${GITLAB_RUNNER_MANAGED_UNIT_FILE}" "/target${GITLAB_RUNNER_BACKUP_UNIT_DIR}"
  chown -h "$runner_uid:$runner_gid" "/target${GITLAB_RUNNER_HOME_UNIT_FILE}"
}

gitlab_runner_verify_target_staging() {
  runner_user=$1
  base_dir="${GITLAB_RUNNER_STATE_BASE}/${runner_user}"
  home_dir="${GITLAB_RUNNER_USER_HOME_BASE}/${runner_user}"

  gitlab_runner_target_user_unit_paths "$runner_user" "$base_dir" "$home_dir"
  [ -x /target/usr/local/sbin/glab-helper ] || installer_fatal "managed GitLab runner operator helper is missing"
  [ -x /target/usr/local/sbin/gitlab-runner-managed ] || installer_fatal "managed GitLab runner helper is missing"
  [ -r "/target${GITLAB_RUNNER_MANAGED_UNIT_FILE}" ] || installer_fatal "managed GitLab runner user unit is missing: ${GITLAB_RUNNER_MANAGED_UNIT_FILE}"
  [ -L "/target${GITLAB_RUNNER_HOME_UNIT_FILE}" ] || installer_fatal "home GitLab runner unit symlink is missing: ${GITLAB_RUNNER_HOME_UNIT_FILE}"
  [ "$(readlink "/target${GITLAB_RUNNER_HOME_UNIT_FILE}")" = "${GITLAB_RUNNER_MANAGED_UNIT_FILE}" ] ||
    installer_fatal "home GitLab runner unit symlink drifted: ${GITLAB_RUNNER_HOME_UNIT_FILE}"
  [ ! -e "/target${GITLAB_RUNNER_HOME_WANTS_FILE}" ] || installer_fatal "GitLab runner unit must not be enabled before first successful once: ${GITLAB_RUNNER_HOME_WANTS_FILE}"
  [ ! -L "/target${GITLAB_RUNNER_HOME_WANTS_FILE}" ] || installer_fatal "GitLab runner unit must not be enabled before first successful once: ${GITLAB_RUNNER_HOME_WANTS_FILE}"
}

configure_target_gitlab_runner_if_selected() {
  gitlab_runner_service_is_selected || return 0

  gitlab_runner_load_envs
  test_in_target test -x /usr/bin/gitlab-runner ||
    installer_fatal "gitlab-runner binary is missing from target despite service/gitlab-runner selection"

  gitlab_runner_mask_target_system_service gitlab-runner.service
  gitlab_runner_remove_target_package_identity
  gitlab_runner_configure_podman_user "$GITLAB_RUNNER_APTLY_USERNAME"
  gitlab_runner_configure_podman_user "$GITLAB_RUNNER_BUILD_USERNAME"
  gitlab_runner_add_managed_users_to_devops_group
  gitlab_runner_ensure_locked_service_account "$GITLAB_RUNNER_APTLY_OWNER_USERNAME" "${GITLAB_RUNNER_USER_HOME_BASE}/${GITLAB_RUNNER_APTLY_OWNER_USERNAME}" /usr/sbin/nologin "Managed Aptly publisher account"

  GITLAB_RUNNER_CONTROL_GID=$(gitlab_runner_target_group_gid "$GITLAB_RUNNER_CONFIG_GROUP")
  [ -n "$GITLAB_RUNNER_CONTROL_GID" ] || installer_fatal "target GitLab runner control group is missing: ${GITLAB_RUNNER_CONFIG_GROUP}"

  aptly_record=$(gitlab_runner_target_passwd_record "$GITLAB_RUNNER_APTLY_USERNAME")
  [ -n "$aptly_record" ] || installer_fatal "target GitLab aptly user is missing: ${GITLAB_RUNNER_APTLY_USERNAME}"
  GITLAB_RUNNER_APTLY_UID=${aptly_record%%:*}
  aptly_record_rest=${aptly_record#*:}
  GITLAB_RUNNER_APTLY_GID=${aptly_record_rest%%:*}
  GITLAB_RUNNER_APTLY_HOME=${aptly_record_rest#*:}

  aptly_owner_record=$(gitlab_runner_target_passwd_record "$GITLAB_RUNNER_APTLY_OWNER_USERNAME")
  [ -n "$aptly_owner_record" ] || installer_fatal "target Aptly owner user is missing: ${GITLAB_RUNNER_APTLY_OWNER_USERNAME}"
  GITLAB_RUNNER_APTLY_OWNER_UID=${aptly_owner_record%%:*}
  aptly_owner_record_rest=${aptly_owner_record#*:}
  GITLAB_RUNNER_APTLY_OWNER_GID=${aptly_owner_record_rest%%:*}
  GITLAB_RUNNER_APTLY_OWNER_HOME=${aptly_owner_record_rest#*:}

  shared_record=$(gitlab_runner_target_passwd_record "$GITLAB_RUNNER_BUILD_USERNAME")
  [ -n "$shared_record" ] || installer_fatal "target shared GitLab runner user is missing: ${GITLAB_RUNNER_BUILD_USERNAME}"
  GITLAB_RUNNER_SHARED_UID=${shared_record%%:*}
  shared_record_rest=${shared_record#*:}
  GITLAB_RUNNER_SHARED_GID=${shared_record_rest%%:*}
  GITLAB_RUNNER_SHARED_HOME=${shared_record_rest#*:}

  gitlab_runner_prepare_runner_root "$GITLAB_RUNNER_APTLY_USERNAME" "$GITLAB_RUNNER_APTLY_UID" "$GITLAB_RUNNER_APTLY_GID"
  gitlab_runner_prepare_runner_root "$GITLAB_RUNNER_BUILD_USERNAME" "$GITLAB_RUNNER_SHARED_UID" "$GITLAB_RUNNER_SHARED_GID"
  gitlab_runner_prepare_runner_paths "$GITLAB_RUNNER_APTLY_USERNAME" "$GITLAB_RUNNER_APTLY_UID" "$GITLAB_RUNNER_APTLY_GID" \
    "$GITLAB_RUNNER_APTLY_BUILDS_DIR" "$GITLAB_RUNNER_APTLY_GITLAB_CACHE_DIR" "$GITLAB_RUNNER_APTLY_CACHE_ROOT"
  gitlab_runner_prepare_runner_paths "$GITLAB_RUNNER_BUILD_USERNAME" "$GITLAB_RUNNER_SHARED_UID" "$GITLAB_RUNNER_SHARED_GID" \
    "$GITLAB_RUNNER_BUILD_BUILDS_DIR" "$GITLAB_RUNNER_BUILD_GITLAB_CACHE_DIR" "$GITLAB_RUNNER_BUILD_CACHE_ROOT"
  gitlab_runner_prepare_runner_paths "$GITLAB_RUNNER_TASK_USERNAME" "$GITLAB_RUNNER_SHARED_UID" "$GITLAB_RUNNER_SHARED_GID" \
    "$GITLAB_RUNNER_TASK_BUILDS_DIR" "$GITLAB_RUNNER_TASK_GITLAB_CACHE_DIR" "$GITLAB_RUNNER_TASK_CACHE_ROOT"

  gitlab_runner_stage_service_assets
  gitlab_runner_stage_target_envs
  stage_target_helper_doc gitlab-runner.md gitlab-runner.md
  gitlab_runner_verify_target_envs

  gitlab_runner_render_unit \
    "$GITLAB_RUNNER_APTLY_USERNAME" \
    "$GITLAB_RUNNER_APTLY_UID" \
    "$GITLAB_RUNNER_APTLY_GID" \
    "$GITLAB_RUNNER_APTLY_HOME" \
    "GitLab Runner aptly docker executor" \
    "${GITLAB_RUNNER_STATE_BASE}/${GITLAB_RUNNER_APTLY_USERNAME}/work ${GITLAB_RUNNER_STATE_BASE}/${GITLAB_RUNNER_APTLY_USERNAME}/home ${GITLAB_RUNNER_APTLY_HOME} ${GITLAB_RUNNER_APTLY_BUILDS_DIR} ${GITLAB_RUNNER_APTLY_GITLAB_CACHE_DIR} ${GITLAB_RUNNER_APTLY_CACHE_ROOT} /run/user/${GITLAB_RUNNER_APTLY_UID}/gitlab-runner %t" \
    "${GITLAB_RUNNER_PODMAN_CONFIG_BASE}/${GITLAB_RUNNER_APTLY_USERNAME}"

  gitlab_runner_render_unit \
    "$GITLAB_RUNNER_BUILD_USERNAME" \
    "$GITLAB_RUNNER_SHARED_UID" \
    "$GITLAB_RUNNER_SHARED_GID" \
    "$GITLAB_RUNNER_SHARED_HOME" \
    "GitLab Runner build and task docker executor" \
    "${GITLAB_RUNNER_STATE_BASE}/${GITLAB_RUNNER_BUILD_USERNAME}/work ${GITLAB_RUNNER_STATE_BASE}/${GITLAB_RUNNER_BUILD_USERNAME}/home ${GITLAB_RUNNER_SHARED_HOME} ${GITLAB_RUNNER_BUILD_BUILDS_DIR} ${GITLAB_RUNNER_BUILD_GITLAB_CACHE_DIR} ${GITLAB_RUNNER_BUILD_CACHE_ROOT} ${GITLAB_RUNNER_TASK_BUILDS_DIR} ${GITLAB_RUNNER_TASK_GITLAB_CACHE_DIR} ${GITLAB_RUNNER_TASK_CACHE_ROOT} /run/user/${GITLAB_RUNNER_SHARED_UID}/gitlab-runner %t" \
    "${GITLAB_RUNNER_PODMAN_CONFIG_BASE}/${GITLAB_RUNNER_BUILD_USERNAME}"

  gitlab_runner_verify_target_staging "$GITLAB_RUNNER_APTLY_USERNAME"
  gitlab_runner_verify_target_staging "$GITLAB_RUNNER_BUILD_USERNAME"
}
