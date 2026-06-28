#!/bin/sh
# shellcheck disable=SC2016
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=21
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

printf '1..%s\n' "$TEST_COUNT"

system_cfg="$ROOT_DIR/d-i/debian/classes/configs/system.cfg"
class_select="$ROOT_DIR/d-i/debian/classes/class-select/service/gitlab-runner.cfg"
shared_loader="$ROOT_DIR/d-i/debian/hooks/shared/late_command.sh"
dispatch_script="$ROOT_DIR/d-i/debian/scripts/late/dispatch.sh"
btrfs_late="$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh"
f2fs_late="$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"
repo_env="$ROOT_DIR/d-i/debian/repo.env"
common_lib="$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
gitlab_late="$ROOT_DIR/d-i/debian/scripts/late/gitlab-runner.sh"
podman_late="$ROOT_DIR/d-i/debian/scripts/late/podman.sh"
security_script="$ROOT_DIR/d-i/debian/scripts/late/security.sh"
shared_env="$ROOT_DIR/d-i/debian/hosts/services/gitlab-runner/gitlab-runner-shared.env"
runtime_storage_tmpfiles="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/tmpfiles.d/10-runtime-storage-roots.conf"
aptly_env="$ROOT_DIR/d-i/debian/hosts/services/gitlab-runner/gitlab-runner-aptly.env"
build_env="$ROOT_DIR/d-i/debian/hosts/services/gitlab-runner/gitlab-runner-build.env"
managed_helper="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/gitlab-runner-managed"
aptly_managed="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/aptly-managed"
aptly_bridge_processor="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/aptly-bridge-processor"
aptly_publish_helper="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/libexec/aptly-publish-managed"
operator_helper="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/glab-helper"
service_template="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/data/config/runners/templates/gitlab-runner.service.tmpl"
aptly_tmpfiles="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/etc/tmpfiles.d/80-gitlab-runner-storage.conf.tmpl"
aptly_prepare="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/bin/prepare-aptly-env.sh"
aptly_wrapper="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/bin/aptly"
aptly_bridge="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/bin/aptly-bridge"
aptly_containerfile="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/Containerfile"
aptly_template="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/.aptly.conf.template.json"
aptly_bridge_service="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/etc/systemd/system/aptly-bridge.service"
aptly_bridge_path="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/etc/systemd/system/aptly-bridge.path"
gitlab_nft_overlay="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/nftables/services/gitlab-runner.yml"
docs_index="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/README.md"
gitlab_runner_doc="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/gitlab-runner.md"
service_readme="$ROOT_DIR/d-i/debian/hosts/services/gitlab-runner/README.md"

if grep -q '^Name: gitlab-runner$' "$system_cfg" &&
   grep -q '^Description: GitLab Runner service role$' "$system_cfg" &&
   ! grep -q '^LateHelper: gitlab-runner-service$' "$system_cfg"; then
  pass "service/gitlab-runner class is registered and stays package-selected only"
else
  fail "service/gitlab-runner class is registered and stays package-selected only"
fi

if grep -q '^d-i apt-setup/local9/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$class_select" &&
   grep -q '^d-i pkgsel/include string .*gitlab-runner .*aptly .*podman .*buildah .*uidmap .*netavark .*aardvark-dns .*passt .*slirp4netns .*fuse-overlayfs .*golang-github-containernetworking-plugin-dnsname .*dbus-user-session' "$class_select"; then
  pass "service/gitlab-runner selects GitLab Runner and rootless Podman packages"
else
  fail "service/gitlab-runner selects GitLab Runner and rootless Podman packages"
fi

if grep -q '^gitlab_runner_install_target_bazelisk() {$' "$gitlab_late" &&
   grep -q 'https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64' "$gitlab_late" &&
   grep -q 'curl -fsSLo "\$tmp_bazelisk" "\$bazelisk_url"' "$gitlab_late" &&
   grep -q 'install -m 0755 "\$tmp_bazelisk" /usr/local/bin/bazelisk' "$gitlab_late" &&
   grep -q 'ln -sfn /usr/local/bin/bazelisk /usr/local/bin/bazel' "$gitlab_late" &&
   grep -q 'gitlab_runner_install_target_bazelisk' "$gitlab_late"; then
  pass "GitLab runner late helper installs Bazelisk into /usr/local/bin with bazel symlink"
