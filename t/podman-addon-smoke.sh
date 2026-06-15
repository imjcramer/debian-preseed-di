#!/bin/sh
# shellcheck disable=SC2016
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=16
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

podman_class="$ROOT_DIR/d-i/debian/classes/class-addon/podman.cfg"
classes_conf="$ROOT_DIR/d-i/debian/classes/CLASSES.conf"
desktop_env="$ROOT_DIR/d-i/debian/hosts/shared/desktop.env"
server_env="$ROOT_DIR/d-i/debian/hosts/shared/server.env"
helper="$ROOT_DIR/d-i/debian/scripts/late/podman.sh"
shared_loader="$ROOT_DIR/d-i/debian/hooks/shared/late_command.sh"
dispatch_script="$ROOT_DIR/d-i/debian/scripts/late/dispatch.sh"
quadlet_dropin="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/containers/systemd/container.d/10-podman-managed.conf.tmpl"
podman_slice="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman-rootless.slice.tmpl"
podman_service_dropin="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman.service.d/10-podman-service-managed.conf"
buildah_env_service="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/buildah-env.service.tmpl"
podman_env_service="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/systemd/user/podman-api-env.service.tmpl"
podman_env_file="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/rootless/environment.d/90-podman-api.conf.tmpl"
podman_linger_unit="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/podman-rootless-linger.service.tmpl"
podman_sysctl="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/sysctl.d/90-podman-rootless.conf.tmpl"
podbin_wrapper="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/sbin/podbin.tmpl"
podbin_default="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/default/podbin.tmpl"
podbin_template_dir="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/podbin"
podbin_runtime_containerfile="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/Containerfile.tmpl"
podbin_runtime_entrypoint="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/entrypoint.sh.tmpl"
podbin_runtime_sshd="$ROOT_DIR/d-i/debian/hooks/shared/target/data/config/podman/templates/podbin/images/runtime/sshd_config.tmpl"
podbin_doc="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/podbin.md"
account_sudoers="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/sudoers.d/account.tmpl"
desktop_podman_policy=$(grep '^PODMAN_' "$desktop_env")
server_podman_policy=$(grep '^PODMAN_' "$server_env")

if grep -Eq '^d-i pkgsel/include string .*podman .*buildah .*golang-github-containers-common .*conmon .*crun .*uidmap .*netavark .*aardvark-dns .*passt .*slirp4netns .*fuse-overlayfs .*catatonit .*containernetworking-plugins .*openssh-client .*dbus-user-session$' "$podman_class"; then
  pass "podman addon fragment installs the requested rootless package baseline"
else
  fail "podman addon fragment installs the requested rootless package baseline"
fi

if grep -q '^\[class\.addon\.podman\]$' "$classes_conf" &&
   ! grep -q '^late_helper=podman$' "$classes_conf"; then
  pass "podman addon is package-selected directly while the shared late module handles target staging"
else
  fail "podman addon is package-selected directly while the shared late module handles target staging"
fi

if [ "$desktop_podman_policy" = "$server_podman_policy" ] &&
   grep -q '^PODMAN_USER="podsvc"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_HOME="/data/accounts/podman"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_SHELL="/usr/sbin/nologin"$' "$desktop_env" &&
   grep -q '^PODMAN_USER_LOCK=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_STRIP_GROUPS=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_LINGER=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_DOCKER_HOST=0$' "$desktop_env" &&
   grep -q '^PODMAN_USER_CONTAINER_HOST=0$' "$desktop_env" &&
   grep -q '^PODMAN_SERVICE_SLICE_ENABLE=1$' "$desktop_env" &&
   grep -q '^PODMAN_ENABLE_ROOTLESS_SYSCTL=1$' "$desktop_env" &&
   grep -q '^PODMAN_USER_CONFIG_BASE="/data/config/podman"$' "$desktop_env" &&
   grep -q '^PODMAN_ROOTLESS_STATE_BASE="/pool/podman"$' "$desktop_env" &&
   ! grep -q 'glab-aptly' "$desktop_env" &&
   ! grep -q 'glab-user' "$desktop_env" &&
   ! grep -q '^PODMAN_APT_' "$desktop_env" &&
   ! grep -q '^PODMAN_GLOBAL_' "$desktop_env"; then
  pass "desktop and server shared podman policy files mirror the hardened podsvc service-account contract"
else
  fail "desktop and server shared podman policy files mirror the hardened podsvc service-account contract"
fi

