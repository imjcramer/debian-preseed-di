#!/bin/sh

bootstrap_log() {
  case "$*" in
    fatal:\ *|error:\ *) ;;
    *)
      case "${INSTALLER_DEBUG_LOGS:-0}" in
        1|true|TRUE|yes|YES|on|ON) ;;
        *) return 0 ;;
      esac
      ;;
  esac
  printf '[bootstrap] %s\n' "$*" >&2
}

bootstrap_fatal() {
  bootstrap_log "fatal: $*"
  exit 1
}

bootstrap_runtime_dir() {
  printf '%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_log_dir() {
  printf '%s\n' "${INSTALLER_LOG_DIR:-${INSTALLER_PRESEED_LOG_DIR:-/tmp/preseed-logs}}"
}

bootstrap_runtime_cache_dir() {
  printf '%s/cache\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_seed_cache_dir() {
  printf '%s/cache/seed\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_bootstrap_dir() {
  printf '%s/bootstrap\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_url_path() {
  printf '%s/bootstrap/seed.url\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_file_path() {
  printf '%s/bootstrap/seed.file\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_lib_path() {
  printf '%s/bootstrap/bootstrap.sh\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_repo_env_relpath() {
  printf '%s\n' repo.env
}

bootstrap_repo_env_path() {
  printf '%s/bootstrap/repo.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_repo_required_dir_vars() {
  cat <<'EOF'
DIR_SCRIPTS_COMMON
DIR_SCRIPTS_EARLY
DIR_SCRIPTS_LATE
DIR_SCRIPTS_PARTMAN
DIR_SCRIPTS_PRESEED
EOF
}

bootstrap_validate_repo_dir_value() {
  bootstrap_repo_validate_var=$1
  bootstrap_repo_validate_value=$2

  case "$bootstrap_repo_validate_value" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      bootstrap_fatal "${bootstrap_repo_validate_var} must be a safe repository-relative directory path: ${bootstrap_repo_validate_value:-unset}"
      ;;
  esac
}