else
  fail "GitLab runner late helper installs Bazelisk into /usr/local/bin with bazel symlink"
fi

if grep -Fq "  gitlab-runner \\" "$shared_loader" &&
   grep -q 'podman gitlab-runner zram-swap' "$dispatch_script"; then
  pass "shared late loader fetches the gitlab-runner module after Podman"
else
  fail "shared late loader fetches the gitlab-runner module after Podman"
fi

if grep -q 'configure_target_rootless_podman_if_selected' "$btrfs_late" &&
   grep -q 'configure_target_gitlab_runner_if_selected' "$btrfs_late" &&
   grep -q 'configure_target_rootless_podman_if_selected' "$f2fs_late" &&
   grep -q 'configure_target_gitlab_runner_if_selected' "$f2fs_late"; then
  pass "both storage-family late paths run GitLab runner staging after Podman staging"
else
  fail "both storage-family late paths run GitLab runner staging after Podman staging"
fi

if grep -q '^DIR_HOSTS_SERVICES="hosts/services"$' "$repo_env" &&
   grep -q '^DIR_HOOKS_SERVICES_GITLAB_RUNNER="hooks/services/gitlab-runner"$' "$repo_env" &&
   grep -q 'DIR_HOSTS_SERVICES) printf' "$common_lib" &&
   grep -q 'hooks/services/gitlab-runner|DIR_HOOKS_SERVICES_GITLAB_RUNNER|' "$common_lib"; then
  pass "repo path resolver exposes service env and GitLab Runner service asset roots"
else
  fail "repo path resolver exposes service env and GitLab Runner service asset roots"
fi

if grep -q '^GITLAB_RUNNER_APTLY_USERNAME="glab-aptly"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_DOCKER_USERNS_MODE="keep-id"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_CHANNELS="stable testing"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_CHANNEL_STABLE_KEEP_SNAPSHOTS="2"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_CHANNEL_TESTING_KEEP_SNAPSHOTS="3"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_CHANNEL_TESTING_MAX_AGE_DAYS="14"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_SBUILD_ARCH="amd64"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_SBUILD_SUITES="stable testing unstable"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_SBUILD_MIRROR="https://deb.debian.org/debian"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_SBUILD_TARBALL_DIR="/pool/cache/aptly/tools/sbuild"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_BUILD_USERNAME="glab-user"$' "$build_env" &&
   grep -q '^GITLAB_RUNNER_APTLY_NAME="aptly"$' "$aptly_env" &&
   grep -q '^GITLAB_RUNNER_BUILD_NAME="build"$' "$build_env" &&
   [ ! -e "$ROOT_DIR/d-i/debian/hosts/services/gitlab-runner/gitlab-runner-task.env" ]; then
  pass "runner env files define only the aptly and build runners and pin the managed sbuild settings"
else
  fail "runner env files define only the aptly and build runners and pin the managed sbuild settings"
fi

if grep -q '^GITLAB_RUNNER_STATE_BASE="/data/config/runners"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_USER_HOME_BASE="/data/services/usr"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_PODMAN_CONFIG_BASE="/data/config/podman"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_PODMAN_STATE_BASE="/pool/podman"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_CONFIG_GROUP="devops"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_CONTROL_DIR_MODE="0750"$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_CONTROL_FILE_MODE="0640"$' "$shared_env" &&
   grep -q '^GITLAB_PODMAN_USER_DOCKER_HOST="0"$' "$shared_env" &&
   grep -q '^GITLAB_PODMAN_USER_CONTAINER_HOST="0"$' "$shared_env" &&
   grep -q '^GITLAB_PODMAN_UNQUALIFIED_SEARCH_REGISTRIES="docker.io,ghcr.io,registry.gitlab.com"$' "$shared_env" &&
   grep -q '^GITLAB_PODMAN_TLS_ENABLE="0"$' "$shared_env" &&
   grep -q '^GITLAB_PODMAN_TLS_REGISTRIES=""$' "$shared_env" &&
   grep -q '^GITLAB_RUNNER_SERVICE_STABLE_SECONDS="3"$' "$shared_env" &&
   grep -q '^helm/cache$' "$shared_env" &&
   grep -q '^helm/config$' "$shared_env" &&
   grep -q '^helm/data$' "$shared_env" &&
   grep -q '^kaniko$' "$shared_env"; then
  pass "shared env centralizes persistent runner, Podman, and cache directory policy"
