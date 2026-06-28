#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/late-policy-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=30
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

common_lib="$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
if grep -Fq 'live_log_max_bytes=${INSTALLER_LIVE_LOG_MAX_BYTES:-4194304}' "$common_lib" &&
   grep -Fq "printf '%s\\n' \"\$live_log_max_bytes\"" "$common_lib" &&
   ! grep -Fq "printf '%s\\n' \"\$INSTALLER_LIVE_LOG_MAX_BYTES\"" "$common_lib"; then
  pass "installer live-log byte limit handles unset values under set -u"
else
  fail "installer live-log byte limit handles unset values under set -u"
fi

runtime_env="$ROOT_DIR/d-i/debian/hosts/shared/runtime.env"
if grep -q '^DIR_POLKIT_LOCAL_RULES_D=' "$runtime_env" &&
   grep -q '^DIR_POLKIT_RUNTIME_RULES_D=' "$runtime_env" &&
   grep -q '^DIR_DBUS_SESSION_SERVICES=' "$runtime_env" &&
   grep -q '^DIR_DBUS_LOCAL_SESSION_SERVICES=' "$runtime_env" &&
   ! grep -q '^POLKIT_MANAGED_RULE_FILES=' "$runtime_env"; then
  pass "runtime env defines shared polkit and dbus service directories"
else
  fail "runtime env defines shared polkit and dbus service directories"
fi

polkit_tmpfiles="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/tmpfiles.d/70-polkit-runtime.conf"
if grep -q '^d __INSTALLER_DIR_POLKIT_RUNTIME_RULES_D__ 0755 root root -$' "$polkit_tmpfiles" &&
   grep -q '^d __INSTALLER_DIR_POLKIT_LOCAL_RULES_D__ 0755 root root -$' "$polkit_tmpfiles"; then
  pass "polkit tmpfiles file renders runtime path placeholders"
else
  fail "polkit tmpfiles file renders runtime path placeholders"
fi

polkit_rules_ok=true
for polkit_rule in \
  05-active-local-gate.rules \
  10-pkexec.rules \
  20-login1-power.rules \
  40-networkmanager.rules \
  50-usb-policy.rules \
  55-software-management.rules \
  60-system-services-identity.rules \
  70-hardware-peripherals.rules
do
  polkit_rule_path="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/polkit-1/rules.d/$polkit_rule"
  if ! grep -q 'subject.active !== true' "$polkit_rule_path" ||
     ! grep -q 'typeof subject.seat === "string"' "$polkit_rule_path"; then
    polkit_rules_ok=false
    break
  fi
done
if [ "$polkit_rules_ok" = true ]; then
  pass "managed polkit rules accept active logind seat sessions for Labwc pkexec prompts"
else
  fail "managed polkit rules accept active logind seat sessions for Labwc pkexec prompts"
fi

account_script="$ROOT_DIR/d-i/debian/scripts/late/account.sh"
if grep -q 'account_polkit_managed_rule_files()' "$account_script" &&
   grep -q 'render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/70-polkit-runtime.conf)"' "$account_script" &&
   grep -q 'DIR_POLKIT_LOCAL_RULES_D must be set' "$account_script" &&
   grep -q 'DIR_POLKIT_RUNTIME_RULES_D must be set' "$account_script"; then
  pass "account late hook stages the managed polkit tmpfiles policy"
else
  fail "account late hook stages the managed polkit tmpfiles policy"
fi

shared_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/skel/.profile"
shared_bash_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/skel/.bash_profile"
shared_bashrc="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/skel/.bashrc"
if [ -r "$shared_profile" ] &&
   [ -r "$shared_bash_profile" ] &&
   [ -r "$shared_bashrc" ] &&
   sh -n "$shared_profile" &&
   bash -n "$shared_bash_profile" &&
   bash -n "$shared_bashrc" &&
   ! grep -q '^alias ' "$shared_profile" &&
   ! grep -q '\. "\$HOME/\.bashrc"' "$shared_profile" &&
   grep -q '\. "\$HOME/\.profile"' "$shared_bash_profile" &&
   grep -q '\. "\$HOME/\.bashrc"' "$shared_bash_profile" &&
   grep -q '^alias ll=' "$shared_bashrc" &&
   ! grep -q 'luks-mok-' "$shared_bashrc"; then
  pass "shared shell assets are syntax-valid, keep login env in .profile, and do not inject MOK aliases"
else
  fail "shared shell assets are syntax-valid, keep login env in .profile, and do not inject MOK aliases"
