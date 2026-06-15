#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PRESEED_CFG="$ROOT_DIR/d-i/debian/preseed.cfg"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/preseed-fetch-path-smoke.XXXXXX")
TEST_COUNT=33
TEST_INDEX=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

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

top_include_line=$(sed -n 's/^d-i[[:space:]]\+preseed\/include[[:space:]]\+string[[:space:]]\+//p' "$PRESEED_CFG")
common_include_line=$(sed -n 's/^d-i[[:space:]]\+preseed\/include[[:space:]]\+string[[:space:]]\+//p' "$ROOT_DIR/d-i/debian/common.cfg")

if [ "$top_include_line" = "common.cfg" ]; then
  pass "top-level preseed include is common.cfg only"
else
  fail "top-level preseed include is common.cfg only"
fi

case "$common_include_line" in
  *'fragments/apt.cfg'*)
    pass "common.cfg include references fragments/apt.cfg"
    ;;
  *)
    fail "common.cfg include references fragments/apt.cfg"
    ;;
esac

case " $common_include_line " in
  *' apt.cfg '*|*' /apt.cfg '*)
    fail "common.cfg include does not request root-level apt.cfg"
    ;;
  *)
    pass "common.cfg include does not request root-level apt.cfg"
    ;;
esac

case "$top_include_line $common_include_line" in
  *'\'*)
    fail "preseed include lines are physical single lines"
    ;;
  *)
    pass "preseed include lines are physical single lines"
    ;;
esac

normalized_seed=$(
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/common/bootstrap.sh"
  bootstrap_normalize_seed_base "http://192.0.2.10:8080/d-i/debian/" url
)
if [ "$normalized_seed" = "http://192.0.2.10:8080/d-i/debian" ]; then
  pass "bootstrap URL seed base strips trailing slash"
else
  fail "bootstrap URL seed base strips trailing slash"
fi

direct_fragment_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-smoke.$$" \
    sh -c '
      set -eu
      # shellcheck disable=SC1090
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_ensure_repo_env ""
      installer_repo_join_var fragments/apt.cfg ""
    '
)
if [ "$direct_fragment_path" = "fragments/apt.cfg" ]; then
  pass "repo path helper accepts direct fragments/apt.cfg input"
else
  fail "repo path helper accepts direct fragments/apt.cfg input"
fi

derived_grub_dropin_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-grub.$$" \
    sh -c '
      set -eu
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_ensure_repo_env ""
      installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/default/grub.d/50-os-prober.cfg.tmpl
    '
)
if [ "$derived_grub_dropin_path" = "hooks/shared/target/etc/default/grub.d/50-os-prober.cfg.tmpl" ]; then
  pass "repo path helper derives shared target drop-in paths from reduced repo.env"
else
  fail "repo path helper derives shared target drop-in paths from reduced repo.env"
fi

derived_role_target_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-role.$$" \
    sh -c '
      set -eu
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_ensure_repo_env ""
      installer_repo_join_var DIR_HOOKS_ROLE_DESKTOP target/etc/greetd/config.toml.tmpl
    '
)
if [ "$derived_role_target_path" = "hooks/role/desktop/target/etc/greetd/config.toml.tmpl" ]; then
  pass "repo path helper derives role target paths from reduced repo.env"
else
  fail "repo path helper derives role target paths from reduced repo.env"
fi

derived_apt_setup_generator_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-apt.$$" \
    sh -c '
      set -eu
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_ensure_repo_env ""
      installer_repo_join_var DIR_HOOKS_SHARED_APT_SETUP_GENERATORS generators/99-apt-preferences
    '
)
if [ "$derived_apt_setup_generator_path" = "hooks/shared/apt-setup/generators/99-apt-preferences" ]; then
  pass "repo path helper normalizes apt-setup generator roots from reduced repo.env"
else
  fail "repo path helper normalizes apt-setup generator roots from reduced repo.env"
fi

