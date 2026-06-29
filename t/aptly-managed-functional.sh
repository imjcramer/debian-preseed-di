#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MANAGED_HELPER="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/sbin/aptly-managed"
PUBLISH_HELPER="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/usr/local/libexec/aptly-publish-managed"
APTLY_WRAPPER="$ROOT_DIR/d-i/debian/hooks/services/gitlab-runner/target/pool/aptly/bin/aptly"

TEST_COUNT=3
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

dump_debug() {
  local label="$1"
  printf '# %s stderr\n' "$label"
  cat "$TMP_ROOT/${label}.stderr" 2>/dev/null || true
  printf '# aptly log\n'
  cat "$APTLY_LOG" 2>/dev/null || true
  printf '# aptly state\n'
  cat "$APTLY_STATE_JSON" 2>/dev/null || true
}

printf '1..%s\n' "$TEST_COUNT"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aptly-managed-functional.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT
export TMPDIR="$TMP_ROOT/tmp"
mkdir -p "$TMPDIR"

ENV_DIR="$TMP_ROOT/etc/default/gitlab-runner"
STATE_ROOT="$TMP_ROOT/pool/aptly"
STATE_DIR="$STATE_ROOT/.managed/channels"
HOME_BASE="$TMP_ROOT/data/services/usr"
MOCK_BIN="$TMP_ROOT/bin"
MOCK_REAL="$MOCK_BIN/aptly-real"
PATCHED_HELPER="$TMP_ROOT/aptly-managed"
PATCHED_PUBLISH_HELPER="$TMP_ROOT/aptly-publish-managed"
PATCHED_WRAPPER="$TMP_ROOT/aptly-wrapper"
PREPARE_ENV="$TMP_ROOT/prepare-aptly-env.sh"
CONFIG_TEMPLATE="$STATE_ROOT/.aptly.conf.template.json"
APTLY_STATE_JSON="$TMP_ROOT/aptly-state.json"
APTLY_LOG="$TMP_ROOT/aptly.log"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

mkdir -p "$ENV_DIR" "$STATE_ROOT/bin" "$STATE_ROOT/.aptly" "$STATE_DIR" "$HOME_BASE/aptly" "$MOCK_BIN"
printf '{}\n' >"$CONFIG_TEMPLATE"
: >"$APTLY_LOG"

cat >"$ENV_DIR/gitlab-runner-shared.env" <<EOF
GITLAB_RUNNER_USER_HOME_BASE="$HOME_BASE"
EOF

cat >"$ENV_DIR/gitlab-runner-aptly.env" <<EOF
GITLAB_RUNNER_APTLY_USERNAME="glab-aptly"
GITLAB_RUNNER_APTLY_R2_BUCKET_NAME="cf-aptly-r2-prod"
GITLAB_RUNNER_APTLY_R2_ENDPOINT_URL="https://example.invalid"
GITLAB_RUNNER_APTLY_R2_ACCESS_KEY_ID="access-key"
GITLAB_RUNNER_APTLY_R2_SECRET_ACCESS_KEY="secret-key"
GITLAB_RUNNER_APTLY_GPG_SIGNING_KEY="ABC123"
GITLAB_RUNNER_APTLY_GPG_SIGNING_PASSPHRASE="secret-passphrase"
GITLAB_RUNNER_APTLY_R2_ENDPOINT_NAME="r2"
GITLAB_RUNNER_APTLY_R2_PREFIX="debian/"
GITLAB_RUNNER_APTLY_PUBLISH_COMPONENT="main"
GITLAB_RUNNER_APTLY_PUBLISH_ORIGIN="GitLab CI"
GITLAB_RUNNER_APTLY_PUBLISH_LABEL="GitLab CI"
GITLAB_RUNNER_APTLY_PUBLISH_ACQUIRE_BY_HASH="true"
GITLAB_RUNNER_APTLY_SKIP_CONTENTS="false"
GITLAB_RUNNER_APTLY_CHANNELS="stable testing unstable"
GITLAB_RUNNER_APTLY_CHANNEL_STATE_DIR="$STATE_DIR"
GITLAB_RUNNER_APTLY_CHANNEL_STABLE_DISTRIBUTION="stable"
GITLAB_RUNNER_APTLY_CHANNEL_STABLE_ENDPOINT="s3:r2:"
GITLAB_RUNNER_APTLY_CHANNEL_STABLE_PREFIX="."
GITLAB_RUNNER_APTLY_CHANNEL_STABLE_KEEP_SNAPSHOTS="2"
GITLAB_RUNNER_APTLY_CHANNEL_STABLE_MAX_AGE_DAYS="0"
GITLAB_RUNNER_APTLY_CHANNEL_TESTING_DISTRIBUTION="testing"
GITLAB_RUNNER_APTLY_CHANNEL_TESTING_ENDPOINT="s3:r2:"
GITLAB_RUNNER_APTLY_CHANNEL_TESTING_PREFIX="."
GITLAB_RUNNER_APTLY_CHANNEL_TESTING_KEEP_SNAPSHOTS="3"
GITLAB_RUNNER_APTLY_CHANNEL_TESTING_MAX_AGE_DAYS="14"
GITLAB_RUNNER_APTLY_CHANNEL_UNSTABLE_DISTRIBUTION="unstable"
GITLAB_RUNNER_APTLY_CHANNEL_UNSTABLE_ENDPOINT="s3:r2:"
GITLAB_RUNNER_APTLY_CHANNEL_UNSTABLE_PREFIX="."
GITLAB_RUNNER_APTLY_CHANNEL_UNSTABLE_KEEP_SNAPSHOTS="4"
GITLAB_RUNNER_APTLY_CHANNEL_UNSTABLE_MAX_AGE_DAYS="21"
EOF

