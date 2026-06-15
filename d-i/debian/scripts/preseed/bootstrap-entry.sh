#!/bin/sh
set -eu

phase=${1:-}
log_path=${2:-}
requested_seed_base=${3:-}
RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_DIR=${RUNTIME_DIR}/bootstrap
LOG_DIR=${INSTALLER_LOG_DIR:-${INSTALLER_PRESEED_LOG_DIR:-/tmp/preseed-logs}}
SEED_URL_PATH=${BOOTSTRAP_DIR}/seed.url
SEED_FILE_PATH=${BOOTSTRAP_DIR}/seed.file
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${BOOTSTRAP_DIR}/bootstrap.sh}
BOOTSTRAP_SEED_META=${BOOTSTRAP_DIR}/seed.meta
CONTEXT_ENV=${RUNTIME_DIR}/state/context.env

usage() {
  echo "usage: ${0##*/} {prepare-context|apply|early|partman|late} [log-path] [seed-base]" >&2
  exit 1
}

phase_default_log() {
  case "$1" in
    prepare-context|apply|early) printf '%s/%s\n' "$LOG_DIR" 02-preseed.log ;;
    partman) printf '%s/%s\n' "$LOG_DIR" 05-partman.log ;;
    late) printf '%s/%s\n' "$LOG_DIR" 09-late.log ;;
    *) return 1 ;;
  esac
}

class_list_has_debug() {
  class_list=${1:-}

  for class_token in $(printf '%s\n' "$class_list" | tr ';,' '  '); do
    case "$class_token" in
      debug|debug/debug|debug:debug|debug.debug)
        return 0
        ;;
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
  if [ -r "$CONTEXT_ENV" ]; then
    # shellcheck disable=SC1090
    . "$CONTEXT_ENV"
    class_list_has_debug "${INSTALLER_SELECTED_CLASS_REFS:-}" && return 0
    class_list_has_debug "${INSTALLER_SELECTED_CLASSES:-}" && return 0
    class_list_has_debug "${INSTALLER_CLASSES_RAW:-${CLASSES:-}}" && return 0
  fi

  if [ -r "${RUNTIME_DIR}/state/classes.raw" ]; then
    cached_classes=$(cat "${RUNTIME_DIR}/state/classes.raw" 2>/dev/null || true)
    class_list_has_debug "$cached_classes" && return 0
  fi

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

log_path_is_numbered() {
  path_name=${1##*/}
  case "$path_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

log_sequence_file() {
  printf '%s/.log-sequence\n' "$1"
}

next_log_sequence() {
  log_dir=$1
  sequence_path=$(log_sequence_file "$log_dir")
  sequence_tmp="${sequence_path}.tmp.$$"
  current_sequence=0

  [ -d "$log_dir" ] || install -d -m 0700 "$log_dir"
  if [ -r "$sequence_path" ]; then
    current_sequence=$(cat "$sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$current_sequence" in
    ''|*[!0-9]*) current_sequence=0 ;;
  esac

  next_sequence=$((current_sequence + 1))
  printf '%s\n' "$next_sequence" >"$sequence_tmp"
  mv "$sequence_tmp" "$sequence_path"
  chmod 0600 "$sequence_path" 2>/dev/null || true
  printf '%s\n' "$next_sequence"
}

resolve_runtime_log_path() {
  requested_log_path=$1
  printf '%s\n' "$requested_log_path"
}

log() {
  case "$*" in
    fatal:\ *|error:\ *) ;;
    *) logging_enabled || return 0 ;;
  esac
  printf '[preseed-bootstrap] %s\n' "$*" >&2
}