apt_preferences_generator="$ROOT_DIR/d-i/debian/hooks/shared/apt-setup/generators/99-apt-preferences"
if grep -q 'installer_repo_join_var DIR_HOOKS_SHARED_TARGET "etc/apt/preferences.d/${pref_name}"' "$apt_preferences_generator" &&
   ! grep -q 'DIR_HOOKS_SHARED_APT_PREFERENCES_D' "$apt_preferences_generator"; then
  pass "apt preferences generator uses the reduced shared target repo root"
else
  fail "apt preferences generator uses the reduced shared target repo root"
fi

dualboot_class="$ROOT_DIR/d-i/debian/classes/class-addon/dualboot.cfg"
classes_conf="$ROOT_DIR/d-i/debian/classes/CLASSES.conf"
if grep -q '^\[class\.addon\.dualboot\]$' "$classes_conf" &&
   grep -q '^allowed_hardware_classes=disk/nvme disk/vm$' "$classes_conf" &&
   grep -q '^d-i pkgsel/include string os-prober$' "$dualboot_class"; then
  pass "dualboot addon is declared and owns os-prober package selection"
else
  fail "dualboot addon is declared and owns os-prober package selection"
fi

if grep -q '^d-i grub-installer/only_debian boolean false$' "$dualboot_class" &&
   grep -q '^d-i grub-installer/with_other_os boolean true$' "$dualboot_class" &&
   grep -q '^d-i grub-installer/enable_os_prober_otheros_yes boolean true$' "$dualboot_class"; then
  pass "dualboot addon flips GRUB installer answers for other OS probing"
else
  fail "dualboot addon flips GRUB installer answers for other OS probing"
fi

if ! grep -q 'os-prober' "$ROOT_DIR/d-i/debian/fragments/apt.cfg"; then
  pass "base apt fragment leaves os-prober to the dualboot addon"
else
  fail "base apt fragment leaves os-prober to the dualboot addon"
fi

grub_helper="$ROOT_DIR/d-i/debian/scripts/late/grub.sh"
btrfs_late="$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh"
if grep -q '^require_target_dualboot_os_prober_package() {$' "$grub_helper" &&
   ! grep -q 'TARGET_HAS_OS_PROBER' "$grub_helper"; then
  pass "late grub helper uses direct dualboot os-prober verification instead of cached os-prober state"
else
  fail "late grub helper uses direct dualboot os-prober verification instead of cached os-prober state"
fi

if grep -q '^resolve_target_grub_config_command() {$' "$grub_helper" &&
   grep -q '/usr/sbin/grub-mkconfig' "$grub_helper" &&
   grep -q '/usr/sbin/update-grub' "$grub_helper"; then
  pass "late grub helper supports both update-grub and grub-mkconfig target regeneration paths"
else
  fail "late grub helper supports both update-grub and grub-mkconfig target regeneration paths"
fi

if grep -q 'require_target_dualboot_os_prober_package' "$btrfs_late" &&
   grep -q 'run_target_grub_config_update' "$btrfs_late" &&
   ! grep -q 'TARGET_HAS_OS_PROBER' "$btrfs_late" &&
   ! grep -q 'TARGET_HAS_UPDATE_GRUB' "$btrfs_late"; then
  pass "btrfs late path uses direct os-prober and grub config helper checks instead of cached boot-tool state"
else
  fail "btrfs late path uses direct os-prober and grub config helper checks instead of cached boot-tool state"
fi

f2fs_late="$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"
if grep -q 'run_target_grub_config_update' "$f2fs_late" &&
   ! grep -q 'TARGET_HAS_UPDATE_GRUB' "$f2fs_late"; then
  pass "f2fs late path also uses the shared grub config helper instead of a fixed update-grub wrapper"
else
  fail "f2fs late path also uses the shared grub config helper instead of a fixed update-grub wrapper"
fi

derived_ssh_asset_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-ssh.$$" \
    sh -c '
      set -eu
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_repo_join_var ssh config
    '
)
if [ "$derived_ssh_asset_path" = "ssh/config" ]; then
  pass "repo path helper keeps SSH assets reachable without repo.env SSH variables"
else
  fail "repo path helper keeps SSH assets reachable without repo.env SSH variables"
fi