bootstrap_repo_dir_input_is_var() {
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

bootstrap_validate_repo_env() {
  for bootstrap_repo_env_var in $(bootstrap_repo_required_dir_vars); do
    bootstrap_repo_env_value=
    eval "bootstrap_repo_env_value=\${$bootstrap_repo_env_var:-}"
    bootstrap_validate_repo_dir_value "$bootstrap_repo_env_var" "$bootstrap_repo_env_value"
  done
}

bootstrap_ensure_repo_env() {
  bootstrap_repo_seed_base=${1:-}

  if [ "${BOOTSTRAP_REPO_ENV_READY:-0}" -eq 1 ]; then
    return 0
  fi

  bootstrap_repo_seed_base=$(bootstrap_require_seed_base "$bootstrap_repo_seed_base")
  bootstrap_repo_env_file=$(bootstrap_repo_env_path)
  if [ ! -s "$bootstrap_repo_env_file" ]; then
    bootstrap_fetch_seed_file "$bootstrap_repo_seed_base" "$(bootstrap_repo_env_relpath)" "$bootstrap_repo_env_file" 0600 "repository path environment"
  fi
  # shellcheck disable=SC1090
  . "$bootstrap_repo_env_file"
  bootstrap_validate_repo_env
  BOOTSTRAP_REPO_ENV_READY=1
}

bootstrap_repo_dir_value() {
  bootstrap_repo_dir_name=$1
  bootstrap_repo_dir_value=
  bootstrap_repo_dir_path=

  if ! bootstrap_repo_dir_input_is_var "$bootstrap_repo_dir_name"; then
    bootstrap_repo_dir_path=$bootstrap_repo_dir_name
    bootstrap_validate_repo_dir_value repository_path "$bootstrap_repo_dir_path"
    printf '%s\n' "$bootstrap_repo_dir_path"
    return 0
  fi

  eval "bootstrap_repo_dir_value=\${$bootstrap_repo_dir_name:-}"
  [ -n "$bootstrap_repo_dir_value" ] || bootstrap_fatal "repository directory variable is unset: $bootstrap_repo_dir_name"
  bootstrap_validate_repo_dir_value "$bootstrap_repo_dir_name" "$bootstrap_repo_dir_value"
  printf '%s\n' "$bootstrap_repo_dir_value"
}

bootstrap_repo_join_var() {
  bootstrap_repo_join_dir=$1
  bootstrap_repo_join_leaf=${2:-}
  bootstrap_repo_join_base=$(bootstrap_repo_dir_value "$bootstrap_repo_join_dir")

  case "$bootstrap_repo_join_leaf" in
    '') printf '%s\n' "$bootstrap_repo_join_base" ;;
    /*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      bootstrap_fatal "unsafe repository path suffix for ${bootstrap_repo_join_dir}: ${bootstrap_repo_join_leaf:-unset}"
      ;;
    *) printf '%s/%s\n' "$bootstrap_repo_join_base" "$bootstrap_repo_join_leaf" ;;
  esac
}

bootstrap_repo_resolve_path() {
  bootstrap_repo_source_path=$1

  case "$bootstrap_repo_source_path" in
    "$(bootstrap_repo_env_relpath)")
      printf '%s\n' "$bootstrap_repo_source_path"
      return 0
      ;;
  esac

  bootstrap_ensure_repo_env ""
  case "$bootstrap_repo_source_path" in
    scripts/common/*)
      bootstrap_repo_join_var DIR_SCRIPTS_COMMON "${bootstrap_repo_source_path#scripts/common/}"
      ;;
    scripts/preseed/*)
      bootstrap_repo_join_var DIR_SCRIPTS_PRESEED "${bootstrap_repo_source_path#scripts/preseed/}"
      ;;
    scripts/early/*)
      bootstrap_repo_join_var DIR_SCRIPTS_EARLY "${bootstrap_repo_source_path#scripts/early/}"
      ;;
    scripts/partman/*)
      bootstrap_repo_join_var DIR_SCRIPTS_PARTMAN "${bootstrap_repo_source_path#scripts/partman/}"
      ;;
    scripts/late/*)
      bootstrap_repo_join_var DIR_SCRIPTS_LATE "${bootstrap_repo_source_path#scripts/late/}"
      ;;
    *)
      printf '%s\n' "$bootstrap_repo_source_path"
      ;;
  esac
}

bootstrap_phase_runner_path() {
  runner_name=$1
  printf '%s/bootstrap/%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}" "$runner_name"
}

bootstrap_seed_source_type() {
  case "${1:-}" in
    /*) printf '%s\n' file ;;
    *) printf '%s\n' url ;;
  esac
}

bootstrap_trim_seed_base() {
  seed_base=$1

  while [ "${#seed_base}" -gt 1 ]; do
    case "$seed_base" in
      */) seed_base=${seed_base%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$seed_base"
}

