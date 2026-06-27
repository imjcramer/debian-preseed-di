#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MANAGED_HELPER="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/gitlab-runner-managed"

TEST_COUNT=11
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

assert_contains() {
  local file="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$file"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  ! grep -Fq -- "$pattern" "$file"
}

write_shared_env() {
  cat >"$ENV_DIR/gitlab-runner-shared.env" <<EOF
GITLAB_RUNNER_ENV_DIR="$ENV_DIR"
GITLAB_RUNNER_STATE_BASE="$STATE_BASE"
GITLAB_RUNNER_USER_HOME_BASE="$HOME_BASE"
GITLAB_RUNNER_PODMAN_CONFIG_BASE="$PODMAN_CONFIG_BASE"
GITLAB_RUNNER_PODMAN_STATE_BASE="$PODMAN_STATE_BASE"
GITLAB_RUNNER_PODMAN_TMP_BASE="$PODMAN_STATE_BASE"
GITLAB_RUNNER_CONTAINER_BUILDS_DIR="/builds"
GITLAB_RUNNER_CONTAINER_CACHE_DIR="/cache"
GITLAB_RUNNER_CONFIG_BASENAME="config.toml"
GITLAB_RUNNER_SYSTEM_ID_BASENAME=".runner_system_id"
GITLAB_RUNNER_CONFIG_GROUP="devops"
GITLAB_RUNNER_CONTROL_DIR_MODE="0750"
GITLAB_RUNNER_CONTROL_FILE_MODE="0640"
GITLAB_RUNNER_CONCURRENT="1"
GITLAB_RUNNER_LIMIT="1"
GITLAB_RUNNER_REQUEST_CONCURRENCY="1"
GITLAB_RUNNER_OUTPUT_LIMIT="32768"
GITLAB_RUNNER_CACHE_MAX_UPLOADED_ARCHIVE_SIZE="1073741824"
GITLAB_RUNNER_CHECK_INTERVAL="3"
GITLAB_RUNNER_CONNECTION_MAX_AGE="15m"
GITLAB_RUNNER_SHUTDOWN_TIMEOUT="30"
GITLAB_RUNNER_LOG_LEVEL="info"
GITLAB_RUNNER_LOG_FORMAT="json"
GITLAB_RUNNER_RUN_UNTAGGED="false"
GITLAB_RUNNER_LOCKED="true"
GITLAB_RUNNER_CLEAN_GIT_CONFIG="true"
GITLAB_RUNNER_DEBUG_TRACE_DISABLED="true"
GITLAB_RUNNER_CUSTOM_BUILD_DIR_ENABLED="false"
GITLAB_RUNNER_REQUIRE_PODMAN="true"
GITLAB_RUNNER_VERIFY_ACTIVE="true"
GITLAB_RUNNER_SERVICE_STABLE_SECONDS="2"
GITLAB_RUNNER_DOCKER_TLS_VERIFY="false"
GITLAB_RUNNER_DOCKER_PRIVILEGED="false"
GITLAB_RUNNER_DOCKER_PULL_POLICY="if-not-present"
GITLAB_RUNNER_ALLOWED_PULL_POLICIES="always,if-not-present"
GITLAB_RUNNER_DOCKER_SECURITY_OPTS="no-new-privileges:true"
GITLAB_RUNNER_CAP_DROP="NET_RAW"
GITLAB_RUNNER_SERVICES_LIMIT="5"
GITLAB_RUNNER_ENABLE_CCACHE="true"
GITLAB_RUNNER_ENABLE_SCCACHE="true"
GITLAB_RUNNER_CCACHE_MAX_SIZE="20G"
GITLAB_RUNNER_SCCACHE_CACHE_SIZE="20G"
GITLAB_RUNNER_CCACHE_COMPRESS="true"
GITLAB_RUNNER_CCACHE_COMPRESSLEVEL="6"
GITLAB_RUNNER_CCACHE_COMPILERCHECK="content"
GITLAB_RUNNER_CACHE_DIR_NAMES='
xdg
'
EOF
}

