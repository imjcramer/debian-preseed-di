#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/class-plan-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=5
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

install_conf="$ROOT_DIR/d-i/debian/classes/install.conf"
if grep -q '^ManifestVersion: 5$' "$install_conf" &&
   grep -q '^ClassTokenFormats: bare, group/class, group:class, group.class$' "$install_conf" &&
   grep -q '^Config: classes/configs/groups.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/addons.cfg$' "$install_conf"; then
  pass "install.conf declares manifest metadata and config sources"
else
  fail "install.conf declares manifest metadata and config sources"
fi

runtime_dir="$TMP_DIR/runtime"
plan_out="$TMP_DIR/plan.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian"
  INSTALLER_RUNTIME_DIR="$runtime_dir"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
  installer_classes_cache_ensure
  printf '%s\n' "$(installer_classes_plan_path)"
  printf '%s\n' "$(installer_classes_conf_path)"
) >"$plan_out"; then
  plan_path=$(sed -n '1p' "$plan_out")
  state_path=$(sed -n '2p' "$plan_out")
  if [ -s "$plan_path" ] && [ -s "$state_path" ]; then
    pass "class planner materializes plan.tsv and generated state config"
  else
    fail "class planner materializes plan.tsv and generated state config"
  fi
else
  fail "class planner materializes plan.tsv and generated state config"
fi

plan_path=$(sed -n '1p' "$plan_out")
if grep -q '^manifest	version	5$' "$plan_path" &&
   grep -q '^group	disk	true	__EMPTY__	90	storage	class-auto	auto-detected storage family and host profile derivation$' "$plan_path" &&
   grep -q '^class	addon	timeshift	opt-in Timeshift Btrfs snapshots with managed GRUB snapshot integration' "$plan_path"; then
  pass "generated plan.tsv contains manifest, group, and class rows"
else
  fail "generated plan.tsv contains manifest, group, and class rows"
fi

context_runtime="$TMP_DIR/context-runtime"
context_out="$TMP_DIR/context.out"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian"
  INSTALLER_RUNTIME_DIR="$context_runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,timeshift'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$ROOT_DIR/d-i/debian" >/dev/null
  sed -n 's/^selected_class_refs=//p' "$(installer_runtime_install_conf_path)"
) >"$context_out"; then
  if grep -qx 'site/lab role/desktop arch/amd64 cpu/intel gpu/generic security/standard network/dhcp disk/nvme addon/timeshift' "$context_out"; then
    pass "runtime install.conf is generated from the config-backed class plan"
  else
    fail "runtime install.conf is generated from the config-backed class plan"
  fi
else
  fail "runtime install.conf is generated from the config-backed class plan"
fi

reject_root="$TMP_DIR/reject-root"
mkdir -p "$reject_root"
cp "$ROOT_DIR/d-i/debian/repo.env" "$reject_root/repo.env"
cp -a "$ROOT_DIR/d-i/debian/classes" "$reject_root/classes"
cat >>"$reject_root/classes/configs/addons.cfg" <<'EOF'

Type: class
Group: addon
Name: rejectpod
Description: reject podman when both are selected
RejectedClasses: addon/podman
EOF
cat >"$reject_root/classes/class-addon/rejectpod.cfg" <<'EOF'
d-i pkgsel/include string
d-i pkgsel/include seen true
EOF
reject_err="$TMP_DIR/reject.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$reject_root"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/reject-runtime"
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
  installer_auto_class_tokens() {
    printf '%s\n' amd64
    printf '%s\n' intel
    printf '%s\n' generic
    printf '%s\n' nvme
  }
  installer_cmdline_value() {
    case "$1" in
      auto-install/classes|classes)
        printf '%s\n' 'lab,desktop,standard,dhcp,podman,rejectpod'
        ;;
    esac
  }
  installer_debconf_value() { return 1; }
  installer_write_context "$reject_root" >/dev/null
) >"$TMP_DIR/reject.out" 2>"$reject_err"; then
  fail "config-backed rejected class rules are enforced"
elif grep -q 'selected class addon/rejectpod rejects class addon/podman' "$reject_err"; then
  pass "config-backed rejected class rules are enforced"
else
  fail "config-backed rejected class rules are enforced"
fi

[ "$FAIL_COUNT" -eq 0 ]