else
  fail "shared env centralizes persistent runner, Podman, and cache directory policy"
fi

if grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab-runner/gitlab-runner-shared.env)"' "$gitlab_late" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab-runner/gitlab-runner-aptly.env)"' "$gitlab_late" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab-runner/gitlab-runner-build.env)"' "$gitlab_late" &&
   ! grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab-runner/gitlab-runner-task.env)"' "$gitlab_late" &&
   grep -q 'target/usr/local/sbin/aptly-managed' "$gitlab_late" &&
   grep -q 'target/usr/local/sbin/aptly-bridge-processor' "$gitlab_late" &&
   grep -q 'target/usr/local/libexec/aptly-publish-managed' "$gitlab_late" &&
   grep -q 'target/pool/aptly/bin/aptly-bridge' "$gitlab_late" &&
   grep -q 'target/etc/systemd/system/aptly-bridge.service' "$gitlab_late" &&
   grep -q 'target/etc/systemd/system/aptly-bridge.path' "$gitlab_late" &&
   grep -q 'stage_target_helper_doc gitlab-runner.md gitlab-runner.md' "$gitlab_late" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOSTS_SERVICES gitlab-runner/README.md)" "${GITLAB_RUNNER_ENV_DIR}/README.md" 0644' "$gitlab_late" &&
   grep -q 'target_asset_assert_no_unresolved_installer_placeholders' "$gitlab_late" &&
   grep -q 'chown root:root "/target${GITLAB_RUNNER_ENV_DIR}/README.md"' "$gitlab_late" &&
   grep -q 'chown "root:${GITLAB_RUNNER_SHARED_GID}" "/target${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-build.env"' "$gitlab_late" &&
   grep -q 'gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-aptly.env" "$GITLAB_RUNNER_APTLY_GID" 640' "$gitlab_late" &&
   grep -q 'gitlab_runner_verify_target_env_path "${GITLAB_RUNNER_ENV_DIR}/gitlab-runner-build.env" "$GITLAB_RUNNER_SHARED_GID" 640' "$gitlab_late" &&
   grep -q 'legacy gitlab-runner-task.env must not remain staged' "$gitlab_late" &&
   grep -q 'gitlab_runner_verify_target_envs' "$gitlab_late" &&
   grep -q 'target/usr/local/sbin/gitlab-runner-managed' "$gitlab_late" &&
   grep -q '^- `/etc/default/gitlab-runner/README.md`$' "$service_readme" &&
   [ -r "$docs_index" ] &&
   [ -r "$gitlab_runner_doc" ]; then
  pass "late helper stages and verifies GitLab runner env files and README inside the managed env directory"
else
  fail "late helper stages and verifies GitLab runner env files and README inside the managed env directory"
fi

if grep -q '^GITLAB_PODMAN_USER_SHELL="/usr/sbin/nologin"$' "$shared_env" &&
   grep -q 'intentionally provisioned with' "$service_readme" &&
   grep -q '/usr/sbin/nologin' "$service_readme" &&
   grep -q 'Docker jobs run' "$service_readme" &&
   grep -q '/bin/bash' "$service_readme" &&
   grep -q 'sudo -iu glab-user' "$gitlab_runner_doc" &&
   grep -q 'expected to fail' "$gitlab_runner_doc"; then
  pass "runner docs keep the nologin service-account contract explicit and explain why shell-profile loading does not apply to the Docker executor path"
else
  fail "runner docs keep the nologin service-account contract explicit and explain why shell-profile loading does not apply to the Docker executor path"
fi