fi

if grep -q '^stage_target_account_shell_assets() {$' "$account_script" &&
   grep -q 'etc/skel/.profile' "$account_script" &&
   grep -q 'etc/skel/.bash_profile' "$account_script" &&
   grep -q 'etc/skel/.bashrc' "$account_script" &&
   grep -q '^install_target_account_shell_assets() {$' "$account_script" &&
   grep -q 'install managed shell assets for primary account' "$account_script"; then
  pass "account late hook stages managed shell assets for all installs and installs them into the primary account home"
else
  fail "account late hook stages managed shell assets for all installs and installs them into the primary account home"
fi

if grep -q '"/target${DIR_POLKIT_LOCAL_RULES_D}"' "$account_script" &&
   grep -q 'stage_target_polkit_rule "$polkit_rule"' "$account_script" &&
   ! grep -q 'verify USB media authorization policy' "$account_script"; then
  pass "account late hook stages managed polkit rules without a target-side verification gate"
else
  fail "account late hook stages managed polkit rules without a target-side verification gate"
fi

account_answers="$TMP_DIR/account.answers"
effective_account_env="$TMP_DIR/effective-account.env"
if INSTALLER_CMDLINE='primary_user=alice primary_password=userSecret root_password=rootSecret' \
  sh -c '
    set -eu
    . "$1/d-i/debian/scripts/runtime/common.sh"
    . "$1/d-i/debian/hosts/shared/account.env"
    . "$1/d-i/debian/scripts/runtime/account.sh"
    runtime_write_account_answers "$2"
    runtime_write_effective_account_env "$3"
  ' sh "$ROOT_DIR" "$account_answers" "$effective_account_env" &&
   grep -q '^d-i passwd/username string alice$' "$account_answers" &&
   grep -q '^d-i passwd/user-password password userSecret$' "$account_answers" &&
   grep -q '^d-i passwd/root-password password rootSecret$' "$account_answers" &&
   ! grep -q 'user-password-crypted' "$account_answers" &&
   grep -q "^ACCOUNT_USERNAME='alice'$" "$effective_account_env" &&
   grep -q "^ACCOUNT_HOME='/home/alice'$" "$effective_account_env" &&
   grep -q "^SSH_AUTHORIZED_KEYS_TARGET='/home/alice/.ssh/authorized_keys'$" "$effective_account_env" &&
   ! grep -q 'userSecret\|rootSecret' "$effective_account_env"; then
  pass "runtime account helper derives primary and root credentials from cmdline without persisting plaintext env"
else
  fail "runtime account helper derives primary and root credentials from cmdline without persisting plaintext env"
fi

account_bootstrap_err="$TMP_DIR/account-bootstrap.err"
if RUNTIME_COMMON_LIB="$ROOT_DIR/d-i/debian/scripts/runtime/common.sh" \
  sh -c '
    set -eu
    . "$1/d-i/debian/scripts/runtime/account.sh"
    runtime_validate_printable_single_line empty ""
  ' sh "$ROOT_DIR" >"$TMP_DIR/account-bootstrap.out" 2>"$account_bootstrap_err"; then
  fail "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
elif grep -q 'fatal: empty must not be empty' "$account_bootstrap_err" &&
   ! grep -q 'runtime_fatal: not found' "$account_bootstrap_err"; then
  pass "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
else
  fail "runtime account helper bootstraps runtime_fatal from RUNTIME_COMMON_LIB"
fi

account_core_err="$TMP_DIR/account-core.err"
if INSTALLER_CMDLINE='primary_user=bob primary_password=userSecret root_password=rootSecret' \
  sh -c '
    set -eu
    root_dir=$1
    tmp_env_dir=$2

    TMP_ENV_DIR=$tmp_env_dir
    LATE_COMMAND_ACCOUNT_ENV="$root_dir/d-i/debian/hosts/shared/account.env"
    LATE_COMMAND_ACCOUNT_ENV_LOADED=0
    cp "$root_dir/d-i/debian/scripts/runtime/common.sh" "$TMP_ENV_DIR/runtime-common.sh"
    cp "$root_dir/d-i/debian/scripts/runtime/account.sh" "$TMP_ENV_DIR/account-runtime.sh"

    installer_fatal() {
      printf "fatal: %s\n" "$*" >&2
      exit 1
    }

    . "$root_dir/d-i/debian/scripts/late/core.sh"
    late_command_ensure_host_policy_envs() {
      :
    }
    late_command_load_account_env
    runtime_validate_printable_single_line empty ""
  ' sh "$ROOT_DIR" "$TMP_DIR" >"$TMP_DIR/account-core.out" 2>"$account_core_err"; then
  fail "late account env loader exports runtime common before sourcing account runtime"