bootstrap_cmdline() {
  if [ -n "${INSTALLER_CMDLINE:-}" ]; then
    printf '%s\n' "$INSTALLER_CMDLINE"
    return 0
  fi
  if [ "${BOOTSTRAP_CMDLINE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
    return 0
  fi
  if [ -r /proc/cmdline ]; then
    BOOTSTRAP_CMDLINE_CACHE=$(cat /proc/cmdline)
  else
    BOOTSTRAP_CMDLINE_CACHE=
  fi
  BOOTSTRAP_CMDLINE_CACHE_READY=1
  printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
}

bootstrap_assign_normalized_seed_base() {
  output_var_name=$1
  seed_base=$2
  seed_type=$3

  seed_base=${seed_base%%\?*}
  case "$seed_base" in
    */*.cfg) seed_base=${seed_base%/*} ;;
  esac
  seed_base=$(bootstrap_trim_seed_base "$seed_base")

  case "$seed_type" in
    file)
      case "$seed_base" in
        /*) ;;
        *) bootstrap_fatal "installation file base must be an absolute path: ${seed_base:-unset}" ;;
      esac
      case "$seed_base" in
        *..*|*//*)
          bootstrap_fatal "installation file base contains unsupported traversal: $seed_base"
          ;;
      esac
      ;;
    url)
      [ -n "$seed_base" ] || bootstrap_fatal "installation URL base is empty"
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac

  eval "$output_var_name=\$seed_base"
}

bootstrap_normalize_seed_base() {
  normalized_seed_base=
  bootstrap_assign_normalized_seed_base normalized_seed_base "$1" "$2"
  printf '%s\n' "$normalized_seed_base"
}

bootstrap_validate_relative_seed_path() {
  seed_relative_path=$1

  case "$seed_relative_path" in
    ''|/*|../*|*/..|*../*|*//*)
      bootstrap_fatal "seed source path must stay relative to the seed base: ${seed_relative_path:-unset}"
      ;;
  esac
}

bootstrap_copy_path_with_mode() {
  copy_src_path=$1
  copy_dest_path=$2
  copy_mode=$3
  copy_label=${4:-file}
  copy_parent_dir=$(dirname "$copy_dest_path")
  copy_tmp_path="${copy_dest_path}.tmp.$$"
  copy_err_path="${copy_tmp_path}.copy.log"

  if [ "$copy_src_path" = "$copy_dest_path" ]; then
    chmod "$copy_mode" "$copy_dest_path" 2>/dev/null || true
    return 0
  fi

  [ -d "$copy_parent_dir" ] || install -d -m 0700 "$copy_parent_dir"
  rm -f "$copy_tmp_path" "$copy_err_path"
  if cp "$copy_src_path" "$copy_tmp_path" >"$copy_err_path" 2>&1; then
    copy_status=0
  else
    copy_status=$?
  fi
  if [ "$copy_status" -ne 0 ]; then
    bootstrap_log "error: failed to copy ${copy_label} from ${copy_src_path} to ${copy_dest_path} (status ${copy_status})"
    [ -s "$copy_err_path" ] && sed 's/^/[bootstrap:cp] /' "$copy_err_path" >&2
    rm -f "$copy_tmp_path" "$copy_err_path"
    exit 1
  fi
  rm -f "$copy_err_path"
  if [ ! -s "$copy_tmp_path" ]; then
    rm -f "$copy_tmp_path"
    bootstrap_fatal "copied ${copy_label} is empty: ${copy_src_path}"
  fi
  mv "$copy_tmp_path" "$copy_dest_path"
  chmod "$copy_mode" "$copy_dest_path"
}

bootstrap_log_path_is_numbered() {
  bootstrap_check_log_path=$1
  bootstrap_check_log_name=${bootstrap_check_log_path##*/}

  case "$bootstrap_check_log_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

bootstrap_log_sequence_file() {
  bootstrap_sequence_log_dir=$1
  printf '%s/.log-sequence\n' "$bootstrap_sequence_log_dir"
}

bootstrap_next_log_sequence() {
  bootstrap_sequence_log_dir=$1
  bootstrap_sequence_path=$(bootstrap_log_sequence_file "$bootstrap_sequence_log_dir")
  bootstrap_sequence_tmp="${bootstrap_sequence_path}.tmp.$$"
  bootstrap_current_sequence=0

  [ -d "$bootstrap_sequence_log_dir" ] || install -d -m 0700 "$bootstrap_sequence_log_dir"
  if [ -r "$bootstrap_sequence_path" ]; then
    bootstrap_current_sequence=$(cat "$bootstrap_sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$bootstrap_current_sequence" in
    ''|*[!0-9]*) bootstrap_current_sequence=0 ;;
  esac

  bootstrap_next_sequence=$((bootstrap_current_sequence + 1))
  printf '%s\n' "$bootstrap_next_sequence" >"$bootstrap_sequence_tmp"
  mv "$bootstrap_sequence_tmp" "$bootstrap_sequence_path"
  chmod 0600 "$bootstrap_sequence_path" 2>/dev/null || true
  printf '%s\n' "$bootstrap_next_sequence"
}

bootstrap_runtime_log_path_requested() {
  requested_log_path=$1
  runtime_log_dir=$(bootstrap_runtime_log_dir)

  case "$requested_log_path" in
    "${runtime_log_dir}/"*) return 0 ;;
  esac
  return 1
}

