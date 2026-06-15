#!/bin/sh
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

FIRSTBOOT_LOG_DIR=${FIRSTBOOT_LOG_DIR:-/var/lib/preseed/logs/firstboot}
FIRSTBOOT_DATA_DIR=${FIRSTBOOT_DATA_DIR:-${FIRSTBOOT_LOG_DIR}/data}
FIRSTBOOT_STATE_DIR=${FIRSTBOOT_STATE_DIR:-/var/lib/preseed/firstboot}
FIRSTBOOT_SCRIPT_DIR=${FIRSTBOOT_SCRIPT_DIR:-/usr/local/lib/firstboot.d}
FIRSTBOOT_LOG_FILE=${FIRSTBOOT_LOG_FILE:-${FIRSTBOOT_LOG_DIR}/20-firstboot.log}
FIRSTBOOT_STATUS_FILE=${FIRSTBOOT_STATUS_FILE:-${FIRSTBOOT_LOG_DIR}/status.env}
FIRSTBOOT_COMPLETE_FILE=${FIRSTBOOT_COMPLETE_FILE:-${FIRSTBOOT_STATE_DIR}/complete}
export FIRSTBOOT_LOG_DIR FIRSTBOOT_DATA_DIR FIRSTBOOT_STATE_DIR
export FIRSTBOOT_SCRIPT_DIR FIRSTBOOT_LOG_FILE FIRSTBOOT_STATUS_FILE
export FIRSTBOOT_COMPLETE_FILE

mkdir -p "$FIRSTBOOT_LOG_DIR" "$FIRSTBOOT_DATA_DIR" "$FIRSTBOOT_STATE_DIR" 2>/dev/null || exit 0
: >>"$FIRSTBOOT_LOG_FILE" 2>/dev/null || exit 0
chmod 0600 "$FIRSTBOOT_LOG_FILE" 2>/dev/null || true

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s\n' unknown-time
}

log_line() {
  stage=$1
  level=$2
  component=$3
  shift 3
  printf '%s stage=%s level=%s component=%s %s\n' \
    "$(timestamp)" \
    "$stage" \
    "$level" \
    "$component" \
    "$*" >>"$FIRSTBOOT_LOG_FILE"
}

if [ -r "${FIRSTBOOT_SCRIPT_DIR}/logging.sh" ]; then
  # shellcheck disable=SC1090
  . "${FIRSTBOOT_SCRIPT_DIR}/logging.sh"
fi

write_status() {
  status_value=$1
  tmp_status="${FIRSTBOOT_STATUS_FILE}.tmp.$$"
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'status=%s\n' "$status_value"
  } >"$tmp_status" 2>/dev/null || return 0
  chmod 0600 "$tmp_status" 2>/dev/null || true
  mv "$tmp_status" "$FIRSTBOOT_STATUS_FILE" 2>/dev/null || rm -f "$tmp_status"
}

run_step() {
  script_name=$1
  script_path="${FIRSTBOOT_SCRIPT_DIR}/${script_name}"

  if [ ! -x "$script_path" ]; then
    log_line first_boot error firstboot "missing_stage=${script_path}"
    return 127
  fi

  log_line first_boot info firstboot "start_stage=${script_name}"
  "$script_path" >>"$FIRSTBOOT_LOG_FILE" 2>&1
  step_status=$?
  if [ "$step_status" -eq 0 ]; then
    log_line first_boot info firstboot "completed_stage=${script_name}"
  else
    log_line first_boot error firstboot "failed_stage=${script_name} status=${step_status}"
  fi
  return "$step_status"
}

overall_status=0
log_line systemd-start info firstboot "wrapper_start=true"
log_line systemd-start info firstboot "hostname=$(hostname 2>/dev/null || printf unknown)"
log_line systemd-start info firstboot "kernel=$(uname -r 2>/dev/null || printf unknown)"

for stage_script in 01-early.sh 02-collect.sh 03-network.sh 04-validation.sh; do
  if ! run_step "$stage_script"; then
    overall_status=1
  fi
done

FIRSTBOOT_OVERALL_STATUS=$overall_status
export FIRSTBOOT_OVERALL_STATUS
write_status "$overall_status"

if ! run_step 05-cleanup.sh; then
  overall_status=1
  FIRSTBOOT_OVERALL_STATUS=$overall_status
  export FIRSTBOOT_OVERALL_STATUS
  write_status "$overall_status"
fi

if [ "$overall_status" -eq 0 ]; then
  log_line complete info firstboot "firstboot_status=pass"
else
  log_line complete warn firstboot "firstboot_status=diagnostic-failures-recorded"
fi

exit 0
