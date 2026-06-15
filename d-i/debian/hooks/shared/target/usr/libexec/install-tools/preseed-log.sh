#!/bin/sh
# Shared installed-target logging helper. This file is sourced.

preseed_log_canonical() {
  case "${1:-error}" in
    debug|DEBUG) printf '%s\n' debug ;;
    info|INFO) printf '%s\n' info ;;
    warn|WARN|warning|WARNING) printf '%s\n' warning ;;
    error|ERROR|fatal|FATAL) printf '%s\n' error ;;
    none|NONE) printf '%s\n' none ;;
    *) return 1 ;;
  esac
}

preseed_log_level_value() {
  case "$1" in
    debug) printf '%s\n' 10 ;;
    info) printf '%s\n' 20 ;;
    warning) printf '%s\n' 30 ;;
    error) printf '%s\n' 40 ;;
    none) printf '%s\n' 99 ;;
    *) return 1 ;;
  esac
}

preseed_log_raw_error() {
  printf 'error: %s\n' "$*" >&2
}

preseed_log_init() {
  PRESEED_LOG_TAG=$1
  PRESEED_LOG_LEVEL_VAR=$2
  PRESEED_LOG_DEFAULT_LEVEL=${3:-error}

  case "$PRESEED_LOG_LEVEL_VAR" in
    ''|[!ABCDEFGHIJKLMNOPQRSTUVWXYZ_]*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      preseed_log_raw_error "invalid log level variable name: ${PRESEED_LOG_LEVEL_VAR:-unset}"
      exit 1
      ;;
    *)
      ;;
  esac

  # shellcheck disable=SC2086,SC2154
  eval "preseed_log_raw_level=\${$PRESEED_LOG_LEVEL_VAR-}"
  [ -n "$preseed_log_raw_level" ] || preseed_log_raw_level=$PRESEED_LOG_DEFAULT_LEVEL
  PRESEED_LOG_ACTIVE_LEVEL=$(preseed_log_canonical "$preseed_log_raw_level") || {
    preseed_log_raw_error "${PRESEED_LOG_LEVEL_VAR} must be debug, info, warning, error, or none"
    exit 1
  }
  PRESEED_LOG_ACTIVE_VALUE=$(preseed_log_level_value "$PRESEED_LOG_ACTIVE_LEVEL") || exit 1
  PRESEED_LOGGER=
  PRESEED_LOGGER_READY=0
}

preseed_log_should_emit() {
  preseed_requested_level=$(preseed_log_canonical "$1") || preseed_requested_level=error
  [ "$preseed_requested_level" = error ] && return 0
  [ "${PRESEED_LOG_ACTIVE_LEVEL:-error}" != none ] || return 1
  preseed_requested_value=$(preseed_log_level_value "$preseed_requested_level") || return 1
  [ "$preseed_requested_value" -ge "${PRESEED_LOG_ACTIVE_VALUE:-40}" ]
}

preseed_log_ensure_logger() {
  [ "${PRESEED_LOGGER_READY:-0}" = 1 ] && return 0
  PRESEED_LOGGER=$(command -v logger 2>/dev/null || true)
  PRESEED_LOGGER_READY=1
}

log() {
  preseed_log_level=info
  preseed_log_message=$*
  case "$preseed_log_message" in
    debug:\ *) preseed_log_level=debug; preseed_log_message=${preseed_log_message#debug: } ;;
    info:\ *) preseed_log_level=info; preseed_log_message=${preseed_log_message#info: } ;;
    warn:\ *) preseed_log_level=warning; preseed_log_message=${preseed_log_message#warn: } ;;
    warning:\ *) preseed_log_level=warning; preseed_log_message=${preseed_log_message#warning: } ;;
    error:\ *) preseed_log_level=error; preseed_log_message=${preseed_log_message#error: } ;;
    fatal:\ *) preseed_log_level=error; preseed_log_message=${preseed_log_message#fatal: } ;;
  esac

  preseed_log_should_emit "$preseed_log_level" || return 0
  preseed_log_line="${preseed_log_level}: ${preseed_log_message}"
  printf '%s\n' "$preseed_log_line" >&2
  preseed_log_ensure_logger
  if [ -n "${PRESEED_LOGGER:-}" ]; then
    "$PRESEED_LOGGER" -t "${PRESEED_LOG_TAG:-preseed}" -- "$preseed_log_line" 2>/dev/null || true
  fi
}

fatal() {
  log "fatal: $*"
  exit 1
}