elif grep -q 'fatal: empty must not be empty' "$account_core_err" &&
   ! grep -q 'runtime_fatal: not found' "$account_core_err"; then
  pass "late account env loader exports runtime common before sourcing account runtime"
else
  fail "late account env loader exports runtime common before sourcing account runtime"
fi

ssh_helper="$ROOT_DIR/d-i/debian/scripts/common/ssh.sh"
runtime_common="$ROOT_DIR/d-i/debian/scripts/runtime/common.sh"
sshd_config="$ROOT_DIR/d-i/debian/ssh/sshd_config"
if grep -q '^Port __INSTALLER_SSH_PORT__$' "$sshd_config" &&
   grep -q '^AllowUsers __INSTALLER_ACCOUNT_USERNAME__$' "$sshd_config" &&
   grep -q 'SSH_PORT "$SSH_PORT"' "$ssh_helper" &&
   grep -q 'runtime_apply_ssh_from_cmdline' "$runtime_common" &&
   grep -q 'ssh_port must be 65535 or lower' "$runtime_common"; then
  pass "SSH provisioning renders Port and AllowUsers from selected cmdline/runtime values"
else
  fail "SSH provisioning renders Port and AllowUsers from selected cmdline/runtime values"
fi

core_script="$ROOT_DIR/d-i/debian/scripts/late/core.sh"
if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/NetworkManager/conf.d/80-preseed-wifi-client.conf' "$core_script" &&
   grep -q 'staged NetworkManager Wi-Fi client policy is missing' "$core_script" &&
   grep -q 'NetworkManager Wi-Fi client policy must disable scan MAC randomization' "$core_script"; then
  pass "core late hook stages and verifies the NetworkManager Wi-Fi client policy"
else
  fail "core late hook stages and verifies the NetworkManager Wi-Fi client policy"
fi

wifi_client_conf="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/NetworkManager/conf.d/80-preseed-wifi-client.conf"
if grep -q '^\[device\]$' "$wifi_client_conf" &&
   grep -q '^wifi\.scan-rand-mac-address=no$' "$wifi_client_conf"; then
  pass "wifi client policy keeps scan MAC randomization disabled"
else
  fail "wifi client policy keeps scan MAC randomization disabled"
fi

dbus_script="$ROOT_DIR/d-i/debian/scripts/late/dbus-broker.sh"
if grep -Fq 'for dir_var in DIR_DBUS_SESSION_SERVICES DIR_DBUS_LOCAL_SESSION_SERVICES; do' "$dbus_script" &&
   grep -Fq 'run_in_target "stage dbus-broker session service compatibility aliases"' "$dbus_script" &&
   grep -Fq 'divert_path="${source_path}.distrib"' "$dbus_script"; then
  pass "dbus late hook uses runtime paths and diversions for session service alias staging"
else
  fail "dbus late hook uses runtime paths and diversions for session service alias staging"
fi

if grep -q 'verify_target_dbus_session_service_aliases()' "$dbus_script" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/dbus-1/system-local.conf.tmpl' "$dbus_script" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$dbus_script" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/user/dbus-broker.service.d/10-broker-hardening.conf.tmpl' "$dbus_script"; then
  pass "dbus late hook verifies aliases and resolves dbus template assets through repo env"
else
  fail "dbus late hook verifies aliases and resolves dbus template assets through repo env"
fi

if grep -q 'org.xfce.Thunar.FileManager1.service:org.freedesktop.FileManager1' "$dbus_script" &&
   grep -q 'org.xfce.Tumbler.Thumbnailer1.service:org.freedesktop.thumbnails.Thumbnailer1' "$dbus_script"; then
  pass "dbus late hook keeps the expected compatibility alias coverage"
else
  fail "dbus late hook keeps the expected compatibility alias coverage"
fi

if grep -q 'sanitize_target_dbus_session_conf()' "$dbus_script" &&
   grep -Fq 'python3 -c "' "$dbus_script" &&
   grep -q 'attribute-free policy rules' "$dbus_script" &&
   sample_conf="$ROOT_DIR/.tmp-dbus-session-conf.$$" &&
   sample_out="$ROOT_DIR/.tmp-dbus-session-out.$$" &&
   cat >"$sample_conf" <<'EOF' &&
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
   python3 - "$sample_conf" "$sample_out" <<'PY' &&
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
single_quote = chr(39)
space_pattern = r"\s+"

