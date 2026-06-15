#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MANAGED_HELPER="$ROOT_DIR/d-i/debian/hooks/services/gitlab/target/usr/local/sbin/gitlab-runner-managed"

TEST_COUNT=8
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
  local task_token="$1"
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
  cat >"$ENV_DIR/gitlab-runner-task.env" <<EOF
GITLAB_RUNNER_TASK_USERNAME="glab-user"
GITLAB_RUNNER_TASK_GITLAB_URL="https://gitlab.com"
GITLAB_RUNNER_TASK_TOKEN="$task_token"
GITLAB_RUNNER_TASK_NAME="task"
GITLAB_RUNNER_TASK_TAGS="task"
GITLAB_RUNNER_TASK_METRICS_ADDRESS="127.0.0.1:9272"
GITLAB_RUNNER_TASK_IMAGE="docker.io/library/debian:trixie-slim"
GITLAB_RUNNER_TASK_IMAGE_BUILD_MODE="none"
GITLAB_RUNNER_TASK_BUILDS_DIR="$TMP_ROOT/pool/build/runners/task"
GITLAB_RUNNER_TASK_GITLAB_CACHE_DIR="$TMP_ROOT/pool/cache/runners/task/gitlab"
GITLAB_RUNNER_TASK_CACHE_ROOT="$TMP_ROOT/pool/cache/runners/task/tools"
GITLAB_RUNNER_TASK_ALLOWED_IMAGES="debian:*"
GITLAB_RUNNER_TASK_ALLOWED_SERVICES="postgres:*"
GITLAB_RUNNER_TASK_EXTRA_VOLUMES=""
EOF
  cat >"$ENV_DIR/gitlab-runner-aptly.env" <<EOF
GITLAB_RUNNER_APTLY_USERNAME="glab-aptly"
GITLAB_RUNNER_APTLY_TOKEN=""
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
PATCHED_HELPER="$TMP_ROOT/gitlab-runner-managed"
MOCK_BIN="$TMP_ROOT/bin"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

mkdir -p "$ENV_DIR" "$MOCK_BIN" "$RUNTIME_BASE/$CURRENT_UID"
write_shared_env
write_runner_envs ""

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
  "--user kill --signal=HUP --kill-whom=main gitlab-runner.service")
    if [[ "${TEST_SYSTEMCTL_KILL_FAIL:-false}" == "true" ]]; then
      printf 'failed\n' >"$TEST_SYSTEMCTL_STATE"
      exit 1
    fi
    printf 'hup\n' >>"$TEST_SYSTEMCTL_EVENTS"
    exit 0
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
  -e "s|context_runtime_root=\"/run/user/\${context_uid}/gitlab-runner\"|context_runtime_root=\"$RUNTIME_BASE/\${context_uid}/gitlab-runner\"|" \
  "$MANAGED_HELPER" >"$PATCHED_HELPER"
chmod +x "$PATCHED_HELPER"

export PATH="$MOCK_BIN:$PATH"
export TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG"
export TEST_SYSTEMCTL_STATE="$SYSTEMCTL_STATE"
export TEST_SYSTEMCTL_EVENTS="$SYSTEMCTL_EVENTS"
export TEST_EXPECTED_PODMAN_HOME="$HOME_BASE/glab-user"
export TEST_EXPECTED_XDG_RUNTIME_DIR="/run/user/$CURRENT_UID"

if bash "$PATCHED_HELPER" --user glab-user once >"$TMP_ROOT/first.stdout" 2>"$TMP_ROOT/first.stderr"; then
  pass "once succeeds with only the build token populated"
else
  fail "once succeeds with only the build token populated"
fi

if assert_contains "$CONFIG_PATH" 'name = "build"' &&
   assert_not_contains "$CONFIG_PATH" 'name = "task"'; then
  pass "single-token render keeps only the build runner stanza"
else
  fail "single-token render keeps only the build runner stanza"
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

: >"$SYSTEMCTL_LOG"
write_runner_envs "task-token"

if bash "$PATCHED_HELPER" --user glab-user once >"$TMP_ROOT/second.stdout" 2>"$TMP_ROOT/second.stderr"; then
  pass "rerunning once succeeds after the task token is added"
else
  fail "rerunning once succeeds after the task token is added"
fi

if assert_contains "$CONFIG_PATH" 'name = "build"' &&
   assert_contains "$CONFIG_PATH" 'name = "task"'; then
  pass "rerunning once renders both shared runner stanzas when both tokens are present"
else
  fail "rerunning once renders both shared runner stanzas when both tokens are present"
fi

if assert_not_contains "$CONFIG_PATH" 'DOCKER_HOST=' &&
   assert_not_contains "$CONFIG_PATH" 'CONTAINER_HOST=' &&
   assert_not_contains "$CONFIG_PATH" '/podman/podman.sock:' &&
   assert_contains "$CONFIG_PATH" 'TMPDIR=/tmp' &&
   assert_contains "$CONFIG_PATH" 'TEMP=/tmp' &&
   assert_contains "$CONFIG_PATH" '"/tmp"' &&
   assert_not_contains "$CONFIG_PATH" "$RUNTIME_BASE/$CURRENT_UID/gitlab-runner/tmp:"; then
  pass "rerendered shared config still avoids recursive socket injection after task enablement"
else
  fail "rerendered shared config still avoids recursive socket injection after task enablement"
fi

: >"$SYSTEMCTL_LOG"
if bash "$PATCHED_HELPER" --user glab-user once >"$TMP_ROOT/third.stdout" 2>"$TMP_ROOT/third.stderr"; then
  :
else
  fail "rerunning once signals the active service to reload instead of forcing another start"
fi

if assert_contains "$SYSTEMCTL_LOG" '--user kill --signal=HUP --kill-whom=main gitlab-runner.service' &&
   assert_not_contains "$SYSTEMCTL_LOG" '--user start gitlab-runner.service'; then
  pass "rerunning once signals the active service to reload instead of forcing another start"
else
  fail "rerunning once signals the active service to reload instead of forcing another start"
fi

: >"$SYSTEMCTL_LOG"
printf 'active\n' >"$SYSTEMCTL_STATE"
TEST_SYSTEMCTL_KILL_FAIL=true bash "$PATCHED_HELPER" --user glab-user once >"$TMP_ROOT/fourth.stdout" 2>"$TMP_ROOT/fourth.stderr"
if assert_contains "$SYSTEMCTL_LOG" '--user kill --signal=HUP --kill-whom=main gitlab-runner.service' &&
   assert_contains "$SYSTEMCTL_LOG" '--user start gitlab-runner.service'; then
  pass "once falls back to a real start when the active-unit reload path has no main process"
else
  fail "once falls back to a real start when the active-unit reload path has no main process"
fi

[ "$FAIL_COUNT" -eq 0 ]
