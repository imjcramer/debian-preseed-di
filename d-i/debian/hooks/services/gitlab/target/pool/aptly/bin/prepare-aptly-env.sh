#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
shopt -s inherit_errexit 2>/dev/null || true

aptly_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

aptly_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || aptly_fail "missing required command: $1"
}

aptly_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

aptly_read_secret_value() {
  local value="$1"
  if [[ "$value" == /* ]]; then
    [[ -e "$value" ]] || aptly_fail "secret file path does not exist: $value" || return 1
    [[ -f "$value" && -r "$value" && ! -L "$value" ]] || aptly_fail "secret file path is not a readable regular file: $value" || return 1
    [[ "$(wc -c <"$value")" -le 1048576 ]] || aptly_fail "secret file too large: $value" || return 1
    cat -- "$value"
    return 0
  fi
  printf '%s' "$value"
}

aptly_validate_tmp_base() {
  local value="$1"
  [[ -n "$value" ]] || aptly_fail "TMPDIR must not be empty" || return 1
  [[ "$value" == /* ]] || aptly_fail "TMPDIR must be an absolute path" || return 1
  [[ "$value" != "/" ]] || aptly_fail "TMPDIR must not be /" || return 1
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || aptly_fail "TMPDIR contains unsupported control characters" || return 1
  [[ "$value" != *".."* ]] || aptly_fail "TMPDIR must not contain .." || return 1
}

aptly_validate_single_line_secret() {
  local label="$1"
  local value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || aptly_fail "$label contains unsupported control characters" || return 1
}

aptly_make_job_dir() {
  local tmp_base job_dir
  tmp_base="$(aptly_trim "${1:-/tmp}")"
  aptly_validate_tmp_base "$tmp_base"
  if [[ ! -d "$tmp_base" ]]; then
    install -d -m 0700 -- "$tmp_base"
  fi
  [[ -d "$tmp_base" && -w "$tmp_base" && -x "$tmp_base" ]] || aptly_fail "TMPDIR is not writable/searchable: $tmp_base" || return 1
  job_dir="$(mktemp -d "${tmp_base%/}/aptly.XXXXXXXXXX")"
  chmod 0700 "$job_dir"
  printf '%s' "$job_dir"
}

aptly_run_registered_cleanup() {
  local job_dir
  if ! declare -p __APTLY_JOB_CLEANUP_DIRS >/dev/null 2>&1; then
    return 0
  fi
  for job_dir in "${__APTLY_JOB_CLEANUP_DIRS[@]}"; do
    [[ -n "$job_dir" ]] || continue
    rm -rf -- "$job_dir" 2>/dev/null || true
  done
}

aptly_register_job_cleanup() {
  local job_dir="$1"
  local existing_trap existing_body new_trap
  if ! declare -p __APTLY_JOB_CLEANUP_DIRS >/dev/null 2>&1; then
    declare -g -a __APTLY_JOB_CLEANUP_DIRS=()
  fi
  __APTLY_JOB_CLEANUP_DIRS+=("$job_dir")
  existing_trap="$(trap -p EXIT || true)"
  if [[ "$existing_trap" == *"aptly_run_registered_cleanup"* ]]; then
    return 0
  fi
  new_trap="aptly_run_registered_cleanup"
  if [[ "$existing_trap" == "trap -- '"*"' EXIT" ]]; then
    existing_body="${existing_trap#trap -- \'}"
    existing_body="${existing_body%\' EXIT}"
    [[ -n "$existing_body" ]] && new_trap+=$'\n'"${existing_body}"
  fi
  # shellcheck disable=SC2064
  trap "$new_trap" EXIT
}

aptly_normalize_prefix() {
  local value
  value="$(aptly_trim "${1:-}")"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || aptly_fail "APTLY_R2_PREFIX contains unsupported control characters" || return 1
  [[ "$value" != *".."* ]] || aptly_fail "APTLY_R2_PREFIX must not contain .." || return 1
  [[ "$value" != *"//"* ]] || aptly_fail "APTLY_R2_PREFIX must not contain empty path segments" || return 1
  [[ "$value" != *" "* && "$value" != *$'\t'* ]] || aptly_fail "APTLY_R2_PREFIX must not contain whitespace" || return 1
  value="${value#/}"
  value="${value%/}"
  if [[ -z "$value" ]]; then
    printf '%s' ""
    return 0
  fi
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._+/-]*$ ]] || aptly_fail "APTLY_R2_PREFIX contains invalid characters" || return 1
  printf '%s/' "$value"
}

aptly_validate_r2_account_id() {
  local account="$1"
  [[ -z "$account" || "$account" =~ ^[A-Fa-f0-9]{32}$ ]] || aptly_fail "R2_ACCOUNT_ID must be a 32-character hex Cloudflare account id" || return 1
}

aptly_validate_endpoint_host() {
  local host="$1"
  local dns_host port port_num label
  local -a endpoint_labels=()
  [[ -n "$host" ]] || aptly_fail "R2 endpoint host must not be empty" || return 1
  [[ "${#host}" -le 255 ]] || aptly_fail "R2 endpoint host is too long" || return 1
  dns_host="$host"
  if [[ "$dns_host" == *:* ]]; then
    port="${dns_host##*:}"
    dns_host="${dns_host%:*}"
    [[ "$port" =~ ^[0-9]+$ ]] || aptly_fail "invalid R2 endpoint port: ${port}" || return 1
    port_num=$((10#$port))
    (( port_num >= 1 && port_num <= 65535 )) || aptly_fail "invalid R2 endpoint port: ${port}" || return 1
  fi
  [[ "$dns_host" != .* && "$dns_host" != *. && "$dns_host" != *..* ]] || aptly_fail "invalid R2 endpoint host: ${host}" || return 1
  local IFS=.
  read -r -a endpoint_labels <<<"$dns_host"
  for label in "${endpoint_labels[@]}"; do
    [[ -n "$label" && "${#label}" -le 63 ]] || aptly_fail "invalid R2 endpoint host label: ${host}" || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || aptly_fail "invalid R2 endpoint host label: ${label}" || return 1
  done
}

aptly_normalize_endpoint_host() {
  local raw account host
  raw="$(aptly_trim "${R2_ENDPOINT_URL:-}")"
  account="$(aptly_trim "${R2_ACCOUNT_ID:-}")"

  if [[ -z "$raw" && -n "$account" ]]; then
    aptly_validate_r2_account_id "$account"
    raw="https://${account}.r2.cloudflarestorage.com"
  fi
  if [[ -z "$raw" ]]; then
    printf '%s' ""
    return 0
  fi

  if [[ "$raw" == *"://"* ]]; then
    [[ "$raw" == https://* ]] || aptly_fail "R2_ENDPOINT_URL must use https://" || return 1
    host="${raw#https://}"
  else
    host="$raw"
  fi
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%\#*}"
  [[ "$host" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || aptly_fail "invalid R2 endpoint host: ${host}" || return 1
  aptly_validate_endpoint_host "$host"
  printf '%s' "$host"
}

aptly_bool_value() {
  case "${1,,}" in
    1|true|yes|y|on) printf 'true' ;;
    0|false|no|n|off|"") printf 'false' ;;
    *) aptly_fail "invalid boolean value: $1" || return 1 ;;
  esac
}

aptly_is_armored_private_key() {
  [[ "$1" == *"BEGIN PGP PRIVATE KEY BLOCK"* || "$1" == *"BEGIN PGP SECRET KEY BLOCK"* ]]
}

aptly_import_signing_key() {
  local job_dir key_value passphrase_value key_file passphrase_file key_id
  job_dir="$1"
  key_value="$(aptly_read_secret_value "${GPG_SIGNING_KEY:-}")"
  if [[ -z "$key_value" ]]; then
    return 0
  fi

  if aptly_is_armored_private_key "$key_value"; then
    export GNUPGHOME="${job_dir}/gnupg"
    install -d -m 0700 -- "$GNUPGHOME"
    key_file="${job_dir}/signing-key.asc"
    printf '%s\n' "$key_value" >"$key_file"
    chmod 0600 "$key_file"
    gpg --batch --pinentry-mode loopback --import "$key_file" >/dev/null 2>&1 || aptly_fail "failed to import GPG_SIGNING_KEY" || return 1
    key_id="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
    [[ -n "$key_id" ]] || aptly_fail "GPG_SIGNING_KEY did not import a secret signing key" || return 1
    export APTLY_GPG_KEY="$key_id"
  else
    [[ "$key_value" != *$'\n'* && "$key_value" != *$'\r'* ]] || aptly_fail "GPG_SIGNING_KEY must be a key id, an armored private key block, or a file path" || return 1
    export APTLY_GPG_KEY="$key_value"
  fi

  passphrase_value="$(aptly_read_secret_value "${GPG_SIGNING_PASSPHRASE:-}")"
  if [[ -n "$passphrase_value" ]]; then
    [[ "${#passphrase_value}" -le 8192 ]] || aptly_fail "GPG_SIGNING_PASSPHRASE is too large" || return 1
    passphrase_file="${job_dir}/gpg-passphrase"
    printf '%s' "$passphrase_value" >"$passphrase_file"
    chmod 0600 "$passphrase_file"
    export APTLY_GPG_PASSPHRASE_FILE="$passphrase_file"
  else
    unset APTLY_GPG_PASSPHRASE_FILE || true
  fi
}

aptly_render_config_file() {
  local template_path="$1"
  local dest_path="$2"
  local root_dir="$3"
  local architectures_csv="$4"
  local download_concurrency="$5"
  local endpoint_name="$6"
  local bucket="$7"
  local endpoint="$8"
  local prefix="$9"
  local storage_class="${10}"
  local debug="${11}"

  [[ -r "$template_path" && ! -L "$template_path" ]] || aptly_fail "aptly config template is missing: ${template_path}" || return 1
  [[ -n "$architectures_csv" ]] || aptly_fail "APTLY_ARCHITECTURES must not be empty" || return 1
  [[ "$download_concurrency" =~ ^[0-9]+$ ]] || aptly_fail "APTLY_DOWNLOAD_CONCURRENCY must be numeric" || return 1
  (( 10#$download_concurrency >= 1 )) || aptly_fail "APTLY_DOWNLOAD_CONCURRENCY must be greater than zero" || return 1

  python3 - "$template_path" "$dest_path" "$root_dir" "$architectures_csv" "$download_concurrency" "$endpoint_name" "$bucket" "$endpoint" "$prefix" "$storage_class" "$debug" <<'PY'
import json
import pathlib
import sys

template_path, dest_path, root_dir, architectures_csv, download_concurrency, endpoint_name, bucket, endpoint, prefix, storage_class, debug = sys.argv[1:]
architectures = [item.strip() for item in architectures_csv.split(",") if item.strip()]
if not architectures:
    raise SystemExit("APTLY_ARCHITECTURES must contain at least one architecture")
replacements = {
    "__ROOT_DIR__": json.dumps(root_dir),
    "__ARCHITECTURES__": json.dumps(architectures),
    "__DOWNLOAD_CONCURRENCY__": download_concurrency,
    "__ENDPOINT_NAME__": json.dumps(endpoint_name),
    "__BUCKET__": json.dumps(bucket),
    "__ENDPOINT__": json.dumps(endpoint),
    "__PREFIX__": json.dumps(prefix),
    "__STORAGE_CLASS__": json.dumps(storage_class),
    "__DEBUG__": debug,
}
text = pathlib.Path(template_path).read_text()
for key, value in replacements.items():
    text = text.replace(key, value)
rendered = json.loads(text)
pathlib.Path(dest_path).write_text(json.dumps(rendered, indent=2) + "\n")
PY
}

prepare_aptly_env() {
  local real_bin job_dir job_tmp_base normalized_prefix normalized_debug bucket_name endpoint_host r2_access_key r2_secret_key
  aptly_require_cmd python3
  aptly_require_cmd gpg
  aptly_require_cmd mktemp

  real_bin="${APTLY_REAL_BIN:-/usr/bin/aptly}"
  if [[ ! -x "$real_bin" ]]; then
    real_bin="/usr/bin/aptly"
  fi
  if [[ ! -x "$real_bin" ]]; then
    real_bin="$(command -v aptly || true)"
  fi
  [[ -n "$real_bin" && -x "$real_bin" ]] || aptly_fail "aptly binary not found" || return 1

  export APTLY_REAL_BIN="$real_bin"
  export APTLY_STATE_DIR="${APTLY_STATE_DIR:-/pool/aptly}"
  export APTLY_ROOT_DIR="${APTLY_ROOT_DIR:-/pool/aptly/.aptly}"
  export APTLY_CONFIG="${APTLY_CONFIG:-${APTLY_STATE_DIR}/.aptly.conf}"
  [[ -r "$APTLY_CONFIG" ]] || aptly_fail "APTLY_CONFIG is missing: ${APTLY_CONFIG}" || return 1
  export APTLY_R2_ENDPOINT_NAME="${APTLY_R2_ENDPOINT_NAME:-r2}"
  export APTLY_PUBLISH_ENDPOINT="${APTLY_PUBLISH_ENDPOINT:-s3:${APTLY_R2_ENDPOINT_NAME}:}"
  normalized_prefix="$(aptly_normalize_prefix "${R2_PREFIX:-${APTLY_R2_PREFIX:-debian/}}")"
  export APTLY_R2_PREFIX="$normalized_prefix"
  export R2_PREFIX="$normalized_prefix"
  export APTLY_R2_STORAGE_CLASS="${APTLY_R2_STORAGE_CLASS:-STANDARD}"
  normalized_debug="$(aptly_bool_value "${APTLY_R2_DEBUG:-false}")"
  export APTLY_R2_DEBUG="$normalized_debug"

  job_tmp_base="${APTLY_JOB_TMP_BASE:-${TMPDIR:-/tmp}/aptly}"
  export APTLY_JOB_TMP_BASE="$job_tmp_base"
  job_dir="$(aptly_make_job_dir "$job_tmp_base")"
  aptly_register_job_cleanup "$job_dir"
  export APTLY_JOB_DIR="$job_dir"

  r2_access_key="$(aptly_trim "$(aptly_read_secret_value "${R2_ACCESS_KEY_ID:-}")")"
  r2_secret_key="$(aptly_trim "$(aptly_read_secret_value "${R2_SECRET_ACCESS_KEY:-}")")"
  aptly_validate_single_line_secret R2_ACCESS_KEY_ID "$r2_access_key"
  aptly_validate_single_line_secret R2_SECRET_ACCESS_KEY "$r2_secret_key"
  if [[ -n "$r2_access_key" && -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    export AWS_ACCESS_KEY_ID="$r2_access_key"
  fi
  if [[ -n "$r2_secret_key" && -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    export AWS_SECRET_ACCESS_KEY="$r2_secret_key"
  fi

  bucket_name="$(aptly_trim "${R2_BUCKET_NAME:-}")"
  endpoint_host="$(aptly_normalize_endpoint_host)"
  export APTLY_R2_BUCKET_NAME="$bucket_name"
  export APTLY_R2_ENDPOINT_HOST="$endpoint_host"

  aptly_import_signing_key "$job_dir"

  export PATH="${APTLY_STATE_DIR}/bin:${PATH}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  prepare_aptly_env "$@"
fi
