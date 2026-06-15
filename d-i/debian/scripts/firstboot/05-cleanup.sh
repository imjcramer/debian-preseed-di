#!/bin/sh
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

FIRSTBOOT_LOG_DIR=${FIRSTBOOT_LOG_DIR:-/var/lib/preseed/logs/firstboot}
FIRSTBOOT_DATA_DIR=${FIRSTBOOT_DATA_DIR:-${FIRSTBOOT_LOG_DIR}/data}
FIRSTBOOT_STATE_DIR=${FIRSTBOOT_STATE_DIR:-/var/lib/preseed/firstboot}
FIRSTBOOT_LOG_FILE=${FIRSTBOOT_LOG_FILE:-${FIRSTBOOT_LOG_DIR}/20-firstboot.log}
FIRSTBOOT_COMPLETE_FILE=${FIRSTBOOT_COMPLETE_FILE:-${FIRSTBOOT_STATE_DIR}/complete}
CLEANUP_LOG=${FIRSTBOOT_DATA_DIR}/cleanup.txt
INITRAMFS_SCRIPT_ROOT=${INITRAMFS_SCRIPT_ROOT:-/etc/initramfs-tools/scripts}

mkdir -p "$FIRSTBOOT_LOG_DIR" "$FIRSTBOOT_DATA_DIR" "$FIRSTBOOT_STATE_DIR" 2>/dev/null || exit 0
: >>"$FIRSTBOOT_LOG_FILE" 2>/dev/null || exit 0
: >"$CLEANUP_LOG" 2>/dev/null || exit 0
chmod 0600 "$CLEANUP_LOG" 2>/dev/null || true
cleanup_failures=0

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s\n' unknown-time
}

log_line() {
  stage=$1
  level=$2
  component=$3
  shift 3
  printf '%s stage=%s level=%s component=%s %s\n' \
    "$(timestamp)" "$stage" "$level" "$component" "$*" >>"$FIRSTBOOT_LOG_FILE"
}

if [ -r /usr/local/lib/firstboot.d/logging.sh ]; then
  # shellcheck disable=SC1091
  . /usr/local/lib/firstboot.d/logging.sh
fi

run_cleanup_command() {
  label=$1
  shift
  {
    printf '# %s\n' "$label"
    "$@"
    printf 'status=0\n'
  } >>"$CLEANUP_LOG" 2>&1 || {
    status=$?
    printf 'status=%s\n' "$status" >>"$CLEANUP_LOG"
    log_line cleanup warn cleanup "${label}=failed status=${status}"
    cleanup_failures=$((cleanup_failures + 1))
    return 0
  }
}

write_complete_marker() {
  tmp_complete="${FIRSTBOOT_COMPLETE_FILE}.tmp.$$"
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'status=%s\n' "${FIRSTBOOT_OVERALL_STATUS:-0}"
    printf 'log_dir=%s\n' "$FIRSTBOOT_LOG_DIR"
  } >"$tmp_complete" 2>/dev/null || return 0
  chmod 0600 "$tmp_complete" 2>/dev/null || true
  mv "$tmp_complete" "$FIRSTBOOT_COMPLETE_FILE" 2>/dev/null || rm -f "$tmp_complete"
}

log_line cleanup info cleanup "cleanup_start=true"

remove_initramfs_health_hooks() {
  for hook_path in \
    "${INITRAMFS_SCRIPT_ROOT}/init-top/health-init-top" \
    "${INITRAMFS_SCRIPT_ROOT}/local-top/health-local-top" \
    "${INITRAMFS_SCRIPT_ROOT}/local-premount/health-local-premount" \
    "${INITRAMFS_SCRIPT_ROOT}/local-bottom/health-local-bottom" \
    "${INITRAMFS_SCRIPT_ROOT}/init-bottom/health-init-bottom"
  do
    [ -e "$hook_path" ] || [ -L "$hook_path" ] || continue
    if rm -f "$hook_path" 2>/dev/null; then
      log_line cleanup info initramfs "removed_hook=${hook_path}"
    else
      log_line cleanup warn initramfs "remove_failed=${hook_path}"
    fi
  done
}

remove_initramfs_health_hooks

if [ -x /usr/sbin/update-initramfs ]; then
  run_cleanup_command "update-initramfs" /usr/sbin/update-initramfs -u -k all
else
  log_line cleanup warn initramfs "update-initramfs=missing"
  cleanup_failures=$((cleanup_failures + 1))
fi

if command -v systemctl >/dev/null 2>&1; then
  run_cleanup_command "disable firstboot.service" systemctl disable firstboot.service
fi

rm -f /etc/systemd/system/sysinit.target.wants/firstboot.service 2>/dev/null || true
rm -f /etc/systemd/system/firstboot.service 2>/dev/null || true
rm -f /usr/local/sbin/firstboot.sh 2>/dev/null || true
rm -rf /usr/local/lib/firstboot.d 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  run_cleanup_command "daemon-reload" systemctl daemon-reload
  run_cleanup_command "reset-failed firstboot.service" systemctl reset-failed firstboot.service
fi

if [ "$cleanup_failures" -gt 0 ]; then
  FIRSTBOOT_OVERALL_STATUS=1
fi
write_complete_marker

log_line cleanup info cleanup "service_removed=true complete_marker=${FIRSTBOOT_COMPLETE_FILE} cleanup_failures=${cleanup_failures}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --no-block stop firstboot.service >/dev/null 2>&1 || true
fi

if [ "$cleanup_failures" -gt 0 ]; then
  exit 1
fi
exit 0