output_lines = []
for raw_line in source_path.read_text(encoding="utf-8").splitlines():
    if re.search(r"<allow[^>]*eavesdrop\s*=", raw_line):
        stripped = re.sub(space_pattern + r'eavesdrop="[^"]*"', '', raw_line)
        stripped = re.sub(space_pattern + rf"eavesdrop={single_quote}[^{single_quote}]*{single_quote}", "", stripped)
        if re.search(r"<allow\s*/>", stripped):
            output_lines.extend([
                '    <allow receive_type="method_call"/>',
                '    <allow receive_type="method_return"/>',
                '    <allow receive_type="error"/>',
                '    <allow receive_type="signal"/>',
            ])
        else:
            output_lines.append(stripped)
        continue
    output_lines.append(raw_line)

target_path.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
PY
   ! grep -Eq 'eavesdrop[[:space:]]*=' "$sample_out" &&
   grep -q '<allow send_destination="\*"/>' "$sample_out" &&
   grep -q '<allow receive_type="method_call"/>' "$sample_out" &&
   grep -q '<allow receive_type="signal"/>' "$sample_out" &&
   ! grep -Eq '<allow[[:space:]]*/>' "$sample_out" &&
   grep -q '<allow own="\*"/>' "$sample_out"; then
  pass "dbus late hook converts bare eavesdrop receive rules into explicit receive policy"
else
  fail "dbus late hook converts bare eavesdrop receive rules into explicit receive policy"
fi
rm -f "$ROOT_DIR/.tmp-dbus-session-conf.$$" "$ROOT_DIR/.tmp-dbus-session-out.$$"

security_script="$ROOT_DIR/d-i/debian/scripts/late/security.sh"
ssh_service_overlay="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/nftables/services/ssh-server.yml"
if grep -q 'late_command_nftables_effective_services()' "$security_script" &&
   grep -q 'SSH_SERVER_ENABLED' "$security_script" &&
   grep -q 'nftables_merge_selected_services "\$effective_services" ssh-server' "$security_script" &&
   grep -q 'nftables_ssh_service_placeholder_map' "$security_script" &&
   grep -q 'render_target_asset_with_placeholder_map' "$security_script" &&
   grep -q '^    - __INSTALLER_SSH_PORT__$' "$ssh_service_overlay" &&
   grep -q '^      ipv4: __INSTALLER_NFTABLES_SSH_ALLOW_IPV4__$' "$ssh_service_overlay" &&
   grep -q '^      ipv6: __INSTALLER_NFTABLES_SSH_ALLOW_IPV6__$' "$ssh_service_overlay" &&
   grep -q '__INSTALLER_PRESEED_NETWORK_ETHERNET_IFACE__' "$ssh_service_overlay" &&
   grep -q '__INSTALLER_PRESEED_NETWORK_WIFI_IFACE__' "$ssh_service_overlay"; then
  pass "security late hook auto-enables the ssh-server firewall overlay with cmdline port and managed subnet placeholders"
else
  fail "security late hook auto-enables the ssh-server firewall overlay with cmdline port and managed subnet placeholders"
fi

if grep -q '^FILE_MODULES_LOAD_TPM=' "$runtime_env" &&
   grep -q '^tpm$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/modules-load.d/32-tpm.conf" &&
   grep -q '^tpm_crb$' "$ROOT_DIR/d-i/debian/hooks/shared/target/etc/modules-load.d/32-tpm.conf"; then
  pass "runtime env and shared target assets define the managed TPM module load list"
else
  fail "runtime env and shared target assets define the managed TPM module load list"
fi

if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modules-load.d/32-tpm.conf' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/modules-load.d/32-tpm.conf' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"; then
  pass "late storage hooks stage the managed TPM module load list"
else
  fail "late storage hooks stage the managed TPM module load list"
fi