bootstrap_resolve_runtime_log_path() {
  requested_log_path=$1
  printf '%s\n' "$requested_log_path"
}

bootstrap_file_safe_token() {
  printf '%s\n' "$(printf '%s' "${1:-seed}" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

bootstrap_seed_cache_key() {
  seed_cache_base=$1
  seed_cache_type=$(bootstrap_seed_source_type "$seed_cache_base")
  seed_cache_norm=$(bootstrap_normalize_seed_base "$seed_cache_base" "$seed_cache_type")
  printf '%s/%s\n' \
    "$(bootstrap_file_safe_token "$seed_cache_type")" \
    "$(bootstrap_file_safe_token "$seed_cache_norm")"
}

bootstrap_seed_cache_path() {
  seed_cache_base=$1
  seed_cache_source_path=$2

  bootstrap_validate_relative_seed_path "$seed_cache_source_path"
  printf '%s/%s/%s\n' \
    "$(bootstrap_runtime_seed_cache_dir)" \
    "$(bootstrap_seed_cache_key "$seed_cache_base")" \
    "$seed_cache_source_path"
}

bootstrap_persist_seed_source() {
  seed_base=$1
  seed_type=$(bootstrap_seed_source_type "$seed_base")
  seed_url_path=$(bootstrap_seed_url_path)
  seed_file_path=$(bootstrap_seed_file_path)

  install -d -m 0700 "$(bootstrap_runtime_bootstrap_dir)"

  case "$seed_type" in
    file)
      printf '%s\n' "$seed_base" >"$seed_file_path"
      rm -f "$seed_url_path"
      ;;
    url)
      printf '%s\n' "$seed_base" >"$seed_url_path"
      rm -f "$seed_file_path"
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac
}