if sh -c '
  set -eu
  . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
  installer_repo_dir_input_is_var DIR_SCRIPTS_COMMON/foo
'; then
  fail "runtime repo path helper rejects DIR-prefixed paths as variables"
else
  pass "runtime repo path helper rejects DIR-prefixed paths as variables"
fi

if direct_dir_path=$(
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  INSTALLER_RUNTIME_DIR="${TMPDIR:-/tmp}/preseed-fetch-path-smoke-dir.$$" \
    sh -c '
      set -eu
      . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
      installer_repo_join_var DIR_SCRIPTS_COMMON/foo ""
    '
); then
  if [ "$direct_dir_path" = "DIR_SCRIPTS_COMMON/foo" ]; then
    pass "runtime repo path helper preserves DIR-prefixed direct paths"
  else
    fail "runtime repo path helper preserves DIR-prefixed direct paths"
  fi
else
  fail "runtime repo path helper preserves DIR-prefixed direct paths"
fi

if sh -c '
  set -eu
  . "'"$ROOT_DIR"'/d-i/debian/scripts/common/bootstrap.sh"
  bootstrap_repo_dir_input_is_var DIR_SCRIPTS_COMMON/foo
'; then
  fail "bootstrap repo path helper rejects DIR-prefixed paths as variables"
else
  pass "bootstrap repo path helper rejects DIR-prefixed paths as variables"
fi

bootstrap_direct_path=$(
  sh -c '
    set -eu
    . "'"$ROOT_DIR"'/d-i/debian/scripts/common/bootstrap.sh"
    bootstrap_repo_join_var DIR_SCRIPTS_COMMON/foo ""
  '
)
if [ "$bootstrap_direct_path" = "DIR_SCRIPTS_COMMON/foo" ]; then
  pass "bootstrap repo path helper preserves DIR-prefixed direct paths"
else
  fail "bootstrap repo path helper preserves DIR-prefixed direct paths"
fi

host_env_path="$TMP_DIR/host.env"
if INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
   INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-host" \
   sh -c '
     set -eu
     . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
     installer_fetch_host_env "'"$ROOT_DIR"'/d-i/debian" btrfs-desktop "'"$host_env_path"'" 0600
   ' &&
   grep -q '^PARTMAN_RECIPE_NAME="btrfs-layout-desktop"$' "$host_env_path" &&
   grep -q '^SYSTEM_DOMAIN=' "$host_env_path"; then
  pass "host env fetch composes repo-relative host paths without bad substitution"
else
  fail "host env fetch composes repo-relative host paths without bad substitution"
fi

server_host_env_path="$TMP_DIR/host-server.env"
if INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
   INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-host-server" \
   sh -c '
     set -eu
     . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
     installer_fetch_host_env "'"$ROOT_DIR"'/d-i/debian" btrfs-server "'"$server_host_env_path"'" 0600
   ' &&
   grep -q '^PARTMAN_RECIPE_NAME="btrfs-layout-server"$' "$server_host_env_path" &&
   grep -q '^PODMAN_USER="podsvc"$' "$server_host_env_path" &&
   ! grep -q '^LABWC_DESKTOP_ENABLE=' "$server_host_env_path"; then
  pass "host env fetch selects the server role-shared env without desktop-only policy"
else
  fail "host env fetch selects the server role-shared env without desktop-only policy"
fi

fake_bin="$TMP_DIR/bin"
fake_wget_log="$TMP_DIR/wget.log"
mkdir -p "$fake_bin"
cat >"$fake_bin/wget" <<'EOF'
#!/bin/sh
set -eu
out=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -O)
      shift
      out=${1:-}
      ;;
    --spider|--no-verbose)
      ;;
    --tries=*|--timeout=*)
      ;;
    *)
      url=$1
      ;;
  esac
  shift || true
done
[ -n "$url" ] || exit 2
printf '%s\n' "$url" >>"${WGET_LOG:?WGET_LOG must be set}"
case "$url" in
  */repo.env)
    cat >"$out" <<'REPOENV'