apt_auto="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apt/apt.conf.d/20auto-upgrades"
apt_no_pdiffs="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apt/apt.conf.d/25no-pdiffs"
apt_unattended="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apt/apt.conf.d/52unattended-upgrades"
apt_no_recommends="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apt/apt.conf.d/99noinstall-recommends"
login_defs="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/login.defs"
unattended_dropin="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/unattended-upgrades.service.d/10-preseed-warning-policy.conf"
if grep -q '^APT::Periodic::Update-Package-Lists "1";$' "$apt_auto" &&
   grep -q '^APT::Periodic::Unattended-Upgrade "1";$' "$apt_auto" &&
   grep -q '^Acquire::PDiffs "false";$' "$apt_no_pdiffs" &&
   grep -q '^Unattended-Upgrade::MailReport "on-change";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Remove-New-Unused-Dependencies "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Remove-Unused-Dependencies "true";$' "$apt_unattended" &&
   grep -q '^Unattended-Upgrade::Automatic-Reboot "false";$' "$apt_unattended" &&
   grep -q '^APT::Install-Recommends "false";$' "$apt_no_recommends" &&
   grep -q '^APT::Install-Suggests "false";$' "$apt_no_recommends" &&
   grep -q '^ENCRYPT_METHOD YESCRYPT$' "$login_defs" &&
   grep -q '^Environment=PYTHONWARNINGS=ignore::DeprecationWarning$' "$unattended_dropin"; then
  pass "shared target policy assets configure unattended upgrades, pdiff policy, and YESCRYPT login defaults"
else
  fail "shared target policy assets configure unattended upgrades, pdiff policy, and YESCRYPT login defaults"
fi

storage_script="$ROOT_DIR/d-i/debian/scripts/late/storage-maintenance.sh"
if grep -q 'managed_target_policy_assets()' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/20auto-upgrades' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/25no-pdiffs' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/52unattended-upgrades' "$storage_script" &&
   grep -q 'etc/apt/apt.conf.d/99noinstall-recommends' "$storage_script" &&
   grep -q 'etc/login.defs' "$storage_script" &&
   grep -q 'Acquire::PDiffs' "$storage_script" &&
   grep -q 'Unattended-Upgrade::MailReport' "$storage_script" &&
   grep -q 'APT::Install-Recommends' "$storage_script" &&
   grep -q 'ENCRYPT_METHOD' "$storage_script"; then
  pass "storage maintenance staging installs and verifies apt/login policy"
else
  fail "storage maintenance staging installs and verifies apt/login policy"
fi

if grep -q 'sanitize_target_xfs_scrub_systemd_units()' "$storage_script" &&
   grep -q 'target_xfs_scrub_cpuaccounting_units()' "$storage_script" &&
   grep -Fq "sed '/^[[:space:]]*CPUAccounting[[:space:]]*=/d'" "$storage_script" &&
   grep -q 'verify_target_xfs_scrub_systemd_units()' "$storage_script" &&
   grep -q 'sanitize_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'sanitize_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh" &&
   grep -q 'verify_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'verify_target_xfs_scrub_systemd_units' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"; then
  pass "storage maintenance sanitizes xfs scrub units that still ship removed CPUAccounting"
else
  fail "storage maintenance sanitizes xfs scrub units that still ship removed CPUAccounting"
fi

profile_env_files='
d-i/debian/hosts/profiles/btrfs/desktop.env
d-i/debian/hosts/profiles/btrfs/server.env
d-i/debian/hosts/profiles/f2fs/desktop.env
d-i/debian/hosts/profiles/f2fs/server.env
d-i/debian/hosts/profiles/vm/desktop.env
d-i/debian/hosts/profiles/vm/server.env
'
profile_iface_ok=true
for relpath in $profile_env_files; do
  env_file="$ROOT_DIR/$relpath"
  if ! grep -q '^PRESEED_NETWORK_ETHERNET_IFACE="preeth0"$' "$env_file" ||
     ! grep -q '^PRESEED_NETWORK_WIFI_IFACE="prewifi0"$' "$env_file"; then
    profile_iface_ok=false
    break
  fi
done
if [ "$profile_iface_ok" = true ]; then
  pass "all concrete desktop and server profiles define configurable first-boot interface names"
else
  fail "all concrete desktop and server profiles define configurable first-boot interface names"
fi

network_script="$ROOT_DIR/d-i/debian/scripts/late/network.sh"
network_generator="$ROOT_DIR/d-i/debian/scripts/late/preseed-network-generate.pl"
if grep -q 'target_ethernet_iface=${PRESEED_NETWORK_ETHERNET_IFACE:-preeth0}' "$network_script" &&
   grep -q 'target_wifi_iface=${PRESEED_NETWORK_WIFI_IFACE:-prewifi0}' "$network_script" &&
   grep -q 'write_shell_config_var PRESEED_NETWORK_ETHERNET_IFACE "$target_ethernet_iface"' "$network_script" &&
   grep -q 'write_shell_config_var PRESEED_NETWORK_WIFI_IFACE "$target_wifi_iface"' "$network_script" &&
   grep -q 'return $link_type eq '\''wifi'\'' ? $CFG{PRESEED_NETWORK_WIFI_IFACE} : $CFG{PRESEED_NETWORK_ETHERNET_IFACE};' "$network_generator" &&
   grep -q 'PRESEED_NETWORK_ETHERNET_IFACE and PRESEED_NETWORK_WIFI_IFACE must differ' "$network_generator"; then
  pass "late network generation persists configurable first-boot interface names into the handoff defaults"
