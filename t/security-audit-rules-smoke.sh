#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=10
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

standard_rules="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/audit/standard/rules.d/10-security-standard.rules"
enhanced_rules="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/audit/enhanced/rules.d/10-security-enhanced.rules"
security_script="$ROOT_DIR/d-i/debian/scripts/late/security.sh"
augenrules_wrapper="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/sbin/augenrules-quiet"
auditd_override="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/systemd/system/auditd.service.d/override.conf"

if awk '/^[[:space:]]*-/ && /(^|[[:space:]])-F[[:space:]]+arch=/ && !/(^|[[:space:]])-S[[:space:]]+/ { exit 1 }' "$standard_rules"; then
  pass "standard audit rules keep syscall selectors on every arch-qualified rule"
else
  fail "standard audit rules keep syscall selectors on every arch-qualified rule"
fi

if awk '/^[[:space:]]*-/ && /(^|[[:space:]])-F[[:space:]]+arch=/ && !/(^|[[:space:]])-S[[:space:]]+/ { exit 1 }' "$enhanced_rules"; then
  pass "enhanced audit rules keep syscall selectors on every arch-qualified rule"
else
  fail "enhanced audit rules keep syscall selectors on every arch-qualified rule"
fi

if grep -q '^-a always,exit -F arch=b64 -S execve -S execveat -F path=/usr/bin/sudo -F perm=x -F key=privilege-escalation$' "$standard_rules" &&
   grep -q '^-a always,exit -F arch=b64 -S execve -S execveat -F path=/usr/bin/sudo -F perm=x -F key=privilege-escalation$' "$enhanced_rules"; then
  pass "sudo execution auditing uses explicit exec syscalls in both profiles"
else
  fail "sudo execution auditing uses explicit exec syscalls in both profiles"
fi

if grep -q '^-a always,exit -F arch=b64 -S openat .* -F dir=/etc/apparmor.d -F perm=wa -F key=apparmor-policy$' "$standard_rules" &&
   grep -q '^-a always,exit -F arch=b64 -S openat .* -F dir=/etc/apparmor.d -F perm=wa -F key=apparmor-policy$' "$enhanced_rules"; then
  pass "AppArmor policy auditing uses syscall-form write and attribute selectors"
else
  fail "AppArmor policy auditing uses syscall-form write and attribute selectors"
fi

if grep -q 'audit rules with arch= must include explicit syscall selectors' "$security_script"; then
  pass "late security hook still enforces the syscall-selector contract"
else
  fail "late security hook still enforces the syscall-selector contract"
fi

if grep -q 'must not use trailing slashes in dir= filters' "$security_script"; then
  pass "late security hook still enforces trailing-slash-free dir filters"
else
  fail "late security hook still enforces trailing-slash-free dir filters"
fi

totem_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apparmor.d/usr.bin.totem"
apt_cacher_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apparmor.d/usr.sbin.apt-cacher-ng"
avahi_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apparmor.d/usr.sbin.avahi-daemon"

if grep -q '^profile /usr/bin/totem /usr/bin/totem flags=(attach_disconnected, complain)' "$totem_profile" &&
   grep -q '^  profile sanitized_helper flags=(attach_disconnected, complain)' "$totem_profile" &&
   grep -q '^profile apt-cacher-ng /usr/sbin/apt-cacher-ng flags=(attach_disconnected, complain)' "$apt_cacher_profile" &&
   grep -q '^profile avahi-daemon /usr/sbin/avahi-daemon flags=(attach_disconnected, complain)' "$avahi_profile"; then
  pass "managed AppArmor profiles cover totem, apt-cacher-ng, avahi-daemon, and the totem sanitized helper"
else
  fail "managed AppArmor profiles cover totem, apt-cacher-ng, avahi-daemon, and the totem sanitized helper"
fi

if ! grep -Eq 'flags=.*(unconfined|default_allow)' "$totem_profile" "$apt_cacher_profile" "$avahi_profile"; then
  pass "managed AppArmor profiles avoid unconfined and default_allow modes"
else
  fail "managed AppArmor profiles avoid unconfined and default_allow modes"
fi

if grep -q 'apparmor_managed_profile_files()' "$security_script" &&
   grep -q 'usr.bin.totem' "$security_script" &&
   grep -q 'usr.sbin.apt-cacher-ng' "$security_script" &&
   grep -q 'usr.sbin.avahi-daemon' "$security_script" &&
   grep -q 'apparmor_parser -q -Q -K -T' "$security_script"; then
  pass "late security hook stages and syntax-checks managed AppArmor profiles"
else
  fail "late security hook stages and syntax-checks managed AppArmor profiles"
fi

if grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET usr/local/sbin/augenrules-quiet)" "/usr/local/sbin/augenrules-quiet" 0755' "$security_script" &&
   grep -q 'stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET etc/systemd/system/auditd.service.d/override.conf)" "/etc/systemd/system/auditd.service.d/override.conf" 0644' "$security_script" &&
   grep -q '^ExecStartPost=-/usr/local/sbin/augenrules-quiet --load$' "$auditd_override" &&
   grep -Fq "'No rules'" "$augenrules_wrapper" &&
   grep -Fq "'No change'" "$augenrules_wrapper" &&
   grep -Fq "'loginuid_immutable '[0-9]*" "$augenrules_wrapper" &&
   grep -Fq "'failure '[0-9]*" "$augenrules_wrapper"; then
  pass "auditd staging routes augenrules through a broader status-line filter without removing real stderr output"
else
  fail "auditd staging routes augenrules through a broader status-line filter without removing real stderr output"
fi

[ "$FAIL_COUNT" -eq 0 ]