DIR_SCRIPTS_COMMON="scripts/common"
DIR_SCRIPTS_EARLY="scripts/early"
DIR_SCRIPTS_LATE="scripts/late"
DIR_SCRIPTS_PARTMAN="scripts/partman"
DIR_SCRIPTS_PRESEED="scripts/preseed"
REPOENV
    ;;
  *)
    printf 'fetched %s\n' "$url" >"$out"
    ;;
esac
EOF
chmod 0700 "$fake_bin/wget"

: >"$fake_wget_log"
if PATH="$fake_bin:$PATH" WGET_LOG="$fake_wget_log" INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-cache" \
   sh -c '
     set -eu
     . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
     installer_fetch_file http://seed.example/d-i/debian scripts/common/lib.sh "'"$TMP_DIR"'/runtime-lib-1" 0600
     installer_fetch_file http://seed.example/d-i/debian scripts/common/lib.sh "'"$TMP_DIR"'/runtime-lib-2" 0600
   '; then
  runtime_lib_fetches=$(grep -c '/scripts/common/lib\.sh$' "$fake_wget_log" || true)
  if [ "$runtime_lib_fetches" = 1 ]; then
    pass "runtime fetch cache reuses successfully fetched files"
  else
    fail "runtime fetch cache reuses successfully fetched files"
  fi
else
  fail "runtime fetch cache reuses successfully fetched files"
fi

: >"$fake_wget_log"
if PATH="$fake_bin:$PATH" WGET_LOG="$fake_wget_log" INSTALLER_RUNTIME_DIR="$TMP_DIR/bootstrap-cache" \
   sh -c '
     set -eu
     . "'"$ROOT_DIR"'/d-i/debian/scripts/common/bootstrap.sh"
     bootstrap_fetch_seed_file http://seed.example/d-i/debian scripts/common/bootstrap.sh "'"$TMP_DIR"'/bootstrap-1" 0600 "bootstrap"
     bootstrap_fetch_seed_file http://seed.example/d-i/debian scripts/common/bootstrap.sh "'"$TMP_DIR"'/bootstrap-2" 0600 "bootstrap"
   '; then
  bootstrap_fetches=$(grep -c '/scripts/common/bootstrap\.sh$' "$fake_wget_log" || true)
  if [ "$bootstrap_fetches" = 1 ]; then
    pass "bootstrap fetch cache reuses successfully fetched files"
  else
    fail "bootstrap fetch cache reuses successfully fetched files"
  fi
else
  fail "bootstrap fetch cache reuses successfully fetched files"
fi

apply_seed="$TMP_DIR/apply-seed"
mkdir -p "$apply_seed/scripts/preseed"
cat >"$apply_seed/scripts/preseed/bootstrap-entry.sh" <<'EOF'
#!/bin/sh
printf 'fresh helper\n' >"${INSTALLER_RUNTIME_DIR:?}/helper.marker"
exit 0
EOF
chmod 0700 "$apply_seed/scripts/preseed/bootstrap-entry.sh"
apply_runtime="$TMP_DIR/apply-runtime"
apply_bootstrap="$apply_runtime/bootstrap"
apply_state="$apply_runtime/state"
apply_seed_cache="$apply_runtime/cache/seed/file/example.invalid"
mkdir -p "$apply_bootstrap" "$apply_state" "$apply_seed_cache/scripts/preseed"
cat >"$apply_bootstrap/preseed-bootstrap-entry.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0700 "$apply_bootstrap/preseed-bootstrap-entry.sh"
printf 'cached bootstrap lib\n' >"$apply_bootstrap/bootstrap.sh"
printf 'DIR_SCRIPTS_COMMON="scripts/common"\n' >"$apply_bootstrap/repo.env"
printf 'stale classes\n' >"$apply_state/classes.raw"
printf 'stale context\n' >"$apply_state/context.env"
printf 'stale cached answers\n' >"$apply_seed_cache/scripts/preseed/answers.sh"
if INSTALLER_RUNTIME_DIR="$apply_runtime" sh "$ROOT_DIR/d-i/debian/scripts/preseed/apply.sh" "$apply_seed" &&
   [ -s "$apply_runtime/helper.marker" ] &&
   [ ! -e "$apply_bootstrap/bootstrap.sh" ] &&
   [ ! -e "$apply_bootstrap/repo.env" ] &&
   [ -e "$apply_state/classes.raw" ] &&
   [ -e "$apply_state/context.env" ] &&
   [ ! -d "$apply_runtime/cache/seed" ] &&
   grep -q 'fresh helper' "$apply_runtime/helper.marker"; then
  pass "preseed apply refreshes bootstrap/cache while preserving early context state"