else
  fail "late network generation persists configurable first-boot interface names into the handoff defaults"
fi

nft_readme="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/nftables/README.md"
nft_doc="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/nft-policy-generate.md"
nm_unmanaged_template="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/NetworkManager/conf.d/90-preseed-network-unmanaged.conf"
if grep -q 'nftables_interface_placeholder_map()' "$security_script" &&
   grep -q 'render_target_asset_with_placeholder_map "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/nftables/README.md)" "/etc/nftables/README.md" 0644 nftables_interface_placeholder_map' "$security_script" &&
   grep -q 'stage_target_helper_doc nft-policy-generate.md nft-policy-generate.md' "$security_script" &&
   grep -q '__INSTALLER_PRESEED_NETWORK_ETHERNET_IFACE__' "$nft_readme" &&
   grep -q '__INSTALLER_PRESEED_NETWORK_WIFI_IFACE__' "$nft_readme" &&
   [ -r "$nft_doc" ] &&
   grep -q '__INSTALLER_PRESEED_NETWORK_ETHERNET_IFACE__' "$nm_unmanaged_template" &&
   grep -q '__INSTALLER_PRESEED_NETWORK_WIFI_IFACE__' "$nm_unmanaged_template"; then
  pass "nftables and NetworkManager artifacts render the configured managed interface names"
else
  fail "nftables and NetworkManager artifacts render the configured managed interface names"
fi

shared_loader="$ROOT_DIR/d-i/debian/hooks/shared/late_command.sh"
dispatch_script="$ROOT_DIR/d-i/debian/scripts/late/dispatch.sh"
volatile_script="$ROOT_DIR/d-i/debian/scripts/late/volatile-storage.sh"
asset_script="$ROOT_DIR/d-i/debian/scripts/late/target-assets.sh"
if [ ! -e "$ROOT_DIR/d-i/debian/scripts/late/tmpfs.sh" ] &&
   grep -q 'target-assets' "$shared_loader" &&
   grep -q 'volatile-storage' "$shared_loader" &&
   grep -q 'storage-maintenance' "$shared_loader" &&
   grep -q 'shared_modules="core target-assets volatile-storage storage-maintenance templates network grub security dbus-broker podman gitlab-runner zram-swap btrfs-family f2fs-family account"' "$dispatch_script" &&
   grep -q '^stage_target_helper_doc() {$' "$asset_script" &&
   grep -q 'apply_sysctl_profile_placeholders()' "$asset_script" &&
   grep -q 'apply_tmpfs_policy_placeholders()' "$volatile_script"; then
  pass "late module loader uses the split target-assets, volatile-storage, and storage-maintenance helpers"
else
  fail "late module loader uses the split target-assets, volatile-storage, and storage-maintenance helpers"
fi

udev_udisks_rules="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/udev/rules.d/90-udisks-behavior.rules"
account_script="$ROOT_DIR/d-i/debian/scripts/late/account.sh"
if grep -q 'ENV{ID_FS_LABEL}=="secure-boot-mok".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules" &&
   grep -q 'ENV{DM_NAME}=="secure-boot-mok".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules" &&
   grep -q 'ENV{ID_FS_LABEL}=="SHIM_SIGNED".*ENV{UDISKS_IGNORE}="1"' "$udev_udisks_rules"; then
  pass "udisks policy hides the secure-boot MOK state from file managers"
else
  fail "udisks policy hides the secure-boot MOK state from file managers"
fi

wpa_override="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/wpa_supplicant.service.d/10-preseed-no-p2p.conf"
core_script="$ROOT_DIR/d-i/debian/scripts/late/core.sh"
if ! grep -q ' -m /etc/wpa_supplicant/p2p-device.conf ' "$wpa_override" &&
   grep -q 'must not start a dedicated P2P device config' "$core_script"; then
  pass "wpa_supplicant D-Bus override avoids the dedicated P2P device path"
else
  fail "wpa_supplicant D-Bus override avoids the dedicated P2P device path"
fi

[ "$FAIL_COUNT" -eq 0 ]