cat >"$PREPARE_ENV" <<'EOF'
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
  printf '{"rootDir":"%s"}\n' "${APTLY_ROOT_DIR:-unset}" >"$config_path"
}

prepare_aptly_env() {
  export APTLY_REAL_BIN="${APTLY_REAL_BIN:?}"
  export APTLY_R2_BUCKET_NAME="${R2_BUCKET_NAME:-}"
  export APTLY_R2_ENDPOINT_HOST="example.invalid"
  export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-}"
  export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-}"
  export APTLY_JOB_DIR
  mkdir -p "${APTLY_JOB_TMP_BASE:-${TMPDIR:-/tmp}/aptly}"
  APTLY_JOB_DIR="$(mktemp -d "${APTLY_JOB_TMP_BASE:-${TMPDIR:-/tmp}/aptly}/job.XXXXXX")"
}
EOF
chmod +x "$PREPARE_ENV"

cat >"$MOCK_BIN/getent" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "glab-aptly" ]]; then
  printf 'glab-aptly:x:%s:%s::%s/glab-aptly:/usr/sbin/nologin\n' "$CURRENT_UID" "$CURRENT_GID" "$HOME_BASE"
  exit 0
fi
exit 2
EOF
chmod +x "$MOCK_BIN/getent"

cat >"$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "--" ]] && shift
export TEST_FAKE_ROOT=1
exec "$@"
EOF
chmod +x "$MOCK_BIN/sudo"

cat >"$MOCK_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${TEST_FAKE_ROOT:-0}" == "1" && "${1:-}" == "-u" ]]; then
  printf '0\n'
  exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$MOCK_BIN/id"

cat >"$MOCK_BIN/runuser" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "-u" ]] && shift 2
[[ "${1:-}" == "--" ]] && shift
exec "$@"
EOF
chmod +x "$MOCK_BIN/runuser"

cat >"$MOCK_BIN/chown" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF
chmod +x "$MOCK_BIN/chown"

cat >"$MOCK_REAL" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

state_file="${TEST_APTLY_STATE_JSON:?}"
log_file="${TEST_APTLY_LOG:?}"
printf '%s\n' "$*" >>"$log_file"