else
  fail "preseed apply refreshes bootstrap/cache while preserving early context state"
fi

stale_runtime="$TMP_DIR/stale-runtime"
stale_bin="$TMP_DIR/stale-bin"
mkdir -p "$stale_runtime/state" "$stale_runtime/bootstrap" "$stale_bin"
printf 'lab,desktop,standard,dhcp\n' >"$stale_runtime/state/classes.raw"
cat >"$stale_bin/debconf-get" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  auto-install/classes|classes)
    printf '%s: %s\n' "$1" "lab,desktop,standard,dhcp"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 0700 "$stale_bin/debconf-get"
if PATH="$stale_bin:$PATH" \
   INSTALLER_RUNTIME_DIR="$stale_runtime" \
   INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
   sh "$ROOT_DIR/d-i/debian/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/debian" >/dev/null; then
  resolved_classes=$(cat "$stale_runtime/state/classes.raw" 2>/dev/null || true)
  stale_cache_fixed=true
  for auto_class in $(sh "$ROOT_DIR/d-i/debian/scripts/preseed/class-auto.sh" classes); do
    case ",$resolved_classes," in
      *",$auto_class,"*) ;;
      *)
        stale_cache_fixed=false
        break
        ;;
    esac
  done
  if [ "$stale_cache_fixed" = true ]; then
    pass "preseed render ignores stale classes.raw when current class input is available"
  else
    fail "preseed render ignores stale classes.raw when current class input is available"
  fi
else
  fail "preseed render ignores stale classes.raw when current class input is available"
fi

collector_seed="$TMP_DIR/collector-seed"
collector_runtime="$TMP_DIR/collector-runtime"
mkdir -p "$collector_seed/scripts/preseed" "$collector_runtime"
cat >"$collector_seed/repo.env" <<'EOF'
DIR_SCRIPTS_COMMON="scripts/common"
DIR_SCRIPTS_EARLY="scripts/early"
DIR_SCRIPTS_LATE="scripts/late"
DIR_SCRIPTS_PARTMAN="scripts/partman"
DIR_SCRIPTS_PRESEED="scripts/preseed"
EOF
cat >"$collector_seed/scripts/preseed/class-auto.sh" <<'EOF'
#!/bin/sh
set -eu
case "${1:-report}" in
  classes)
    printf 'arch/amd64\ncpu/intel\ngpu/generic\ndisk/vm\n'
    ;;
  report|--report)
    printf '\n=== d-i hardware detection ===\n\n[AUTO CLASSES]\n\n=== end ===\n\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0700 "$collector_seed/scripts/preseed/class-auto.sh"
collector_tokens=$(
  INSTALLER_RUNTIME_DIR="$collector_runtime" \
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
  sh -c '
    set -eu
    . "'"$ROOT_DIR"'/d-i/debian/scripts/common/lib.sh"
    installer_ensure_repo_env "'"$collector_seed"'"
    installer_auto_class_tokens "'"$collector_seed"'"
  '
)
if [ "$collector_tokens" = "arch/amd64
cpu/intel
gpu/generic
disk/vm" ]; then
  pass "auto class collector uses classes output instead of parsing human report"
else
  fail "auto class collector uses classes output instead of parsing human report"
fi

disk_probe_root="$TMP_DIR/disk-probe-sys"
disk_probe_pci_root="$TMP_DIR/disk-probe-pci"
mkdir -p "$disk_probe_root/sda" "$disk_probe_pci_root"
printf '0\n' >"$disk_probe_root/sda/removable"
disk_probe_output=$(
  CLASS_AUTO_SYS_BLOCK_ROOT="$disk_probe_root" \
  CLASS_AUTO_SYS_PCI_DEVICES_ROOT="$disk_probe_pci_root" \
  CLASS_AUTO_VM_TYPE_OVERRIDE=none \
  sh "$ROOT_DIR/d-i/debian/scripts/preseed/class-auto.sh" classes
)
case "$disk_probe_output" in
  *"disk/nvme"*)
    pass "class auto disk detection maps fixed non-NVMe bare-metal disks to nvme baseline"
    ;;
  *)
    fail "class auto disk detection maps fixed non-NVMe bare-metal disks to nvme baseline"
    ;;