bootstrap_choose_seed_base_from_pair() {
  seed_url_base=$1
  seed_file_base=$2
  seed_label=$3

  if [ -n "$seed_url_base" ] && [ -n "$seed_file_base" ]; then
    bootstrap_fatal "${seed_label} defines both URL and file seed sources"
  fi
  if [ -n "$seed_url_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_url_base" url
    return 0
  fi
  if [ -n "$seed_file_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_file_base" file
    return 0
  fi

  BOOTSTRAP_RESOLVED_SEED_BASE=
  return 1
}

bootstrap_persisted_seed_base() {
  persisted_seed_url_base=
  persisted_seed_file_base=
  seed_url_path=$(bootstrap_seed_url_path)
  seed_file_path=$(bootstrap_seed_file_path)

  if [ -f "$seed_url_path" ]; then
    persisted_seed_url_base=$(cat "$seed_url_path")
  fi
  if [ -f "$seed_file_path" ]; then
    persisted_seed_file_base=$(cat "$seed_file_path")
  fi

  bootstrap_choose_seed_base_from_pair "$persisted_seed_url_base" "$persisted_seed_file_base" "persisted installer state"
}

bootstrap_cmdline_seed_base() {
  if [ "${BOOTSTRAP_CMDLINE_SEED_PAIR_READY:-0}" -eq 1 ]; then
    if bootstrap_choose_seed_base_from_pair "$BOOTSTRAP_CMDLINE_SEED_URL_BASE" "$BOOTSTRAP_CMDLINE_SEED_FILE_BASE" "kernel cmdline"; then
      printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
      return 0
    fi
    return 1
  fi

  cmdline_seed_url_base=
  cmdline_seed_file_base=

  for arg in $(bootstrap_cmdline); do
    case "$arg" in
      preseed/url=*|url=*)
        [ -n "$cmdline_seed_url_base" ] || cmdline_seed_url_base=${arg#*=}
        ;;
      preseed/file=*|file=*)
        [ -n "$cmdline_seed_file_base" ] || cmdline_seed_file_base=${arg#*=}
        ;;
    esac
  done

  BOOTSTRAP_CMDLINE_SEED_URL_BASE=$cmdline_seed_url_base
  BOOTSTRAP_CMDLINE_SEED_FILE_BASE=$cmdline_seed_file_base
  BOOTSTRAP_CMDLINE_SEED_PAIR_READY=1

  if bootstrap_choose_seed_base_from_pair "$cmdline_seed_url_base" "$cmdline_seed_file_base" "kernel cmdline"; then
    printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
    return 0
  fi
  return 1
}

bootstrap_require_seed_base() {
  requested_seed_base=${1:-}

  if [ -n "$requested_seed_base" ]; then
    seed_type=$(bootstrap_seed_source_type "$requested_seed_base")
    bootstrap_normalize_seed_base "$requested_seed_base" "$seed_type"
    return 0
  fi
  if [ "${BOOTSTRAP_SEED_BASE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "$BOOTSTRAP_SEED_BASE_CACHE"
    return 0
  fi

  if cmdline_seed_base=$(bootstrap_cmdline_seed_base); then
    BOOTSTRAP_SEED_BASE_CACHE=$cmdline_seed_base
    BOOTSTRAP_SEED_BASE_CACHE_READY=1
    printf '%s\n' "$BOOTSTRAP_SEED_BASE_CACHE"
    return 0
  fi
  if bootstrap_persisted_seed_base; then
    BOOTSTRAP_SEED_BASE_CACHE=$BOOTSTRAP_RESOLVED_SEED_BASE
    BOOTSTRAP_SEED_BASE_CACHE_READY=1
    printf '%s\n' "$BOOTSTRAP_SEED_BASE_CACHE"
    return 0
  fi

  bootstrap_fatal "installation preseed URL or file path not found in kernel cmdline or persisted installer state"
}

bootstrap_require_seed_url_base() {
  bootstrap_require_seed_base "${1:-}"
}

bootstrap_fetch_seed_file() {
  seed_base=$1
  src=$2
  dest=$3
  mode=${4:-0600}
  label=${5:-file}
  timeout_seconds=${6:-45}

  case "$src" in
    "$(bootstrap_repo_env_relpath)") ;;
    *)
      bootstrap_ensure_repo_env "$seed_base"
      src=$(bootstrap_repo_resolve_path "$src")
      ;;
  esac

  seed_type=$(bootstrap_seed_source_type "$seed_base")
  cache_path=$(bootstrap_seed_cache_path "$seed_base" "$src")

  if [ ! -s "$cache_path" ]; then
    bootstrap_log "info: seed cache miss for ${src}; fetching ${label} from ${seed_type} seed source"
    tmp_dest="${cache_path}.tmp.$$"
    fetch_log="${tmp_dest}.fetch.log"
    parent_dir=$(dirname "$cache_path")

    [ -d "$parent_dir" ] || install -d -m 0700 "$parent_dir"
    rm -f "$tmp_dest" "$fetch_log"

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
        bootstrap_fatal "unsupported installation source type: $seed_type"
        ;;
    esac

    if [ "$fetch_status" -ne 0 ]; then
      bootstrap_log "error: failed to fetch ${label}: ${src} (status ${fetch_status})"
      [ -s "$fetch_log" ] && sed "s/^/[bootstrap:${seed_type}] /" "$fetch_log" >&2
      rm -f "$tmp_dest" "$fetch_log"
      exit 1
    fi
    rm -f "$fetch_log"
    if [ ! -s "$tmp_dest" ]; then
      rm -f "$tmp_dest"
      bootstrap_fatal "fetched ${label} is empty: ${src}"
    fi
    mv "$tmp_dest" "$cache_path"
    chmod 0600 "$cache_path"
  else
    bootstrap_log "info: seed cache hit for ${src}"
  fi

  bootstrap_copy_path_with_mode "$cache_path" "$dest" "$mode" "cached seed file ${src}"
}

bootstrap_source_common_lib() {
  requested_seed_base=${1:-}
  common_lib_path=${2:-$(bootstrap_phase_runner_path common-lib.sh)}
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base")
  bootstrap_persist_seed_source "$seed_base"
  bootstrap_ensure_repo_env "$seed_base"

  bootstrap_fetch_seed_file "$seed_base" "$(bootstrap_repo_join_var DIR_SCRIPTS_COMMON lib.sh)" "$common_lib_path" 0600 "common library"
  # shellcheck disable=SC1090,SC1091
  . "$common_lib_path"
}

bootstrap_source_common_support_libs() {
  requested_seed_base=${1:-}
  tmp_env_dir=$2
  shift 2

  seed_base=$(bootstrap_require_seed_base "$requested_seed_base")
  bootstrap_persist_seed_source "$seed_base"
  bootstrap_ensure_repo_env "$seed_base"
  install -d -m 0700 "$tmp_env_dir"

  for lib_name in "$@"; do
    case "$lib_name" in
      fetch)
        src=$(bootstrap_repo_join_var DIR_SCRIPTS_COMMON fetch.sh)
        dest="${tmp_env_dir}/fetch.sh"
        ;;
      hook)
        src=$(bootstrap_repo_join_var DIR_SCRIPTS_COMMON hook.sh)
        dest="${tmp_env_dir}/hook.sh"
        ;;
      target)
        src=$(bootstrap_repo_join_var DIR_SCRIPTS_COMMON target.sh)
        dest="${tmp_env_dir}/target-common.sh"
        ;;
      ssh)
        src=$(bootstrap_repo_join_var DIR_SCRIPTS_COMMON ssh.sh)
        dest="${tmp_env_dir}/ssh.sh"
        ;;
      *)
        bootstrap_fatal "unsupported installer support library: ${lib_name}"
        ;;
    esac
    bootstrap_fetch_seed_file "$seed_base" "$src" "$dest" 0600 "shared helper"
    # shellcheck disable=SC1090,SC1091
    . "$dest"
  done
}