serve_api() {
  local listen_arg="$1"
  python3 - "$listen_arg" "$state_file" <<'PY'
import json
import pathlib
import signal
import socket
import sys
import urllib.parse

listen_arg = sys.argv[1]
state_path = pathlib.Path(sys.argv[2])
socket_path = pathlib.Path(listen_arg.removeprefix("-listen=unix://"))
try:
    socket_path.unlink()
except FileNotFoundError:
    pass

def load_state():
    return json.loads(state_path.read_text())

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(str(socket_path))
server.listen(5)

def cleanup(*_args):
    try:
        socket_path.unlink()
    except FileNotFoundError:
        pass
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

while True:
    conn, _addr = server.accept()
    with conn:
        request = conn.recv(65536).decode("utf-8", "replace")
        path = request.split(" ", 2)[1]
        parsed = urllib.parse.urlparse(path)
        state = load_state()
        if parsed.path == "/api/publish":
          body = json.dumps(state["publications"]).encode("utf-8")
        elif parsed.path == "/api/snapshots":
          snapshots = sorted(state["snapshots"], key=lambda item: item["CreatedAt"], reverse=True)
          body = json.dumps(snapshots).encode("utf-8")
        else:
          body = b'{"error":"not found"}'
          conn.sendall(
              b"HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n"
              + f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
              + body
          )
          continue
        conn.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
            + f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
            + body
        )
PY
}

mutate_state() {
  python3 - "$state_file" "$@" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
args = sys.argv[2:]
data = json.loads(state_path.read_text())

def split_target(value):
    parts = value.split(":", 2)
    if len(parts) == 3:
        return "s3", parts[2] or "."
    return "", value or "."

if args[:2] == ["publish", "switch"]:
    idx = 2
    while idx < len(args) and args[idx].startswith("-"):
        idx += 1
    distribution = args[idx]
    idx += 1
    target = args[idx]
    idx += 1
    snapshot = args[idx]
    storage, prefix = split_target(target)
    for publication in data["publications"]:
        if publication["Distribution"] == distribution:
            publication["Storage"] = storage
            publication["Prefix"] = prefix
            publication["SourceKind"] = "snapshot"
            publication["Sources"] = [{"Component": "main", "Name": snapshot}]
            break
elif args[:2] == ["publish", "snapshot"]:
    idx = 2
    distribution = ""
    while idx < len(args) and args[idx].startswith("-"):
        if args[idx].startswith("-distribution="):
            distribution = args[idx].split("=", 1)[1]
        idx += 1
    snapshot = args[idx]
    idx += 1
    target = args[idx] if idx < len(args) else "."
    storage, prefix = split_target(target)
    publication = {
        "Storage": storage,
        "Prefix": prefix,
        "Distribution": distribution,
        "SourceKind": "snapshot",
        "Sources": [{"Component": "main", "Name": snapshot}],
    }
    data["publications"] = [pub for pub in data["publications"] if pub["Distribution"] != distribution]
    data["publications"].append(publication)
elif args[:2] == ["snapshot", "drop"]:
    snapshot = args[2]
    data["snapshots"] = [item for item in data["snapshots"] if item["Name"] != snapshot]
elif args[:2] == ["db", "cleanup"]:
    pass
else:
    raise SystemExit(f"unsupported mock aptly invocation: {' '.join(args)}")

state_path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

case "${1:-}" in
  api)
    serve_api "$3"
    ;;
  publish|snapshot|db)
    mutate_state "$@"
    ;;
  *)
    printf 'unsupported mock aptly args: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_REAL"

cp "$APTLY_WRAPPER" "$PATCHED_WRAPPER"
chmod +x "$PATCHED_WRAPPER"

sed \
  -e "s|^ENV_DIR=.*|ENV_DIR=\"$ENV_DIR\"|" \
  -e "s|^APTLY_STATE_DIR_DEFAULT=.*|APTLY_STATE_DIR_DEFAULT=\"$STATE_ROOT\"|" \
  -e "s|^APTLY_PUBLISH_HELPER=.*|APTLY_PUBLISH_HELPER=\"$PATCHED_PUBLISH_HELPER\"|" \
  -e "s|/pool/aptly/bin/prepare-aptly-env.sh|$PREPARE_ENV|g" \
  "$MANAGED_HELPER" >"$PATCHED_HELPER"
chmod +x "$PATCHED_HELPER"

sed \
  -e "s|/pool/aptly/bin/aptly|$PATCHED_WRAPPER|g" \
  "$PUBLISH_HELPER" >"$PATCHED_PUBLISH_HELPER"
chmod +x "$PATCHED_PUBLISH_HELPER"

export PATH="$MOCK_BIN:$PATH"
export APTLY_REAL_BIN="$MOCK_REAL"
export TEST_APTLY_STATE_JSON="$APTLY_STATE_JSON"
export TEST_APTLY_LOG="$APTLY_LOG"