if grep -q "podman \\\\" "$shared_loader" &&
   grep -q 'dbus-broker podman gitlab-runner zram-swap' "$dispatch_script"; then
  pass "late command loader wires the shared podman module through both loader paths"
else
  fail "late command loader wires the shared podman module through both loader paths"
fi

if grep -q 'PODMAN_SERVICE_USER=$PODMAN_USER' "$helper" &&
   grep -q 'refusing to reuse login-class account for Podman service user' "$helper" &&
   grep -q 'PODMAN_USER_HOME must not be a login home path' "$helper" &&
   grep -q 'configure_target_rootless_podman_if_selected()' "$helper" &&
   grep -q 'podman_ensure_service_subids' "$helper" &&
   grep -q ': "${PODMAN_USER_DOCKER_HOST:=1}"' "$helper" &&
   grep -q ': "${PODMAN_USER_CONTAINER_HOST:=1}"' "$helper" &&
   grep -q 'podman_chown_target_tree()' "$helper" &&
   grep -q 'usermod -p "!" -- "$service_user"' "$helper" &&
   grep -q '/etc/shadow' "$helper" &&
   ! grep -q 'glab-aptly' "$helper" &&
   ! grep -q 'glab-user' "$helper" &&
   ! grep -q 'passwd -l "$service_user"' "$helper" &&
   ! grep -q 'passwd -S "$service_user"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR="${PODMAN_ROOTLESS_CONFIG_ROOT}/containers"' "$helper" &&
   grep -q 'PODMAN_ROOTLESS_QUADLET_DIR="${PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR}/systemd"' "$helper" &&
   grep -q 'server role requires PODMAN_USER_LINGER=1' "$helper" &&
   grep -q 'PODMAN_EFFECTIVE_USER_DAEMON=1' "$helper" &&
   grep -q 'PODMAN_EFFECTIVE_USER_API_ENV=1' "$helper" &&
   grep -q 'Podman addon must not stage rootful /etc/containers/containers.conf' "$helper"; then
  pass "podman helper enforces the hardened service user, unique subids, managed roots, and server socket policy"
else
  fail "podman helper enforces the hardened service user, unique subids, managed roots, and server socket policy"
fi

if grep -q 'containers/systemd/container.d/10-podman-managed.conf.tmpl' "$helper" &&
   grep -q 'podman-rootless.slice.tmpl' "$helper" &&
   grep -q 'podman-api-env.service.tmpl' "$helper" &&
   grep -q '90-podman-api.conf.tmpl' "$helper"; then
  pass "podman helper stages Quadlet and user-manager assets from managed target templates"
else
  fail "podman helper stages Quadlet and user-manager assets from managed target templates"
fi

if grep -q '^podman_render_registries_conf_file() {$' "$helper" &&
   grep -q 'podman_render_registries_conf_file "/target${PODMAN_ROOTLESS_CONTAINERS_CONFIG_DIR}/registries.conf"' "$helper" &&
   ! grep -q 'registries.conf.tmpl' "$helper"; then
  pass "podman helper renders registries.conf directly instead of shipping unresolved multiline placeholders"
else
  fail "podman helper renders registries.conf directly instead of shipping unresolved multiline placeholders"
fi

if grep -q '^\[Service\]$' "$quadlet_dropin" &&
   grep -q '^TimeoutStartSec=900$' "$quadlet_dropin" &&
   grep -q '__INSTALLER_PODMAN_SERVICE_SLICE_LINE__' "$quadlet_dropin"; then
  pass "quadlet container drop-in applies managed startup and slice policy"
else
  fail "quadlet container drop-in applies managed startup and slice policy"
fi

if grep -q '^CPUWeight=__INSTALLER_PODMAN_SERVICE_SLICE_CPU_WEIGHT__$' "$podman_slice" &&
   grep -q '^IOWeight=__INSTALLER_PODMAN_SERVICE_SLICE_IO_WEIGHT__$' "$podman_slice" &&
   grep -q '^TasksMax=__INSTALLER_PODMAN_SERVICE_SLICE_TASKS_MAX__$' "$podman_slice" &&
   grep -q '^Delegate=true$' "$podman_service_dropin" &&
   grep -q '^UnsetEnvironment=DOCKER_HOST CONTAINER_HOST$' "$podman_service_dropin" &&
   grep -q '^ExecStart=$' "$podman_service_dropin" &&
   grep -q '^ExecStart=/usr/bin/podman \$LOGGING system service --time=0$' "$podman_service_dropin" &&
   grep -q '__INSTALLER_PODMAN_SERVICE_SLICE_LINE__' "$podman_service_dropin"; then
  pass "podman service limits are bound to a dedicated rootless slice and the API backend is pinned without an idle timeout"
