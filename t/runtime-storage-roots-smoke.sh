#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=6
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

runtime_env="$ROOT_DIR/d-i/debian/hosts/shared/runtime.env"
storage_script="$ROOT_DIR/d-i/debian/scripts/late/storage-maintenance.sh"
asset_script="$ROOT_DIR/d-i/debian/scripts/late/target-assets.sh"
template_script="$ROOT_DIR/d-i/debian/scripts/late/templates.sh"
tmpfiles_roots="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/tmpfiles.d/10-runtime-storage-roots.conf"

if grep -q '^DIR_DATA_CONFIG="${DIR_DATA}/config"$' "$runtime_env" &&
   grep -q '^DIR_DATA_SERVICES_USR="${DIR_DATA_SERVICES}/usr"$' "$runtime_env" &&
   grep -q '^DIR_DATA_BIN="${DIR_DATA}/bin"$' "$runtime_env" &&
   grep -q '^DIR_DATA_DOCS="${DIR_DATA}/docs"$' "$runtime_env" &&
   grep -q '^DIR_DATA_DOWNLOADS="${DIR_DATA}/downloads"$' "$runtime_env" &&
   grep -q '^DIR_DATA_PKI="${DIR_DATA}/pki"$' "$runtime_env" &&
   grep -q '^DIR_DATA_BACKUP="${DIR_DATA}/backup"$' "$runtime_env" &&
   grep -q '^DIR_POOL_BUILD="${DIR_POOL}/build"$' "$runtime_env" &&
   grep -q '^DIR_POOL_PODMAN="${DIR_POOL}/podman"$' "$runtime_env" &&
   grep -q '^DIR_POOL_LOG="${DIR_POOL}/log"$' "$runtime_env" &&
   ! grep -q '^DIR_POOL_BUILDS=' "$runtime_env"; then
  pass "shared runtime env defines the always-present /data and /pool roots without DIR_POOL_BUILDS"
else
  fail "shared runtime env defines the always-present /data and /pool roots without DIR_POOL_BUILDS"
fi

if grep -q '^d __INSTALLER_DIR_DATA__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_CONFIG__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_SERVICES_USR__ 0755 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_DOCS__ 2750 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_DOWNLOADS__ 2750 __INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_PKI__ 0700 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_DATA_BACKUP__ 0700 root root -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL__ 2775 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_BUILD__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_BUILD_RUNNERS__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_CACHE__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_CACHE_RUNNERS__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_DB__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_PODMAN__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_LOG__ 2770 root devops -$' "$tmpfiles_roots" &&
   grep -q '^d __INSTALLER_DIR_POOL_APTLY__ 2770 root devops -$' "$tmpfiles_roots"; then
  pass "tmpfiles root policy recreates the shared /data and /pool runtime roots"
else
  fail "tmpfiles root policy recreates the shared /data and /pool runtime roots"
fi

if grep -q '^normalize_target_tmpfiles_directory_policy() {$' "$storage_script" &&
   grep -q '^stage_target_runtime_storage_root_policy() {$' "$storage_script" &&
   grep -q '^    0\[0-7\]\[0-7\]\[0-7\]\[0-7\])$' "$storage_script" &&
   grep -q '^      entry_mode=\${entry_mode#0}$' "$storage_script" &&
   grep -q 'render_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/tmpfiles.d/10-runtime-storage-roots.conf)" "/etc/tmpfiles.d/10-runtime-storage-roots.conf" 0644' "$storage_script" &&
   grep -q 'normalize_target_tmpfiles_directory_policy "/etc/tmpfiles.d/10-runtime-storage-roots.conf" "shared runtime storage roots"' "$storage_script"; then
  pass "storage maintenance stages the runtime-root tmpfiles policy and normalizes shared storage roots from that single policy"
else
  fail "storage maintenance stages the runtime-root tmpfiles policy and normalizes shared storage roots from that single policy"
fi

if grep -q 'ensure_target_managed_runtime_storage_roots' "$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh" &&
   grep -q 'ensure_target_managed_runtime_storage_roots' "$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"; then
  pass "both storage families invoke the shared runtime-root creator"
else
  fail "both storage families invoke the shared runtime-root creator"
fi

if grep -q '\[ -d "\$target_parent" \] || install -d -m 0755 "\$target_parent"' "$asset_script" &&
   grep -q '\[ -d "\$dest_parent" \] || install -d -m 0755 "\$dest_parent"' "$template_script"; then
  pass "target asset and template helpers preserve existing normalized parent-directory modes"
else
  fail "target asset and template helpers preserve existing normalized parent-directory modes"
fi

if grep -q '^target_helper_doc_owner_ids() {$' "$asset_script" &&
   grep -q '^target_chown_helper_doc_path() {$' "$asset_script" &&
   grep -q 'ACCOUNT_USERNAME must be set before staging helper docs' "$asset_script" &&
   grep -q "awk -F: -v wanted_user=\"\$ACCOUNT_USERNAME\" '\$1 == wanted_user { print \$3 \":\" \$4; exit }' /target/etc/passwd" "$asset_script" &&
   grep -q 'chown "\$helper_doc_owner_ids" "\$doc_host_path"' "$asset_script"; then
  pass "helper docs inherit the primary-user ownership contract instead of landing as root-owned files"
else
  fail "helper docs inherit the primary-user ownership contract instead of landing as root-owned files"
fi

[ "$FAIL_COUNT" -eq 0 ]
