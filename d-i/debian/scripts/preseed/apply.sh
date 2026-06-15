#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_DIR=${RUNTIME_DIR}/bootstrap
LOG_DIR=${INSTALLER_LOG_DIR:-${INSTALLER_PRESEED_LOG_DIR:-/tmp/preseed-logs}}
LOG=${LOG_DIR}/02-preseed.log
CONTEXT_ENV=${RUNTIME_DIR}/state/context.env

class_list_has_debug() {
  class_list=${1:-}
  for class_token in $(printf '%s\n' "$class_list" | tr ';,' '  '); do
    case "$class_token" in
      debug|debug/debug|debug:debug|debug.debug) return 0 ;;
    esac
  done
  return 1
}

cmdline_classes() {
  [ -r /proc/cmdline ] || return 1
  for arg in $(cat /proc/cmdline 2>/dev/null || true); do
    case "$arg" in
      classes=*|auto-install/classes=*)
        printf '%s\n' "${arg#*=}"
        return 0
        ;;
    esac
  done
  return 1
}

debug_logs_requested() {
  raw_classes=$(cmdline_classes 2>/dev/null || true)
  class_list_has_debug "$raw_classes"
}

apply_logging_policy() {
  if debug_logs_requested; then
    INSTALLER_DEBUG_LOGS=1
    INSTALLER_LOG_LEVEL=debug
  else
    INSTALLER_DEBUG_LOGS=0
    INSTALLER_LOG_LEVEL=none
  fi
  export INSTALLER_DEBUG_LOGS INSTALLER_LOG_LEVEL
}

logging_enabled() {
  case "${INSTALLER_DEBUG_LOGS:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

seed_source_type() {
  case "${1:-}" in
    /*) printf '%s\n' file ;;
    *) printf '%s\n' url ;;
  esac
}

trim_seed_base() {
  seed_base=$1

  while [ "${#seed_base}" -gt 1 ]; do
    case "$seed_base" in
      */) seed_base=${seed_base%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$seed_base"
}

normalize_seed_base() {
  seed_value=$1
  seed_type=$2

  seed_value=${seed_value%%\?*}
  case "$seed_value" in
    */*.cfg) seed_value=${seed_value%/*} ;;
  esac
  seed_value=$(trim_seed_base "$seed_value")

  case "$seed_type" in
    file)
      case "$seed_value" in
        /*) ;;
        *) return 1 ;;
      esac
      ;;
    url)
      [ -n "$seed_value" ] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s\n' "$seed_value"
}

resolve_seed_base() {
  requested_seed_base=${1:-}

  if [ -n "$requested_seed_base" ]; then
    normalize_seed_base "$requested_seed_base" "$(seed_source_type "$requested_seed_base")"
    return 0
  fi

  if [ -r /proc/cmdline ]; then
    for arg in $(cat /proc/cmdline 2>/dev/null || true); do
      case "$arg" in
        preseed/url=*|url=*)
          normalize_seed_base "${arg#*=}" url && return 0
          ;;
        preseed/file=*|file=*)
          normalize_seed_base "${arg#*=}" file && return 0
          ;;
      esac
    done
  fi

  if [ -r "${BOOTSTRAP_DIR}/seed.url" ]; then
    seed_url_base=$(cat "${BOOTSTRAP_DIR}/seed.url" 2>/dev/null || true)
    normalize_seed_base "$seed_url_base" url && return 0
  fi
  if [ -r "${BOOTSTRAP_DIR}/seed.file" ]; then
    seed_file_base=$(cat "${BOOTSTRAP_DIR}/seed.file" 2>/dev/null || true)
    normalize_seed_base "$seed_file_base" file && return 0
  fi

  return 1
}

validate_runtime_reset_base() {
  runtime_reset_base=$1

  case "$runtime_reset_base" in
    ''|/|.|..|*/..|*'/../'*)
      echo "fatal: refusing to reset unsafe INSTALLER_RUNTIME_DIR: ${runtime_reset_base:-unset}" >&2
      exit 1
      ;;
  esac
}