esac

nvme_vm_probe_root="$TMP_DIR/nvme-vm-probe-sys"
mkdir -p "$nvme_vm_probe_root/nvme1n1" "$nvme_vm_probe_root/vda" "$nvme_vm_probe_root/sda"
printf '0\n' >"$nvme_vm_probe_root/nvme1n1/removable"
printf '0\n' >"$nvme_vm_probe_root/vda/removable"
printf '0\n' >"$nvme_vm_probe_root/sda/removable"
nvme_vm_probe_output=$(
  CLASS_AUTO_SYS_BLOCK_ROOT="$nvme_vm_probe_root" \
  CLASS_AUTO_VM_TYPE_OVERRIDE=kvm \
  sh "$ROOT_DIR/d-i/debian/scripts/preseed/class-auto.sh" classes
)
case "$nvme_vm_probe_output" in
  *"disk/nvme"*)
    pass "class auto disk detection lets NVMe take precedence over VM and SCSI disks"
    ;;
  *)
    fail "class auto disk detection lets NVMe take precedence over VM and SCSI disks"
    ;;
esac

nvme_pci_probe_block_root="$TMP_DIR/nvme-pci-probe-sys"
nvme_pci_probe_pci_root="$TMP_DIR/nvme-pci-probe-pci"
mkdir -p "$nvme_pci_probe_block_root" "$nvme_pci_probe_pci_root/0000:00:01.0"
printf '0x144d\n' >"$nvme_pci_probe_pci_root/0000:00:01.0/vendor"
printf '0x010802\n' >"$nvme_pci_probe_pci_root/0000:00:01.0/class"
nvme_pci_probe_output=$(
  CLASS_AUTO_SYS_BLOCK_ROOT="$nvme_pci_probe_block_root" \
  CLASS_AUTO_SYS_PCI_DEVICES_ROOT="$nvme_pci_probe_pci_root" \
  CLASS_AUTO_VM_TYPE_OVERRIDE=kvm \
  sh "$ROOT_DIR/d-i/debian/scripts/preseed/class-auto.sh" classes
)
case "$nvme_pci_probe_output" in
  *"disk/nvme"*)
    pass "class auto disk detection maps PCI NVMe controllers to nvme before block devices settle"
    ;;
  *)
    fail "class auto disk detection maps PCI NVMe controllers to nvme before block devices settle"
    ;;
esac

vm_probe_root="$TMP_DIR/vm-probe-sys"
vm_probe_pci_root="$TMP_DIR/vm-probe-pci"
mkdir -p "$vm_probe_root/vda" "$vm_probe_root/sda" "$vm_probe_pci_root"
printf '0\n' >"$vm_probe_root/vda/removable"
printf '0\n' >"$vm_probe_root/sda/removable"
vm_probe_output=$(
  CLASS_AUTO_SYS_BLOCK_ROOT="$vm_probe_root" \
  CLASS_AUTO_SYS_PCI_DEVICES_ROOT="$vm_probe_pci_root" \
  CLASS_AUTO_VM_TYPE_OVERRIDE=kvm \
  sh "$ROOT_DIR/d-i/debian/scripts/preseed/class-auto.sh" classes
)
case "$vm_probe_output" in
  *"disk/vm"*)
    pass "class auto disk detection keeps VM class when no NVMe disk is present"
    ;;
  *)
    fail "class auto disk detection keeps VM class when no NVMe disk is present"
    ;;
esac

[ "$FAIL_COUNT" -eq 0 ]