bootstrap_run_preseed_phase() {
  phase=$1
  requested_seed_base=${2:-}
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base")
  bootstrap_ensure_repo_env "$seed_base"

  case "$phase" in
    prepare-context|apply)
      runner_src=$(bootstrap_repo_join_var DIR_SCRIPTS_PRESEED answers.sh)
      runner=${3:-$(bootstrap_phase_runner_path preseed-answers.sh)}
      runner_args="$phase $seed_base"
      ;;
    early)
      runner_src=$(bootstrap_repo_join_var DIR_SCRIPTS_EARLY dispatch.sh)
      runner=${3:-$(bootstrap_phase_runner_path early-dispatch.sh)}
      runner_args="$seed_base"
      ;;
    partman)
      runner_src=$(bootstrap_repo_join_var DIR_SCRIPTS_PARTMAN dispatch.sh)
      runner=${3:-$(bootstrap_phase_runner_path partman-dispatch.sh)}
      runner_args="$seed_base"
      ;;
    late)
      runner_src=$(bootstrap_repo_join_var DIR_SCRIPTS_LATE dispatch.sh)
      runner=${3:-$(bootstrap_phase_runner_path late-dispatch.sh)}
      runner_args="$seed_base"
      ;;
    *)
      bootstrap_fatal "unsupported preseed phase: ${phase}"
      ;;
  esac

  bootstrap_persist_seed_source "$seed_base"
  bootstrap_fetch_seed_file "$seed_base" "$runner_src" "$runner" 0755 "phase runner"
  bootstrap_log "info: invoking preseed phase ${phase}"
  # shellcheck disable=SC2086
  INSTALLER_BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-$(bootstrap_lib_path)} "$runner" $runner_args
}