if ! grep -q '__INSTALLER_DIR_POOL_APTLY__' "$runtime_storage_tmpfiles" &&
   grep -q '^d /pool/aptly 0755 root root -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/.aptly 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/.managed 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/.managed/channels 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/secrets 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/queue/requests 03770 root __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/queue/results 03770 root __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d /pool/aptly/queue/processing 0700 root root -$' "$aptly_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__/__INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__/__INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__/tmp 0700 __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ __INSTALLER_GITLAB_RUNNER_APTLY_USERNAME__ -$' "$aptly_tmpfiles" &&
   ! grep -q '/runtime/run/networks/rootless-netns ' "$aptly_tmpfiles" &&
   ! grep -q '/gitlab-runner/tmp ' "$aptly_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__/__INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__ 0700 __INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__ __INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__/__INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__/tmp 0700 __INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__ __INSTALLER_GITLAB_RUNNER_BUILD_USERNAME__ -$' "$aptly_tmpfiles" &&
   grep -q '/pool/aptly:/pool/aptly:rw' "$aptly_env" &&
   grep -Fq 'exec "$bridge_bin" submit "$@"' "$aptly_wrapper" &&
   grep -Fq 'snapshot|repo|switch' "$aptly_bridge" &&
   grep -Fq 'PathExistsGlob=/pool/aptly/queue/requests/*.json' "$aptly_bridge_path" &&
   grep -q '^ExecStart=/usr/local/sbin/aptly-bridge-processor$' "$aptly_bridge_service" &&
   grep -Fq 'chown "${publish_user}:${publish_user}" "$env_file"' "$aptly_managed" &&
   grep -Fq 'runuser -u "$publish_user" -- bash -lc' "$aptly_managed" &&
   grep -Fq '/usr/local/sbin/aptly-managed "${managed_args[@]}"' "$aptly_bridge_processor" &&
   grep -Fq 'source /pool/aptly/bin/prepare-aptly-env.sh' "$aptly_managed" &&
   grep -Fq 'prepare_aptly_env' "$aptly_managed" &&
   grep -Fq 'APTLY_JOB_DIR' "$aptly_publish_helper" &&
   grep -Fq 'chown "${context_user}:${context_user}" "$config_path"' "$managed_helper" &&
   ! grep -q 'APTLY_CONFIG=/pool/aptly/.aptly.conf' "$managed_helper" &&
   ! grep -q 'R2_ACCESS_KEY_ID=$(runner_var' "$managed_helper"; then
  pass "aptly state stays on the glab-aptly account, its tmpfiles root no longer duplicates the shared roots file, and publish/signing is forced through the controlled host helper"
else
  fail "aptly state stays on the glab-aptly account, its tmpfiles root no longer duplicates the shared roots file, and publish/signing is forced through the controlled host helper"
fi

if grep -Fq 'configure_target_rootless_podman_without_podbin' "$gitlab_late" &&
   grep -q '^configure_target_rootless_podman_without_podbin() {$' "$podman_late" &&
   grep -q '^  PODMAN_PODBIN_ENABLE=0$' "$podman_late" &&
   grep -Fq 'preserved_groups=" ${allowed_groups} devops "' "$podman_late"; then
  pass "GitLab-managed Podman users skip podbin while keeping per-user linger units"
else
  fail "GitLab-managed Podman users skip podbin while keeping per-user linger units"
fi

if grep -q '^gitlab-runner$' "$security_script" &&
   grep -q 'git-server|gitlab-runner|grafana' "$security_script" &&
   grep -q 'gitlab_runner_service_is_selected' "$security_script" &&
   grep -q 'nftables_merge_selected_services "$effective_services" gitlab-runner' "$security_script" &&
   grep -q '^  name: gitlab-runner$' "$gitlab_nft_overlay" &&
   grep -q '^    allow_container_outbound: true$' "$gitlab_nft_overlay" &&
   grep -q '^    http_https:$' "$gitlab_nft_overlay" &&
   grep -q '^      - 443$' "$gitlab_nft_overlay"; then
  pass "GitLab runner selection auto-enables hardened nftables egress and Podman container outbound policy"
else
  fail "GitLab runner selection auto-enables hardened nftables egress and Podman container outbound policy"
fi