write_runner_envs() {
  cat >"$ENV_DIR/gitlab-runner-build.env" <<EOF
GITLAB_RUNNER_BUILD_USERNAME="glab-user"
GITLAB_RUNNER_BUILD_GITLAB_URL="https://gitlab.com"
GITLAB_RUNNER_BUILD_TOKEN="build-token"
GITLAB_RUNNER_BUILD_NAME="build"
GITLAB_RUNNER_BUILD_TAGS="build"
GITLAB_RUNNER_BUILD_METRICS_ADDRESS="127.0.0.1:9272"
GITLAB_RUNNER_BUILD_IMAGE="docker.io/library/debian:trixie-slim"
GITLAB_RUNNER_BUILD_IMAGE_BUILD_MODE="none"
GITLAB_RUNNER_BUILD_BUILDS_DIR="$TMP_ROOT/pool/build/runners/build"
GITLAB_RUNNER_BUILD_GITLAB_CACHE_DIR="$TMP_ROOT/pool/cache/runners/build/gitlab"
GITLAB_RUNNER_BUILD_CACHE_ROOT="$TMP_ROOT/pool/cache/runners/build/tools"
GITLAB_RUNNER_BUILD_ALLOWED_IMAGES="debian:*"
GITLAB_RUNNER_BUILD_ALLOWED_SERVICES="postgres:*"
GITLAB_RUNNER_BUILD_EXTRA_VOLUMES=""
EOF
  cat >"$ENV_DIR/gitlab-runner-aptly.env" <<EOF
GITLAB_RUNNER_APTLY_USERNAME="glab-aptly"
GITLAB_RUNNER_APTLY_GITLAB_URL="https://gitlab.com"
GITLAB_RUNNER_APTLY_TOKEN=""
GITLAB_RUNNER_APTLY_NAME="aptly"
GITLAB_RUNNER_APTLY_TAGS="aptly"
GITLAB_RUNNER_APTLY_METRICS_ADDRESS="127.0.0.1:9271"
GITLAB_RUNNER_APTLY_DOCKER_USERNS_MODE="keep-id"
GITLAB_RUNNER_APTLY_IMAGE="localhost/gitlab-runner-aptly:trixie"
GITLAB_RUNNER_APTLY_IMAGE_BUILD_MODE="containerfile"
GITLAB_RUNNER_APTLY_IMAGE_CONTEXT="$TMP_ROOT/pool/aptly"
GITLAB_RUNNER_APTLY_IMAGE_CONTAINERFILE="$TMP_ROOT/pool/aptly/Containerfile"
GITLAB_RUNNER_APTLY_BUILDS_DIR="$TMP_ROOT/pool/build/aptly"
GITLAB_RUNNER_APTLY_GITLAB_CACHE_DIR="$TMP_ROOT/pool/cache/aptly/gitlab"
GITLAB_RUNNER_APTLY_CACHE_ROOT="$TMP_ROOT/pool/cache/aptly/tools"
GITLAB_RUNNER_APTLY_ALLOWED_IMAGES="debian:*"
GITLAB_RUNNER_APTLY_ALLOWED_SERVICES="postgres:*"
GITLAB_RUNNER_APTLY_EXTRA_VOLUMES=""
GITLAB_RUNNER_APTLY_SBUILD_ARCH="amd64"
GITLAB_RUNNER_APTLY_SBUILD_SUITES="stable testing unstable"
GITLAB_RUNNER_APTLY_SBUILD_MIRROR="https://deb.debian.org/debian"
GITLAB_RUNNER_APTLY_SBUILD_TARBALL_DIR="$TMP_ROOT/pool/cache/aptly/tools/sbuild"
EOF
}

printf '1..%s\n' "$TEST_COUNT"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gitlab-runner-managed-functional.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

ENV_DIR="$TMP_ROOT/etc/default/gitlab-runner"
STATE_BASE="$TMP_ROOT/data/config/runners"
HOME_BASE="$TMP_ROOT/data/services/usr"
PODMAN_CONFIG_BASE="$TMP_ROOT/data/config/podman"
PODMAN_STATE_BASE="$TMP_ROOT/pool/podman"
RUNTIME_BASE="$TMP_ROOT/run/user"
CONFIG_PATH="$STATE_BASE/glab-user/config.toml"
SYSTEMCTL_LOG="$TMP_ROOT/systemctl.log"
SYSTEMCTL_STATE="$TMP_ROOT/systemctl.state"
SYSTEMCTL_EVENTS="$TMP_ROOT/systemctl.events"
PODMAN_LOG="$TMP_ROOT/podman.log"
PATCHED_HELPER="$TMP_ROOT/gitlab-runner-managed"
MOCK_BIN="$TMP_ROOT/bin"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