else
  fail "podman service limits are bound to a dedicated rootless slice and the API backend is pinned without an idle timeout"
fi

if grep -q '^__INSTALLER_PODMAN_API_SERVICE_ENVIRONMENT_LINES__$' "$podman_env_service" &&
   grep -q '^Description=Managed rootless Podman API environment for __INSTALLER_PODMAN_SERVICE_USER__$' "$podman_env_service" &&
   grep -q '^ExecStart=/usr/bin/systemctl --user set-environment __INSTALLER_PODMAN_API_SET_ENV_ARGS__$' "$podman_env_service" &&
   grep -q '^ExecStop=/usr/bin/systemctl --user unset-environment __INSTALLER_PODMAN_API_UNSET_ENV_NAMES__$' "$podman_env_service" &&
   grep -q '^ExecStart=/usr/bin/systemctl --user set-environment BUILDAH_ISOLATION=__INSTALLER_PODMAN_ROOTLESS_BUILDAH_ISOLATION__ BUILDAH_TMPDIR=__INSTALLER_PODMAN_ROOTLESS_BUILDAH_TMPDIR__$' "$buildah_env_service" &&
   ! grep -q '/bin/sh -lc' "$podman_env_service" &&
   ! grep -q '/bin/sh -lc' "$buildah_env_service" &&
   grep -q '^__INSTALLER_PODMAN_API_ENV_FILE_LINES__$' "$podman_env_file"; then
  pass "server socket compatibility exports both DOCKER_HOST and CONTAINER_HOST without shell wrappers"
else
  fail "server socket compatibility exports both DOCKER_HOST and CONTAINER_HOST without shell wrappers"
fi

if grep -q '^kernel\.unprivileged_userns_clone=__INSTALLER_PODMAN_ROOTLESS_USERNS_CLONE__$' "$podman_sysctl" &&
   grep -q '^user\.max_user_namespaces=__INSTALLER_PODMAN_ROOTLESS_MAX_USER_NAMESPACES__$' "$podman_sysctl" &&
   grep -q '^ExecStart=/usr/bin/loginctl enable-linger __INSTALLER_PODMAN_SERVICE_USER__$' "$podman_linger_unit" &&
   grep -q 'runuser -u __INSTALLER_PODMAN_SERVICE_USER__ -- /usr/bin/env HOME=__INSTALLER_PODMAN_SERVICE_HOME__ XDG_RUNTIME_DIR=/run/user/__INSTALLER_PODMAN_SERVICE_UID__' "$podman_linger_unit" &&
   grep -q '/usr/bin/systemctl --user start __INSTALLER_PODMAN_API_START_UNITS__' "$podman_linger_unit" &&
   grep -q '^ConditionPathExists=!__INSTALLER_PODMAN_LINGER_MARKER__$' "$podman_linger_unit"; then
  pass "server lingering and rootless userns tuning are staged from managed target templates"
else
  fail "server lingering and rootless userns tuning are staged from managed target templates"
fi

if grep -q '^PODBIN_KEY_DIR="__INSTALLER_PODBIN_KEY_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_KEY_NAME="__INSTALLER_PODBIN_KEY_NAME__"$' "$podbin_default" &&
   grep -q '^PODBIN_TEMPLATE_DIR="__INSTALLER_PODBIN_TEMPLATE_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_SERVICE_USER="__INSTALLER_PODBIN_SERVICE_USER__"$' "$podbin_default" &&
   grep -q '^PODBIN_DEFAULT_IMAGE="__INSTALLER_PODBIN_DEFAULT_IMAGE__"$' "$podbin_default" &&
   grep -q '^PODBIN_RUNTIME_USER_NAME="__INSTALLER_PODBIN_RUNTIME_USER_NAME__"$' "$podbin_default" &&
   grep -q '^PODBIN_RUNTIME_AUTH_KEYS_DIR="__INSTALLER_PODBIN_RUNTIME_AUTH_KEYS_DIR__"$' "$podbin_default" &&
   grep -q '^PODBIN_KNOWN_HOSTS_FILE="__INSTALLER_PODBIN_KNOWN_HOSTS_FILE__"$' "$podbin_default" &&
   grep -q ': "${PODBIN_KEY_DIR:=/data/pki/ssh/.keys}"' "$helper" &&
   grep -q ': "${PODBIN_KEY_NAME:=podbin_ed25519}"' "$helper" &&
   grep -q ': "${PODBIN_SERVICE_USER:=$PODMAN_SERVICE_USER}"' "$helper" &&
   grep -q ': "${PODBIN_DEFAULT_IMAGE:=localhost/podbin-runtime:trixie}"' "$helper" &&
   grep -q ': "${PODBIN_RUNTIME_USER_NAME:=poduser}"' "$helper" &&
   grep -q ': "${PODBIN_DEFAULT_CONTAINER_SSH_USER:=$PODBIN_RUNTIME_USER_NAME}"' "$helper" &&
   grep -q 'PODBIN_TEMPLATE_DIR=$PODBIN_TEMPLATE_DIR' "$helper" &&
   grep -q 'stage_target_helper_doc podbin.md podbin.md' "$helper" &&
   [ -r "$podbin_doc" ] &&
   grep -q '/usr/local/sbin/podbin --ensure-keypair _' "$helper"; then
  pass "podbin defaults render the managed non-root image and host SSH policy through staged target assets"