fatal() {
  log "fatal: $*"
  exit 1
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

assign_normalized_seed_base() {
  output_var_name=$1
  seed_base=$2
  seed_type=$3
  seed_label=$4

  seed_base=${seed_base%%\?*}
  case "$seed_base" in
    */*.cfg) seed_base=${seed_base%/*} ;;
  esac
  seed_base=$(trim_seed_base "$seed_base")

  case "$seed_type" in
    file)
      case "$seed_base" in
        /*) ;;
        *) fatal "${seed_label} file base must be an absolute path: ${seed_base:-unset}" ;;
      esac
      case "$seed_base" in
        *..*|*//*)
          fatal "${seed_label} file base contains unsupported traversal: $seed_base"
          ;;
      esac
      ;;
    url)
      [ -n "$seed_base" ] || fatal "${seed_label} URL base is empty"
      ;;
    *)
      fatal "unsupported installation source type for ${seed_label}: $seed_type"
      ;;
  esac

  eval "$output_var_name=\$seed_base"
}

choose_seed_base_from_pair() {
  seed_url_base=$1
  seed_file_base=$2
  seed_label=$3

  if [ -n "$seed_url_base" ] && [ -n "$seed_file_base" ]; then
    fatal "${seed_label} defines both URL and file seed sources"
  fi
  if [ -n "$seed_url_base" ]; then
    assign_normalized_seed_base RESOLVED_SEED_BASE "$seed_url_base" url "$seed_label"
    return 0
  fi
  if [ -n "$seed_file_base" ]; then
    assign_normalized_seed_base RESOLVED_SEED_BASE "$seed_file_base" file "$seed_label"
    return 0
  fi

  RESOLVED_SEED_BASE=
  return 1
}

persisted_seed_base() {
  persisted_seed_url_base=
  persisted_seed_file_base=

  if [ -f "$SEED_URL_PATH" ]; then
    persisted_seed_url_base=$(cat "$SEED_URL_PATH")
  fi
  if [ -f "$SEED_FILE_PATH" ]; then
    persisted_seed_file_base=$(cat "$SEED_FILE_PATH")
  fi

  choose_seed_base_from_pair "$persisted_seed_url_base" "$persisted_seed_file_base" "persisted installer state"
}

cmdline_seed_base() {
  cmdline_seed_url_base=
  cmdline_seed_file_base=

  for arg in $(cat /proc/cmdline 2>/dev/null || true); do
    case "$arg" in
      preseed/url=*|url=*)
        [ -n "$cmdline_seed_url_base" ] || cmdline_seed_url_base=${arg#*=}
        ;;
      preseed/file=*|file=*)
        [ -n "$cmdline_seed_file_base" ] || cmdline_seed_file_base=${arg#*=}
        ;;
    esac
  done

  if choose_seed_base_from_pair "$cmdline_seed_url_base" "$cmdline_seed_file_base" "kernel cmdline"; then
    printf '%s\n' "$RESOLVED_SEED_BASE"
    return 0
  fi
  return 1
}

resolve_seed_base() {
  resolved_requested_seed_base=${1:-}

  if [ -n "$resolved_requested_seed_base" ]; then
    assign_normalized_seed_base RESOLVED_SEED_BASE \
      "$resolved_requested_seed_base" \
      "$(seed_source_type "$resolved_requested_seed_base")" \
      "${phase} requested seed source"
    printf '%s\n' "$RESOLVED_SEED_BASE"
    return 0
  fi
  if cmdline_seed_base; then
    return 0
  fi
  if persisted_seed_base; then
    printf '%s\n' "$RESOLVED_SEED_BASE"
    return 0
  fi

  fatal "installation URL or file path not found for ${phase}; use url=, preseed/url=, file=, or preseed/file=, or let include_command stage the seed source first"
}

persist_seed_base() {
  persisted_seed_base_value=$1

  case "$(seed_source_type "$persisted_seed_base_value")" in
    file)
      install -d -m 0700 "$BOOTSTRAP_DIR"
      printf '%s\n' "$persisted_seed_base_value" >"$SEED_FILE_PATH"
      rm -f "$SEED_URL_PATH"
      ;;
    url)
      install -d -m 0700 "$BOOTSTRAP_DIR"
      printf '%s\n' "$persisted_seed_base_value" >"$SEED_URL_PATH"
      rm -f "$SEED_FILE_PATH"
      ;;
    *)
      fatal "unsupported installation source type while persisting seed base: $persisted_seed_base_value"
      ;;
  esac
}

validate_relative_seed_path() {
  seed_relative_path=$1

  case "$seed_relative_path" in
    ''|/*|../*|*/..|*../*|*//*)
      fatal "seed source path must stay relative to the seed base: ${seed_relative_path:-unset}"
      ;;
  esac
}

repo_env_path() {
  printf '%s/repo.env\n' "$BOOTSTRAP_DIR"
}

validate_repo_dir_value() {
  bootstrap_entry_repo_validate_var=$1
  bootstrap_entry_repo_validate_value=$2

  case "$bootstrap_entry_repo_validate_value" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      fatal "${bootstrap_entry_repo_validate_var} must be a safe repository-relative directory path: ${bootstrap_entry_repo_validate_value:-unset}"
      ;;
  esac
}

repo_dir_input_is_var() {
  case "${1:-}" in
    DIR_[ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      case "$1" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

ensure_repo_env() {
  bootstrap_entry_repo_seed_base=$1
  bootstrap_entry_repo_env=$(repo_env_path)

  if [ "${BOOTSTRAP_ENTRY_REPO_ENV_READY:-0}" -eq 1 ]; then
    return 0
  fi

  if [ ! -s "$bootstrap_entry_repo_env" ]; then
    fetch_seed_file "$bootstrap_entry_repo_seed_base" repo.env "$bootstrap_entry_repo_env" 0600 "repository path environment"
  fi
  # shellcheck disable=SC1090
  . "$bootstrap_entry_repo_env"
  validate_repo_dir_value DIR_SCRIPTS_COMMON "${DIR_SCRIPTS_COMMON:-}"
  BOOTSTRAP_ENTRY_REPO_ENV_READY=1
}

repo_join_var() {
  bootstrap_entry_repo_join_dir=$1
  bootstrap_entry_repo_join_leaf=$2
  bootstrap_entry_repo_join_base=
  bootstrap_entry_repo_join_path=

  if repo_dir_input_is_var "$bootstrap_entry_repo_join_dir"; then
    eval "bootstrap_entry_repo_join_base=\${$bootstrap_entry_repo_join_dir:-}"
    validate_repo_dir_value "$bootstrap_entry_repo_join_dir" "$bootstrap_entry_repo_join_base"
  else
    bootstrap_entry_repo_join_path=$bootstrap_entry_repo_join_dir
    validate_repo_dir_value repository_path "$bootstrap_entry_repo_join_path"
    bootstrap_entry_repo_join_base=$bootstrap_entry_repo_join_path
  fi

  case "$bootstrap_entry_repo_join_leaf" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      fatal "unsafe repository path suffix for ${bootstrap_entry_repo_join_dir}: ${bootstrap_entry_repo_join_leaf:-unset}"
      ;;
  esac
  printf '%s/%s\n' "$bootstrap_entry_repo_join_base" "$bootstrap_entry_repo_join_leaf"
}

fetch_seed_file() {
  seed_base=$1
  src=$2
  dest=$3
  mode=$4
  label=$5
  timeout_seconds=${6:-45}
  tmp_dest="${dest}.tmp.$$"
  fetch_log="${tmp_dest}.fetch.log"
  parent_dir=$(dirname "$dest")
  seed_type=$(seed_source_type "$seed_base")

  validate_relative_seed_path "$src"
  [ -d "$parent_dir" ] || install -d -m 0700 "$parent_dir"
  rm -f "$tmp_dest" "$fetch_log"
  log "info: fetching ${label}: ${src} from ${seed_type} seed source"

  case "$seed_type" in
    file)
      seed_source_path="${seed_base%/}/$src"
      if cp "$seed_source_path" "$tmp_dest" >"$fetch_log" 2>&1; then
        fetch_status=0
      else
        fetch_status=$?
      fi
      ;;
    url)
      if wget --no-verbose --tries=3 --timeout="$timeout_seconds" -O "$tmp_dest" "$seed_base/$src" >"$fetch_log" 2>&1; then
        fetch_status=0
      else
        fetch_status=$?
      fi
      ;;
    *)
      fatal "unsupported installation source type while fetching ${label}: $seed_type"
      ;;
  esac

  if [ "$fetch_status" -ne 0 ]; then
    log "error: failed to fetch ${label}: ${src} (status ${fetch_status})"
    [ -s "$fetch_log" ] && sed "s/^/[preseed-bootstrap:${seed_type}] /" "$fetch_log" >&2
    rm -f "$tmp_dest" "$fetch_log"
    exit 1
  fi
  rm -f "$fetch_log"
  [ -s "$tmp_dest" ] || fatal "fetched ${label} is empty: ${src}"
  mv "$tmp_dest" "$dest"
  chmod "$mode" "$dest"
}

refresh_bootstrap_lib() {
  seed_base=$1
  bootstrap_src=

  install -d -m 0700 "$BOOTSTRAP_DIR"
  logging_enabled && install -d -m 0700 "$LOG_DIR"
  if [ -s "$BOOTSTRAP_LIB" ] && [ -r "$BOOTSTRAP_SEED_META" ] &&
     [ "$(cat "$BOOTSTRAP_SEED_META" 2>/dev/null || true)" = "$seed_base" ]
  then
    log "info: common bootstrap helper cache hit for ${seed_base}"
    return 0
  fi
  ensure_repo_env "$seed_base"
  bootstrap_src=$(repo_join_var DIR_SCRIPTS_COMMON bootstrap.sh)
  fetch_seed_file "$seed_base" "$bootstrap_src" "$BOOTSTRAP_LIB" 0600 "common bootstrap helper"
  printf '%s\n' "$seed_base" >"$BOOTSTRAP_SEED_META"
  chmod 0600 "$BOOTSTRAP_SEED_META" 2>/dev/null || true
}

run_phase() {
  seed_base=$1

  # shellcheck disable=SC1090,SC1091
  . "$BOOTSTRAP_LIB"
  if bootstrap_run_preseed_phase "$phase" "$seed_base"; then
    return 0
  else
    phase_status=$?
  fi
  case "$phase" in
    late)
      if logging_enabled; then
        log "fatal: late failed with status ${phase_status} (see ${log_path} and category logs under ${LOG_DIR})"
      else
        log "fatal: late failed with status ${phase_status}"
      fi
      ;;
    *)
      if logging_enabled; then
        log "fatal: ${phase} failed with status ${phase_status} (see ${log_path})"
      else
        log "fatal: ${phase} failed with status ${phase_status}"
      fi
      ;;
  esac
  exit "$phase_status"
}

[ -n "$phase" ] || usage
default_log_path=$(phase_default_log "$phase" 2>/dev/null || true)
[ -n "$default_log_path" ] || usage
[ -n "$log_path" ] || log_path=$default_log_path
log_path=$(resolve_runtime_log_path "$log_path")
apply_logging_policy

install -d -m 0700 "$BOOTSTRAP_DIR"
if logging_enabled; then
  install -d -m 0700 "$(dirname "$log_path")" "$LOG_DIR"
  : >>"$log_path"
  chmod 0600 "$log_path" 2>/dev/null || true
  exec 2>>"$log_path"
fi
log "info: starting ${phase}"

seed_base=$(resolve_seed_base "$requested_seed_base")
persist_seed_base "$seed_base"
refresh_bootstrap_lib "$seed_base"
run_phase "$seed_base"
