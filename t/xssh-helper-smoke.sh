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

server_role="$ROOT_DIR/d-i/debian/classes/class-select/role/server.cfg"
desktop_role="$ROOT_DIR/d-i/debian/classes/class-select/role/desktop.cfg"
ssh_common="$ROOT_DIR/d-i/debian/scripts/common/ssh.sh"
btrfs_late="$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh"
f2fs_late="$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"
xssh_send="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/bin/xssh-send"
xssh_retrieve="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/bin/xssh-retrieve"

if grep -q '^d-i pkgsel/include string sudo openssh-client$' "$server_role"; then
  pass "server role installs openssh-client for xssh helpers"
else
  fail "server role installs openssh-client for xssh helpers"
fi

if grep -q ' openssh-client ' "$desktop_role"; then
  pass "desktop role installs openssh-client for xssh helpers"
else
  fail "desktop role installs openssh-client for xssh helpers"
fi

if grep -q '^stage_target_xssh_helpers() {$' "$ssh_common" &&
   grep -q 'installer_selected_class_reference_is_selected role/server' "$ssh_common" &&
   grep -q 'installer_selected_class_reference_is_selected role/desktop' "$ssh_common" &&
   grep -q 'openssh-client must be preinstalled by pkgsel' "$ssh_common" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/bin/xssh-send)" "${FILE_XSSH_SEND}" 0755' "$ssh_common" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/bin/xssh-retrieve)" "${FILE_XSSH_RETRIEVE}" 0755' "$ssh_common"; then
  pass "shared SSH helper stages xssh tooling only for server and desktop roles"
else
  fail "shared SSH helper stages xssh tooling only for server and desktop roles"
fi

if grep -q 'stage_target_xssh_helpers' "$btrfs_late" &&
   grep -q 'stage_target_xssh_helpers' "$f2fs_late"; then
  pass "both storage families stage xssh helpers after package repair"
else
  fail "both storage families stage xssh helpers after package repair"
fi

if grep -q '^usage: .*--dest-ip <ip-or-host> --port <ssh-port>' "$xssh_send" &&
   grep -q 'scp -r -P "\$port"' "$xssh_send" &&
   grep -q 'send completed:' "$xssh_send"; then
  pass "xssh-send validates flags and uses recursive scp with explicit completion output"
else
  fail "xssh-send validates flags and uses recursive scp with explicit completion output"
fi

if grep -q '^usage: .*--remote-ip <ip-or-host> --port <ssh-port>' "$xssh_retrieve" &&
   grep -q 'scp -r -P "\$port"' "$xssh_retrieve" &&
   grep -q 'retrieve completed:' "$xssh_retrieve"; then
  pass "xssh-retrieve validates flags and uses recursive scp with explicit completion output"
else
  fail "xssh-retrieve validates flags and uses recursive scp with explicit completion output"
fi

[ "$FAIL_COUNT" -eq 0 ]