else
  fail "podbin defaults render the managed non-root image and host SSH policy through staged target assets"
fi

if [ -r "$podbin_wrapper" ] &&
   grep -q 'Usage:' "$podbin_wrapper" &&
   grep -q -- '--create-user' "$podbin_wrapper" &&
   grep -q -- '--create-container' "$podbin_wrapper" &&
   grep -q -- '--delete-container' "$podbin_wrapper" &&
   grep -q -- '--start-container' "$podbin_wrapper" &&
   grep -q -- '--connect-container' "$podbin_wrapper" &&
   grep -q -- '--open-container' "$podbin_wrapper" &&
   grep -q '/data/docs/podbin.md' "$podbin_wrapper" &&
   grep -q 'PODBIN_PORT_SCAN_START' "$podbin_wrapper" &&
   grep -q 'require_high_port "host SSH port"' "$podbin_wrapper" &&
   grep -q 'refusing reserved Podman service account name' "$podbin_wrapper" &&
   grep -q 'PODBIN_USER_MANAGER_READY_UIDS' "$podbin_wrapper" &&
   grep -q 'ensure_runtime_image()' "$podbin_wrapper" &&
   grep -q 'ensure_known_hosts_file()' "$podbin_wrapper" &&
   grep -q ': "${PODBIN_RUNTIME_USER_NAME:=poduser}"' "$podbin_wrapper" &&
   grep -q ': "${PODBIN_DEFAULT_CONTAINER_SSH_USER:=$PODBIN_RUNTIME_USER_NAME}"' "$podbin_wrapper" &&
   grep -q 'podman exec --user "${PODBIN_RUNTIME_USER_UID}:${PODBIN_RUNTIME_USER_GID}"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container SSH user"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container authorized_keys directory"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container shell"' "$podbin_wrapper" &&
   ! grep -q 'prompt "Container runtime user uid' "$podbin_wrapper" &&
   ! grep -q 'validate_container_user()' "$podbin_wrapper" &&
   ! grep -q 'PODBIN_RUN_USER' "$podbin_wrapper" &&
   ! grep -q -- '--user 0' "$podbin_wrapper"; then
  pass "podbin wrapper exposes the lifecycle controls while fixing the interactive contract to the managed non-root runtime user"
else
  fail "podbin wrapper exposes the lifecycle controls while fixing the interactive contract to the managed non-root runtime user"
fi

if [ -r "$podbin_template_dir/containers.conf.tmpl" ] &&
   [ -r "$podbin_template_dir/storage.conf.tmpl" ] &&
   [ -r "$podbin_template_dir/registries.conf" ] &&
   [ -r "$podbin_template_dir/systemd/user/podbin-rootless.slice" ] &&
   [ -r "$podbin_template_dir/systemd/users/container.d/10-podbin-managed.conf" ] &&
   [ -r "$podbin_template_dir/systemd/users/container.container.tmpl" ] &&
   [ -r "$podbin_template_dir/metadata.env.tmpl" ] &&
   grep -q 'data/config/podman/templates/podbin/containers.conf.tmpl' "$helper" &&
   grep -q 'install_template containers.conf.tmpl' "$podbin_wrapper" &&
   grep -q '^User=__PODBIN_RUNTIME_USER_UID__:__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/tmp:rw,mode=1777$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/run/sshd:rw,mode=0755,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=/var/tmp:rw,mode=1777$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=__PODBIN_RUNTIME_USER_HOME__:rw,mode=0700,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   grep -q '^Tmpfs=__PODBIN_RUNTIME_WORKDIR__:rw,mode=0755,uid=__PODBIN_RUNTIME_USER_UID__,gid=__PODBIN_RUNTIME_USER_GID__$' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   ! grep -q '^AddCapability=' "$podbin_template_dir/systemd/users/container.container.tmpl" &&
   ! grep -q 'cat >.*containers.conf' "$podbin_wrapper" &&
   ! grep -q 'cat >.*storage.conf' "$podbin_wrapper" &&
   ! grep -q 'cat >.*container.*[.]container' "$podbin_wrapper"; then
  pass "podbin renders managed config exclusively from shared target templates"