mkdir -p "$ENV_DIR" "$MOCK_BIN" "$RUNTIME_BASE/$CURRENT_UID" "$STATE_BASE/glab-user" "$TMP_ROOT/pool/aptly/bin"
: >"$STATE_BASE/glab-user/.runner_system_id"
write_shared_env
write_runner_envs
cat >"$TMP_ROOT/pool/aptly/Containerfile" <<'EOF'
FROM docker.io/library/debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends aptly python3 \
    && rm -rf /var/lib/apt/lists/*
EOF
mkdir -p "$TMP_ROOT/pool/aptly/.aptly"
chmod 0700 "$TMP_ROOT/pool/aptly/.aptly"
printf '{}\n' >"$TMP_ROOT/pool/aptly/.aptly.conf.template.json"
cat >"$TMP_ROOT/pool/aptly/bin/prepare-aptly-env.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

aptly_bool_value() {
  case "${1,,}" in
    1|true|yes|y|on) printf 'true' ;;
    0|false|no|n|off|"") printf 'false' ;;
    *) return 1 ;;
  esac
}

aptly_normalize_endpoint_host() {
  printf 'example.invalid'
}

aptly_normalize_prefix() {
  local value="${1:-}"
  value="${value#/}"
  value="${value%/}"
  printf '%s' "${value:-debian}"
}

aptly_render_config_file() {
  local _template_path="$1"
  local config_path="$2"
  printf '{"rootDir":"%s"}\n' "$3" >"$config_path"
}
EOF
chmod +x "$TMP_ROOT/pool/aptly/bin/prepare-aptly-env.sh"

cat >"$MOCK_BIN/getent" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "glab-user" ]]; then
  printf 'glab-user:x:%s:%s::%s/glab-user:/usr/sbin/nologin\n' "$CURRENT_UID" "$CURRENT_GID" "$HOME_BASE"
  exit 0
fi
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "glab-aptly" ]]; then
  printf 'glab-aptly:x:%s:%s::%s/glab-aptly:/usr/sbin/nologin\n' "$CURRENT_UID" "$CURRENT_GID" "$HOME_BASE"
  exit 0
fi
exit 2
EOF
chmod +x "$MOCK_BIN/getent"

cat >"$MOCK_BIN/mmdebstrap" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

tarball_path=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --architectures=*|--variant=*|--include=*|--skip=*)
      shift
      ;;
    --architectures|--variant|--include|--skip)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

: "${2:?missing tarball path}"
tarball_path="$2"
mkdir -p "$(dirname "$tarball_path")"
printf 'mock tarball\n' >"$tarball_path"
EOF
chmod +x "$MOCK_BIN/mmdebstrap"

cat >"$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$TEST_SYSTEMCTL_LOG"
case "$*" in
  "--user show-environment")
    exit 0
    ;;
  "--user daemon-reload")
    exit 0
    ;;
  "--user enable gitlab-runner.service")
    printf 'enabled\n' >>"$TEST_SYSTEMCTL_EVENTS"
    exit 0
    ;;
  "--user is-failed --quiet gitlab-runner.service")
    if [[ -f "$TEST_SYSTEMCTL_STATE" ]] && [[ "$(cat "$TEST_SYSTEMCTL_STATE")" == "failed" ]]; then
      exit 0
    fi
    exit 1
    ;;
  "--user reset-failed gitlab-runner.service")
    exit 0
    ;;
  "--user reset-failed podman.service")
    exit 0
    ;;
  "--user reset-failed podman.socket")
    exit 0
    ;;
  "--user restart podman.service")
    printf 'podman-restart\n' >>"$TEST_SYSTEMCTL_EVENTS"
    exit 0
    ;;
  "--user restart podman.socket")
    printf 'podman-socket-restart\n' >>"$TEST_SYSTEMCTL_EVENTS"
    exit 0
    ;;
  "--user restart gitlab-runner.service")
    rm -f "${TEST_SYSTEMCTL_STATE}.active-count"
    if [[ "${TEST_SYSTEMCTL_START_MODE:-active}" == "failed" ]]; then
      printf 'failed\n' >"$TEST_SYSTEMCTL_STATE"
    elif [[ "${TEST_SYSTEMCTL_START_MODE:-active}" == "flap" ]]; then
      printf 'active\n' >"$TEST_SYSTEMCTL_STATE"
    else
      printf 'active\n' >"$TEST_SYSTEMCTL_STATE"
    fi
    printf 'restart\n' >>"$TEST_SYSTEMCTL_EVENTS"
    exit 0
    ;;
  "--user start gitlab-runner.service")
    rm -f "${TEST_SYSTEMCTL_STATE}.active-count"
    if [[ "${TEST_SYSTEMCTL_START_MODE:-active}" == "failed" ]]; then
      printf 'failed\n' >"$TEST_SYSTEMCTL_STATE"
    elif [[ "${TEST_SYSTEMCTL_START_MODE:-active}" == "flap" ]]; then
      printf 'active\n' >"$TEST_SYSTEMCTL_STATE"
    else
      printf 'active\n' >"$TEST_SYSTEMCTL_STATE"
    fi
    exit 0
    ;;
  "--user is-active --quiet gitlab-runner.service")
    if [[ "${TEST_SYSTEMCTL_START_MODE:-active}" == "flap" ]] && [[ -f "$TEST_SYSTEMCTL_STATE" ]] && [[ "$(cat "$TEST_SYSTEMCTL_STATE")" == "active" ]]; then
      count=0
      if [[ -f "${TEST_SYSTEMCTL_STATE}.active-count" ]]; then
        count="$(cat "${TEST_SYSTEMCTL_STATE}.active-count")"
      fi
      if [[ "$count" == "0" ]]; then
        printf '1\n' >"${TEST_SYSTEMCTL_STATE}.active-count"
        printf 'failed\n' >"$TEST_SYSTEMCTL_STATE"
        exit 0
      fi
    fi
    if [[ -f "$TEST_SYSTEMCTL_STATE" ]] && [[ "$(cat "$TEST_SYSTEMCTL_STATE")" == "active" ]]; then
      exit 0
    fi
    exit 3
    ;;
  "--user is-active --quiet podman.service")
    if [[ "${TEST_PODMAN_SERVICE_ACTIVE:-true}" == "true" ]]; then
      exit 0
    fi
    exit 3
    ;;
esac
printf 'unexpected systemctl args: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/systemctl"

cat >"$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  info)
    printf 'true|netavark\n'
    exit 0
    ;;
  ps)
    exit 0
    ;;
esac
printf 'unexpected podman args: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/podman"

cat >"$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${HOME:-}" != "${TEST_EXPECTED_PODMAN_HOME:-}" ]]; then
  printf 'unexpected podman HOME: %s\n' "${HOME:-unset}" >&2
  exit 1
fi
if [[ "${XDG_RUNTIME_DIR:-}" != "${TEST_EXPECTED_XDG_RUNTIME_DIR:-}" ]]; then
  printf 'unexpected XDG_RUNTIME_DIR: %s\n' "${XDG_RUNTIME_DIR:-unset}" >&2
  exit 1
fi
case "${1:-}" in
  info)
    printf 'true|netavark\n'
    exit 0
    ;;
  image)
    if [[ "${2:-}" == "exists" ]]; then
      [[ "${TEST_PODMAN_IMAGE_EXISTS:-false}" == "true" ]] && exit 0
      exit 1
    fi
    ;;
  build)
    printf '%s\n' "$*" >>"$TEST_PODMAN_LOG"
    context_path="${*: -1}"
    containerfile_path=
    prev=
    for arg in "$@"; do
      if [[ "$prev" == "-f" ]]; then
        containerfile_path="$arg"
        break
      fi
      prev="$arg"
    done
    [[ -n "$containerfile_path" ]] || {
      printf 'missing containerfile build arg\n' >&2
      exit 1
    }
    [[ "$context_path" != "$TEST_FORBIDDEN_CONTEXT" ]] || {
      printf 'forbidden build context reused: %s\n' "$context_path" >&2
      exit 1
    }
    [[ "$containerfile_path" != "$TEST_FORBIDDEN_CONTAINERFILE" ]] || {
      printf 'forbidden containerfile path reused: %s\n' "$containerfile_path" >&2
      exit 1
    }
    [[ -d "$context_path" ]] || {
      printf 'synthetic build context missing: %s\n' "$context_path" >&2
      exit 1
    }
    [[ -r "$containerfile_path" ]] || {
      printf 'synthetic containerfile missing: %s\n' "$containerfile_path" >&2
      exit 1
    }
    [[ ! -e "$context_path/.aptly" ]] || {
      printf 'synthetic build context leaked aptly state: %s\n' "$context_path/.aptly" >&2
      exit 1
    }
    grep -Fq 'FROM docker.io/library/debian:trixie-slim' "$containerfile_path" || {
      printf 'unexpected containerfile contents: %s\n' "$containerfile_path" >&2
      exit 1
    }
    exit 0
    ;;
  ps)
    exit 0
    ;;
esac
printf 'unexpected podman args: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/podman"

sed \
  -e "s|^ENV_DIR=.*|ENV_DIR=\"$ENV_DIR\"|" \
  -e "s|/pool/aptly|$TMP_ROOT/pool/aptly|g" \
  -e "s|context_runtime_root=\"/run/user/\${context_uid}/gitlab-runner\"|context_runtime_root=\"$RUNTIME_BASE/\${context_uid}/gitlab-runner\"|" \
  -e "s|context_podman_runtime_root=\"/run/user/\${context_uid}\"|context_podman_runtime_root=\"$RUNTIME_BASE/\${context_uid}\"|" \
  -e "s|context_podman_runtime_libpod_dir=\"/run/user/\${context_uid}/libpod\"|context_podman_runtime_libpod_dir=\"$RUNTIME_BASE/\${context_uid}/libpod\"|" \
  -e "s|context_podman_runroot=\"/run/user/\${context_uid}/run\"|context_podman_runroot=\"$RUNTIME_BASE/\${context_uid}/run\"|" \
  "$MANAGED_HELPER" >"$PATCHED_HELPER"
chmod +x "$PATCHED_HELPER"

export PATH="$MOCK_BIN:$PATH"
export TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG"
export TEST_SYSTEMCTL_STATE="$SYSTEMCTL_STATE"
export TEST_SYSTEMCTL_EVENTS="$SYSTEMCTL_EVENTS"
export TEST_PODMAN_LOG="$PODMAN_LOG"
export TEST_EXPECTED_PODMAN_HOME="$HOME_BASE/glab-user"
export TEST_EXPECTED_XDG_RUNTIME_DIR="/run/user/$CURRENT_UID"
export TEST_FORBIDDEN_CONTEXT="$TMP_ROOT/pool/aptly"
export TEST_FORBIDDEN_CONTAINERFILE="$TMP_ROOT/pool/aptly/Containerfile"

if bash "$PATCHED_HELPER" --user glab-user refresh --require-active >"$TMP_ROOT/first.stdout" 2>"$TMP_ROOT/first.stderr"; then
  pass "refresh succeeds with only the build token populated"
else
  fail "refresh succeeds with only the build token populated"
fi

if bash "$PATCHED_HELPER" --user glab-user preflight >"$TMP_ROOT/preflight-first.stdout" 2>"$TMP_ROOT/preflight-first.stderr"; then
  pass "preflight succeeds with only the build token populated"
else
  fail "preflight succeeds with only the build token populated"
fi

if assert_contains "$CONFIG_PATH" 'name = "build"' &&
   assert_not_contains "$CONFIG_PATH" 'name = "task"'; then
  pass "single-token render keeps only the build runner stanza"
else
  fail "single-token render keeps only the build runner stanza"
fi

if [ -f "$STATE_BASE/glab-user/.runner_system_id" ] &&
   [ ! -e "$STATE_BASE/glab-user/work/.runner_system_id" ]; then
  pass "runner system-id state is created alongside config.toml instead of under the writable work subtree"
else
  fail "runner system-id state is created alongside config.toml instead of under the writable work subtree"
fi

if [ -d "$RUNTIME_BASE/$CURRENT_UID/run/networks/rootless-netns" ] &&
   [ -d "$RUNTIME_BASE/$CURRENT_UID/libpod/tmp" ] &&
   [ -d "$PODMAN_STATE_BASE/glab-user/storage" ] &&
   [ -d "$PODMAN_STATE_BASE/glab-user/libpod" ]; then
  pass "preflight prepares rootless Podman runtime state under /run and persistent storage state under /pool"
else
  fail "preflight prepares rootless Podman runtime state under /run and persistent storage state under /pool"
fi

if assert_not_contains "$CONFIG_PATH" 'DOCKER_HOST=' &&
   assert_not_contains "$CONFIG_PATH" 'CONTAINER_HOST=' &&
   assert_not_contains "$CONFIG_PATH" '/podman/podman.sock:' &&
   assert_contains "$CONFIG_PATH" 'TMPDIR=/tmp' &&
   assert_contains "$CONFIG_PATH" 'TEMP=/tmp' &&
   assert_contains "$CONFIG_PATH" '"/tmp"' &&
   assert_not_contains "$CONFIG_PATH" "$RUNTIME_BASE/$CURRENT_UID/gitlab-runner/tmp:"; then
  pass "rendered config keeps Podman as the executor backend without injecting the socket into job containers"
else
  fail "rendered config keeps Podman as the executor backend without injecting the socket into job containers"
fi

if [ ! -e "$ENV_DIR/gitlab-runner-task.env" ]; then
  pass "legacy task runner env is absent from the managed fixture"
else
  fail "legacy task runner env is absent from the managed fixture"
fi

mkdir -p "$STATE_BASE/glab-aptly"
: >"$STATE_BASE/glab-aptly/.runner_system_id"
sed -i 's/^GITLAB_RUNNER_APTLY_TOKEN=""/GITLAB_RUNNER_APTLY_TOKEN="aptly-token"/' "$ENV_DIR/gitlab-runner-aptly.env"
export TEST_EXPECTED_PODMAN_HOME="$HOME_BASE/glab-aptly"
export TEST_PODMAN_IMAGE_EXISTS="false"
APTLY_JOB_HOME="$STATE_BASE/glab-aptly/home"
APTLY_SBUILD_CONFIG="$APTLY_JOB_HOME/.config/sbuild/config.pl"
APTLY_SBUILD_STABLE="$TMP_ROOT/pool/cache/aptly/tools/sbuild/stable-amd64-sbuild.tar.gz"
APTLY_SBUILD_TESTING="$TMP_ROOT/pool/cache/aptly/tools/sbuild/testing-amd64-sbuild.tar.gz"
APTLY_SBUILD_UNSTABLE="$TMP_ROOT/pool/cache/aptly/tools/sbuild/unstable-amd64-sbuild.tar.gz"

if bash "$PATCHED_HELPER" --user glab-aptly ensure-images >"$TMP_ROOT/aptly-images.stdout" 2>"$TMP_ROOT/aptly-images.stderr"; then
  pass "aptly ensure-images succeeds after the token is populated"
else
  fail "aptly ensure-images succeeds after the token is populated"
fi

if assert_contains "$PODMAN_LOG" "build --pull=missing --tag localhost/gitlab-runner-aptly:trixie" &&
   assert_not_contains "$PODMAN_LOG" " $TMP_ROOT/pool/aptly"; then
  pass "aptly ensure-images builds from a synthetic readable context instead of traversing the protected aptly state"
else
  fail "aptly ensure-images builds from a synthetic readable context instead of traversing the protected aptly state"
fi

if [ -f "$APTLY_SBUILD_STABLE" ] &&
   [ -f "$APTLY_SBUILD_TESTING" ] &&
   [ -f "$APTLY_SBUILD_UNSTABLE" ]; then
  pass "aptly ensure-images seeds the stable, testing, and unstable sbuild tarballs"
else
  fail "aptly ensure-images seeds the stable, testing, and unstable sbuild tarballs"
fi

if [ -f "$APTLY_SBUILD_CONFIG" ] &&
   assert_contains "$APTLY_SBUILD_CONFIG" '$chroot_mode = "unshare";'; then
  pass "aptly ensure-images renders the managed sbuild config file"
else
  fail "aptly ensure-images renders the managed sbuild config file"
fi

[ "$FAIL_COUNT" -eq 0 ]