if grep -q '^Wants=podman.socket$' "$service_template" &&
   grep -q '^After=podman.socket$' "$service_template" &&
   grep -q '^StartLimitIntervalSec=5min$' "$service_template" &&
   grep -q '^StartLimitBurst=3$' "$service_template" &&
   grep -q '^ExecStartPre=/usr/local/sbin/gitlab-runner-managed --user __INSTALLER_GITLAB_RUNNER_USER__ preflight$' "$service_template" &&
   ! grep -q '^Environment=DOCKER_HOST=' "$service_template" &&
   ! grep -q '^Environment=CONTAINER_HOST=' "$service_template" &&
   grep -q '^Restart=on-failure$' "$service_template" &&
   grep -q '^RestartSec=15s$' "$service_template" &&
   grep -q '^ProtectSystem=strict$' "$service_template" &&
   grep -q '^ReadWritePaths=__INSTALLER_GITLAB_RUNNER_READ_WRITE_PATHS__$' "$service_template" &&
   grep -Fq 'system_id_path="${base_dir}/${GITLAB_RUNNER_SYSTEM_ID_BASENAME}"' "$gitlab_late" &&
   grep -Fq 'podman_state_root="${GITLAB_RUNNER_PODMAN_STATE_BASE}/${runner_user}"' "$gitlab_late" &&
   grep -Fq 'podman_tmp_root="${GITLAB_RUNNER_PODMAN_TMP_BASE}/${runner_user}"' "$gitlab_late" &&
   grep -Fq 'tmp_root="/run/user/${runner_uid}/gitlab-runner"' "$gitlab_late" &&
   grep -Fq 'read_write_paths="${read_write_paths} ${podman_state_root} ${podman_tmp_root} ${tmp_root} ${buildah_tmpdir} ${system_id_path}"' "$gitlab_late" &&
   grep -Fq '"${GITLAB_RUNNER_PODMAN_CONFIG_BASE}/${GITLAB_RUNNER_APTLY_USERNAME}"' "$gitlab_late" &&
   grep -Fq '"${GITLAB_RUNNER_PODMAN_CONFIG_BASE}/${GITLAB_RUNNER_BUILD_USERNAME}"' "$gitlab_late" &&
   grep -Fq 'podman_state_root="${GITLAB_RUNNER_PODMAN_STATE_BASE}/${runner_user}"' "$gitlab_late"; then
  pass "user service template keeps Podman control-plane access while leaving the managed Podman state roots, Buildah tmpdir, and runner system-id file writable inside ExecStartPre"
else
  fail "user service template keeps Podman control-plane access while leaving the managed Podman state roots, Buildah tmpdir, and runner system-id file writable inside ExecStartPre"
fi

if grep -q 'context_runner_ids=(APTLY)' "$managed_helper" &&
   grep -q '^load_runner_env_if_present() {$' "$managed_helper" &&
   grep -Fq 'context_runner_ids=(BUILD)' "$managed_helper" &&
   ! grep -Fq 'context_runner_ids+=(TASK)' "$managed_helper" &&
   grep -q 'context_docker_host="unix:///run/user/${context_uid}/podman/podman.sock"' "$managed_helper" &&
   grep -q 'context_system_id_file="${context_base_dir}/${GITLAB_RUNNER_SYSTEM_ID_BASENAME:-.runner_system_id}"' "$managed_helper" &&
   grep -q 'context_podman_tmp_root="${GITLAB_RUNNER_PODMAN_TMP_BASE}/${context_user}"' "$managed_helper" &&
   grep -q 'context_runtime_root="/run/user/${context_uid}/gitlab-runner"' "$managed_helper" &&
   grep -q 'context_podman_runtime_root="/run/user/${context_uid}"' "$managed_helper" &&
   grep -q 'context_podman_tmpdir="${context_podman_runtime_libpod_dir}/tmp"' "$managed_helper" &&
   grep -q 'context_podman_runroot="${context_podman_runtime_root}/run"' "$managed_helper" &&
   grep -q 'context_podman_rootless_netns_dir="${context_podman_runroot_networks_dir}/rootless-netns"' "$managed_helper" &&
   grep -q '^preflight_executor() {$' "$managed_helper" &&
   grep -Fq "run_podman_as_context_user info --format '{{.Host.Security.Rootless}}|{{.Host.NetworkBackend}}'" "$managed_helper" &&
   grep -q 'FF_NETWORK_PER_BUILD = true' "$managed_helper" &&
   grep -Fq 'f"TMPDIR={container_tmp_dir}"' "$managed_helper" &&
   grep -Fq '"/tmp",' "$managed_helper" &&
   grep -Fq 'userns_mode = {toml_string(runner[' "$managed_helper" &&
   grep -Fq 'DEBIAN_SBUILD_TARBALL_DIR=/cache/sbuild' "$managed_helper" &&
   grep -q 'host = {toml_string(globals_cfg' "$managed_helper" &&
   ! grep -Fq 'DOCKER_HOST={docker_host}' "$managed_helper" &&
   ! grep -Fq 'CONTAINER_HOST={container_host}' "$managed_helper" &&
   ! grep -Fq 'docker_socket = docker_host.removeprefix("unix://")' "$managed_helper" &&
   ! grep -Fq 'f"{tmp_dir}:{tmp_dir}:rw"' "$managed_helper" &&
   ! grep -Fq 'docker.sock' "$managed_helper"; then
  pass "managed helper renders one aptly runner and one shared build runner over Podman while checking rootless runtime paths under /run/user and storage/image temp under /pool"