else
  fail "podbin renders managed config exclusively from shared target templates"
fi

if [ -r "$podbin_runtime_containerfile" ] &&
   [ -r "$podbin_runtime_entrypoint" ] &&
   [ -r "$podbin_runtime_sshd" ] &&
   grep -q '^FROM docker.io/library/debian:trixie-slim$' "$podbin_runtime_containerfile" &&
   grep -q 'openssh-server' "$podbin_runtime_containerfile" &&
   grep -q '__INSTALLER_PODBIN_RUNTIME_USER_NAME__' "$podbin_runtime_containerfile" &&
   grep -q '__INSTALLER_PODBIN_RUNTIME_AUTH_KEYS_DIR__' "$podbin_runtime_containerfile" &&
   grep -q '^USER __INSTALLER_PODBIN_RUNTIME_USER_UID__:__INSTALLER_PODBIN_RUNTIME_USER_GID__$' "$podbin_runtime_containerfile" &&
   grep -q '^WORKDIR __INSTALLER_PODBIN_RUNTIME_WORKDIR__$' "$podbin_runtime_containerfile" &&
   grep -q 'chown __INSTALLER_PODBIN_RUNTIME_USER_UID__:__INSTALLER_PODBIN_RUNTIME_USER_GID__ /etc/ssh/ssh_host_\*_key' "$podbin_runtime_containerfile" &&
   grep -q 'COPY entrypoint.sh /usr/local/bin/podbin-entrypoint' "$podbin_runtime_containerfile" &&
   grep -q 'chmod 0755 /usr/local/bin/podbin-entrypoint' "$podbin_runtime_containerfile" &&
   grep -q 'CMD \["/usr/local/bin/podbin-entrypoint"\]' "$podbin_runtime_containerfile" &&
   grep -q '^install -d -m 0755 /run/sshd$' "$podbin_runtime_entrypoint" &&
   grep -q '^exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config$' "$podbin_runtime_entrypoint" &&
   grep -q '^PidFile none$' "$podbin_runtime_sshd" &&
   grep -q '^PermitRootLogin no$' "$podbin_runtime_sshd" &&
   grep -q '^AllowUsers __INSTALLER_PODBIN_RUNTIME_USER_NAME__$' "$podbin_runtime_sshd" &&
   grep -q '^PasswordAuthentication no$' "$podbin_runtime_sshd" &&
   grep -q '^AuthorizedKeysFile .ssh/authorized_keys$' "$podbin_runtime_sshd" &&
   ! grep -q '__PODBIN_' "$podbin_runtime_containerfile" &&
   ! grep -q '__PODBIN_' "$podbin_runtime_sshd"; then
  pass "podbin stages a managed runtime image with a fixed non-root SSH user and root login disabled"
else
  fail "podbin stages a managed runtime image with a fixed non-root SSH user and root login disabled"
fi

if grep -Fq 'Cmnd_Alias PODBIN_DAILY_OPERATIONS' "$account_sudoers" &&
   grep -q '/usr/local/sbin/podbin --start-container \*' "$account_sudoers" &&
   grep -q '/usr/local/sbin/podbin --connect-container \*' "$account_sudoers" &&
   grep -q 'NOPASSWD: READONLY_SYSTEM_INSPECTION, PODBIN_DAILY_OPERATIONS' "$account_sudoers" &&
   ! grep -q '/usr/local/sbin/podbin --create-container \*' "$account_sudoers" &&
   ! grep -q '/usr/local/sbin/podbin --open-container \*' "$account_sudoers"; then
  pass "daily-account sudoers delegate only podbin start and connect without widening passwordless create or open access"
else
  fail "daily-account sudoers delegate only podbin start and connect without widening passwordless create or open access"
fi

[ "$FAIL_COUNT" -eq 0 ]