reset_preseed_runtime_for_apply() {
  runtime_reset_base=$1

  validate_runtime_reset_base "$runtime_reset_base"
  rm -rf \
    "${runtime_reset_base}/cache/seed"
  rm -f \
    "${runtime_reset_base}/bootstrap/bootstrap.sh" \
    "${runtime_reset_base}/bootstrap/repo.env" \
    "${runtime_reset_base}/bootstrap/seed.meta"
}

refresh_bootstrap_helper() {
  seed_base=$1
  helper_tmp="${BOOTSTRAP_HELPER}.tmp.$$"
  helper_log="${helper_tmp}.fetch.log"

  rm -f "$helper_tmp" "$helper_log"
  case "$(seed_source_type "$seed_base")" in
    file)
      if cp "${seed_base%/}/scripts/preseed/bootstrap-entry.sh" "$helper_tmp" >"$helper_log" 2>&1; then
        fetch_status=0
      else
        fetch_status=$?
      fi
      ;;
    url)
      if wget --no-verbose --tries=3 --timeout=45 -O "$helper_tmp" "$seed_base/scripts/preseed/bootstrap-entry.sh" >"$helper_log" 2>&1; then
        fetch_status=0
      else
        fetch_status=$?
      fi
      ;;
    *)
      fetch_status=1
      ;;
  esac
  if [ "$fetch_status" -ne 0 ] || [ ! -s "$helper_tmp" ]; then
    [ -s "$helper_log" ] && sed 's/^/[preseed-bootstrap:refresh] /' "$helper_log" >&2 || true
    rm -f "$helper_tmp" "$helper_log"
    return 1
  fi
  mv "$helper_tmp" "$BOOTSTRAP_HELPER"
  chmod 0700 "$BOOTSTRAP_HELPER" 2>/dev/null || true
  rm -f "$helper_log"
  return 0
}

resolve_runtime_log_path() {
  requested_log_path=$1
  printf '%s\n' "$requested_log_path"
}

LOG=$(resolve_runtime_log_path "$LOG")
apply_logging_policy
install -d -m 0700 "$BOOTSTRAP_DIR"
if logging_enabled; then
  install -d -m 0700 "$LOG_DIR"
  : >>"$LOG"
  chmod 0600 "$LOG" 2>/dev/null || true
  exec 2>>"$LOG"
fi

if logging_enabled; then
  echo "[preseed-bootstrap] info: starting apply" >&2
fi

REQUESTED_SEED_BASE=${1:-}
BOOTSTRAP_HELPER=${BOOTSTRAP_DIR}/preseed-bootstrap-entry.sh
BOOTSTRAP_LIB=${BOOTSTRAP_DIR}/bootstrap.sh

if seed_base=$(resolve_seed_base "$REQUESTED_SEED_BASE" 2>/dev/null); then
  # apply is the top of the dynamic preseed pipeline. Discard any runtime
  # bootstrap/cache from earlier attempts so retries refetch the current repo
  # logic. Keep state/context from include_command prepare-context; it is the
  # earliest class detection point, and common/lib.sh regenerates it when stale.
  reset_preseed_runtime_for_apply "$RUNTIME_DIR"
  install -d -m 0700 "$BOOTSTRAP_DIR"
  refresh_bootstrap_helper "$seed_base" || true
fi

if [ -x "$BOOTSTRAP_HELPER" ]; then
  exec "$BOOTSTRAP_HELPER" apply "$LOG" "$REQUESTED_SEED_BASE"
fi

if [ -s "$BOOTSTRAP_LIB" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$BOOTSTRAP_LIB"
  bootstrap_run_preseed_phase apply "$REQUESTED_SEED_BASE" || {
    code=$?
    if logging_enabled; then
      echo "[preseed-bootstrap] fatal: apply failed with status ${code} (see ${LOG})" >&2
    else
      echo "[preseed-bootstrap] fatal: apply failed with status ${code}" >&2
    fi
    exit "$code"
  }
  exit 0
fi

echo "fatal: local bootstrap entry helper is missing before preseed/run: ${BOOTSTRAP_HELPER}" >&2
exit 1