else
  fail "managed helper renders one aptly runner and one shared build runner over Podman while checking rootless runtime paths under /run/user and storage/image temp under /pool"
fi

if grep -q 'GITLAB_RUNNER_CACHE_DIR_NAMES' "$managed_helper" &&
   grep -q 'validate_cache_dir_name' "$managed_helper" &&
   ! grep -q '^cache_dir_names=(' "$managed_helper" &&
   grep -q 'IFS=: read -r _passwd_name' "$managed_helper" &&
   ! grep -q 'run_as_context_user test -w' "$managed_helper" &&
   ! grep -q 'run_as_context_user test -x' "$managed_helper" &&
   grep -q 'IFS=: read -r _passwd_name' "$operator_helper"; then
  pass "installed Bash helpers avoid duplicated cache tables, repeated passwd parsing subprocesses, and per-path runuser permission probes"
else
  fail "installed Bash helpers avoid duplicated cache tables, repeated passwd parsing subprocesses, and per-path runuser permission probes"
fi

if grep -q '^set_return_file_cleanup() {$' "$managed_helper" &&
   grep -q 'set_return_file_cleanup "\$spec_path"' "$managed_helper" &&
   grep -q 'set_return_file_cleanup "\$spec_probe"' "$managed_helper" &&
   grep -q 'context_job_home="\${context_base_dir}/home"' "$managed_helper" &&
   grep -q '"\$context_job_home"' "$managed_helper" &&
   grep -q 'HOME="\$context_home"' "$managed_helper" &&
   grep -q 'XDG_CONFIG_HOME="\$context_xdg_config_home"' "$managed_helper" &&
   grep -q 'XDG_STATE_HOME="\$context_xdg_state_home"' "$managed_helper" &&
   grep -q 'emit_spec_line "\$spec_path" global.job_home "\$context_job_home"' "$managed_helper" &&
   grep -q '^  preflight_executor$' "$managed_helper" &&
   grep -q '^  ensure_images$' "$managed_helper" &&
   grep -q '^build_runner_image_from_containerfile() {$' "$managed_helper" &&
   grep -q '^prepare_containerfile_build_context() {$' "$managed_helper" &&
   grep -q '^ensure_aptly_sbuild_assets() {$' "$managed_helper" &&
   grep -q 'mmdebstrap' "$managed_helper" &&
   grep -q 'containerfile-context\.' "$managed_helper" &&
   grep -q 'run_podman_as_context_user build --pull=missing --tag "\$image_ref" -f "\$build_containerfile" "\$build_context"' "$managed_helper" &&
   grep -q 'no active runner tokens found for ${context_user}' "$managed_helper" &&
   grep -q 'completed once for ${context_user}' "$managed_helper"; then
  pass "managed helper self-clears RETURN traps, reports missing tokens clearly, and keeps once on the public preflight and ensure-images path"