cat >"$STATE_DIR/stable.json" <<'EOF'
{
  "version": 1,
  "channel": "stable",
  "distribution": "stable",
  "releases": [
    {
      "sources": [{"component": "main", "name": "stable-001"}],
      "created_at": "2026-06-01T00:00:00+00:00",
      "published_at": "2026-06-01T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "stable-002"}],
      "created_at": "2026-06-10T00:00:00+00:00",
      "published_at": "2026-06-10T00:00:00+00:00"
    }
  ]
}
EOF

cat >"$APTLY_STATE_JSON" <<'EOF'
{
  "publications": [
    {
      "Storage": "s3",
      "Prefix": ".",
      "Distribution": "stable",
      "SourceKind": "snapshot",
      "Sources": [{"Component": "main", "Name": "stable-002"}]
    }
  ],
  "snapshots": [
    {"Name": "stable-001", "CreatedAt": "2026-06-01T00:00:00Z"},
    {"Name": "stable-002", "CreatedAt": "2026-06-10T00:00:00Z"},
    {"Name": "stable-003", "CreatedAt": "2026-06-17T00:00:00Z"}
  ]
}
EOF

if bash "$PATCHED_HELPER" --channel stable publish snapshot stable-003 >"$TMP_ROOT/stable.stdout" 2>"$TMP_ROOT/stable.stderr" &&
   assert_contains "$APTLY_LOG" "publish" &&
   assert_contains "$APTLY_LOG" "switch" &&
   assert_contains "$APTLY_LOG" "stable-003" &&
   assert_contains "$APTLY_LOG" "snapshot" &&
   assert_contains "$APTLY_LOG" "drop" &&
   assert_contains "$APTLY_LOG" "stable-001" &&
   assert_contains "$APTLY_LOG" "db" &&
   assert_contains "$APTLY_LOG" "cleanup" &&
   assert_contains "$STATE_DIR/stable.json" '"name": "stable-003"' &&
   assert_contains "$APTLY_STATE_JSON" '"Distribution": "stable"' &&
   assert_contains "$APTLY_STATE_JSON" '"Name": "stable-003"' &&
   ! assert_contains "$APTLY_STATE_JSON" '"Name": "stable-001"'; then
  pass "stable channel auto-switches an existing snapshot publication and keeps two rolling snapshots"
else
  dump_debug stable
  fail "stable channel auto-switches an existing snapshot publication and keeps two rolling snapshots"
fi

: >"$APTLY_LOG"
cat >"$STATE_DIR/testing.json" <<'EOF'
{
  "version": 1,
  "channel": "testing",
  "distribution": "testing",
  "releases": [
    {
      "sources": [{"component": "main", "name": "testing-001"}],
      "created_at": "2026-05-01T00:00:00+00:00",
      "published_at": "2026-05-01T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "testing-002"}],
      "created_at": "2026-05-20T00:00:00+00:00",
      "published_at": "2026-05-20T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "testing-003"}],
      "created_at": "2026-06-10T00:00:00+00:00",
      "published_at": "2026-06-10T00:00:00+00:00"
    }
  ]
}
EOF

cat >"$APTLY_STATE_JSON" <<'EOF'
{
  "publications": [
    {
      "Storage": "s3",
      "Prefix": ".",
      "Distribution": "testing",
      "SourceKind": "snapshot",
      "Sources": [{"Component": "main", "Name": "testing-003"}]
    }
  ],
  "snapshots": [
    {"Name": "testing-001", "CreatedAt": "2026-05-01T00:00:00Z"},
    {"Name": "testing-002", "CreatedAt": "2026-05-20T00:00:00Z"},
    {"Name": "testing-003", "CreatedAt": "2026-06-10T00:00:00Z"},
    {"Name": "testing-004", "CreatedAt": "2026-06-17T00:00:00Z"}
  ]
}
EOF

