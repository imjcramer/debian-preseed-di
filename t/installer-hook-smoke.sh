#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/installer-hook-smoke.XXXXXX")
TEST_COUNT=3
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

PATH=/bin
export PATH
# shellcheck disable=SC1090
. "$ROOT_DIR/d-i/debian/scripts/common/hook.sh"

case ":$PATH:" in
  *:/sbin:*:*:/usr/sbin:*|*:/sbin:*|*:/usr/sbin:*)
    pass "installer hook path includes sbin directories"
    ;;
  *)
    fail "installer hook path includes sbin directories"
    ;;
esac

nvme_candidates=$(hook_nvme_install_disk_candidates "/dev/vd* /dev/nvme*n* /dev/sd*")
if [ "$nvme_candidates" = "/dev/nvme*n*" ]; then
  pass "nvme candidate filter excludes virtual and SCSI fallbacks"
else
  fail "nvme candidate filter excludes virtual and SCSI fallbacks"
fi

pci_root="$TMP_DIR/pci"
mkdir -p "$pci_root/0000:00:01.0"
printf '0x144d\n' >"$pci_root/0000:00:01.0/vendor"
printf '0x010802\n' >"$pci_root/0000:00:01.0/class"
if INSTALLER_PCI_DEVICES_ROOT="$pci_root" hook_nvme_controller_present; then
  pass "hook detects NVMe controller from PCI class"
else
  fail "hook detects NVMe controller from PCI class"
fi

[ "$FAIL_COUNT" -eq 0 ]