else
  fail "managed helper self-clears RETURN traps, reports missing tokens clearly, and keeps once on the public preflight and ensure-images path"
fi

if grep -q '^report_success() {$' "$operator_helper" &&
   grep -q '^gitlab_runner_managed_subcommand() {$' "$operator_helper" &&
   grep -Fq 'gitlab-runner-managed ${managed_subcommand:-command} succeeded for ${context_user}' "$operator_helper"; then
  pass "operator helper emits an explicit success footer for the real gitlab-runner-managed subcommand"
else
  fail "operator helper emits an explicit success footer for the real gitlab-runner-managed subcommand"
fi

if grep -q '^reconcile_runner_service() {$' "$managed_helper" &&
   grep -q '^reconcile_podman_service() {$' "$managed_helper" &&
   grep -Fq 'systemctl --user reset-failed podman.service' "$managed_helper" &&
   grep -Fq 'systemctl --user reset-failed podman.socket' "$managed_helper" &&
   grep -Fq 'systemctl --user restart podman.socket' "$managed_helper" &&
   grep -Fq 'systemctl --user enable gitlab-runner.service' "$managed_helper" &&
   grep -Fq 'systemctl --user reset-failed gitlab-runner.service' "$managed_helper" &&
   grep -Fq 'systemctl --user restart gitlab-runner.service' "$managed_helper" &&
   grep -Fq 'systemctl --user start gitlab-runner.service' "$managed_helper" &&
   grep -Fq 'restarted podman.socket for ${context_user}' "$managed_helper" &&
   grep -Fq 'restarted gitlab-runner.service for ${context_user}' "$managed_helper" &&
   ! grep -Fq 'podman_install_symlink_with_backup "/target${GITLAB_RUNNER_HOME_WANTS_FILE}"' "$gitlab_late" &&
   grep -Fq 'GitLab runner unit must not be enabled before first successful once' "$gitlab_late" &&
   grep -q 'does not enable it until `gitlab-runner-managed once` has rendered a valid' "$service_readme" &&
   grep -q 'does not enable it until `once` succeeds' "$gitlab_runner_doc" &&
   grep -q 'unit only restarts on failure and systemd stops retrying after the bounded' "$service_readme" &&
   grep -q 'unit restarts only on failure and uses bounded systemd start limits' "$gitlab_runner_doc"; then
  pass "managed helper refreshes the Podman and runner user services on successful once and the unit no longer retries forever after enablement"
else
  fail "managed helper refreshes the Podman and runner user services on successful once and the unit no longer retries forever after enablement"
fi

if grep -q 'secret file path does not exist' "$managed_helper" &&
   grep -q 'secret file path does not exist' "$aptly_prepare" &&
   grep -q 'r2_access_key="$(aptly_trim "$(aptly_read_secret_value "${R2_ACCESS_KEY_ID:-}")")"' "$aptly_prepare" &&
   grep -q 'r2_secret_key="$(aptly_trim "$(aptly_read_secret_value "${R2_SECRET_ACCESS_KEY:-}")")"' "$aptly_prepare" &&
   grep -q 'AWS_ACCESS_KEY_ID="$r2_access_key"' "$aptly_prepare" &&
   grep -q 'AWS_SECRET_ACCESS_KEY="$r2_secret_key"' "$aptly_prepare"; then
  pass "secret path handling fails closed and supports file-backed R2 credentials"
else
  fail "secret path handling fails closed and supports file-backed R2 credentials"
fi

if grep -q '^FROM docker.io/library/debian:trixie-slim$' "$aptly_containerfile" &&
   grep -q 'aptly' "$aptly_containerfile" &&
   grep -q 'python3' "$aptly_containerfile" &&
   grep -q '"S3PublishEndpoints"' "$aptly_template" &&
   grep -q 'require_r2_publish_env' "$aptly_wrapper"; then
  pass "Aptly image, config template, and wrapper support package publishing without baking secrets"
else
  fail "Aptly image, config template, and wrapper support package publishing without baking secrets"
fi

[ "$FAIL_COUNT" -eq 0 ]