if bash "$PATCHED_HELPER" --channel testing publish switch testing testing-004 >"$TMP_ROOT/testing.stdout" 2>"$TMP_ROOT/testing.stderr" &&
   assert_contains "$APTLY_LOG" "publish" &&
   assert_contains "$APTLY_LOG" "switch" &&
   assert_contains "$APTLY_LOG" "testing-004" &&
   assert_contains "$APTLY_LOG" "snapshot" &&
   assert_contains "$APTLY_LOG" "drop" &&
   assert_contains "$APTLY_LOG" "testing-001" &&
   assert_contains "$APTLY_LOG" "testing-002" &&
   assert_contains "$APTLY_LOG" "db" &&
   assert_contains "$APTLY_LOG" "cleanup" &&
   assert_contains "$STATE_DIR/testing.json" '"name": "testing-004"' &&
   ! assert_contains "$APTLY_STATE_JSON" '"Name": "testing-001"' &&
   ! assert_contains "$APTLY_STATE_JSON" '"Name": "testing-002"'; then
  pass "testing channel accepts publish switch through the managed path and drops aged snapshots after confirmation"
else
  dump_debug testing
  fail "testing channel accepts publish switch through the managed path and drops aged snapshots after confirmation"
fi

: >"$APTLY_LOG"
cat >"$STATE_DIR/unstable.json" <<'EOF'
{
  "version": 1,
  "channel": "unstable",
  "distribution": "unstable",
  "releases": [
    {
      "sources": [{"component": "main", "name": "unstable-001"}],
      "created_at": "2026-05-01T00:00:00+00:00",
      "published_at": "2026-05-01T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "unstable-002"}],
      "created_at": "2026-06-08T00:00:00+00:00",
      "published_at": "2026-06-08T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "unstable-003"}],
      "created_at": "2026-06-14T00:00:00+00:00",
      "published_at": "2026-06-14T00:00:00+00:00"
    },
    {
      "sources": [{"component": "main", "name": "unstable-004"}],
      "created_at": "2026-06-20T00:00:00+00:00",
      "published_at": "2026-06-20T00:00:00+00:00"
    }
  ]
}
EOF

cat >"$APTLY_STATE_JSON" <<'EOF'
{
  "publications": [
    {
      "Storage": "s3",
      "Prefix": ".",
      "Distribution": "unstable",
      "SourceKind": "snapshot",
      "Sources": [{"Component": "main", "Name": "unstable-004"}]
    }
  ],
  "snapshots": [
    {"Name": "unstable-001", "CreatedAt": "2026-05-01T00:00:00Z"},
    {"Name": "unstable-002", "CreatedAt": "2026-06-08T00:00:00Z"},
    {"Name": "unstable-003", "CreatedAt": "2026-06-14T00:00:00Z"},
    {"Name": "unstable-004", "CreatedAt": "2026-06-20T00:00:00Z"},
    {"Name": "unstable-005", "CreatedAt": "2026-06-27T00:00:00Z"}
  ]
}
EOF

if bash "$PATCHED_HELPER" --channel unstable publish switch unstable unstable-005 >"$TMP_ROOT/unstable.stdout" 2>"$TMP_ROOT/unstable.stderr" &&
   assert_contains "$APTLY_LOG" "publish" &&
   assert_contains "$APTLY_LOG" "switch" &&
   assert_contains "$APTLY_LOG" "unstable-005" &&
   assert_contains "$APTLY_LOG" "snapshot" &&
   assert_contains "$APTLY_LOG" "drop" &&
   assert_contains "$APTLY_LOG" "unstable-001" &&
   ! assert_contains "$APTLY_LOG" "unstable-002" &&
   assert_contains "$APTLY_LOG" "db" &&
   assert_contains "$APTLY_LOG" "cleanup" &&
   assert_contains "$STATE_DIR/unstable.json" '"name": "unstable-005"' &&
   assert_contains "$STATE_DIR/unstable.json" '"name": "unstable-004"' &&
   assert_contains "$STATE_DIR/unstable.json" '"name": "unstable-003"' &&
   assert_contains "$STATE_DIR/unstable.json" '"name": "unstable-002"' &&
   ! assert_contains "$STATE_DIR/unstable.json" '"name": "unstable-001"' &&
   ! assert_contains "$APTLY_STATE_JSON" '"Name": "unstable-001"'; then
  pass "unstable channel keeps four recent snapshots with its own 21-day retention window"
else
  dump_debug unstable
  fail "unstable channel keeps four recent snapshots with its own 21-day retention window"
fi

[ "$FAIL_COUNT" -eq 0 ]
