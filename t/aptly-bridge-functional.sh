#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BRIDGE="$ROOT_DIR/d-i/debian/hooks/services/gitlab/target/pool/aptly/bin/aptly-bridge"

TEST_COUNT=2
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

emit_result() {
  local results_dir="$1"
  local request_path="$2"
  local exit_code="$3"
  local stdout_text="$4"
  local stderr_text="$5"
  python3 - "$results_dir" "$request_path" "$exit_code" "$stdout_text" "$stderr_text" <<'PY'
import json
import pathlib
import sys

results_dir = pathlib.Path(sys.argv[1])
request_path = pathlib.Path(sys.argv[2])
exit_code = int(sys.argv[3])
stdout_text = sys.argv[4]
stderr_text = sys.argv[5]
request_id = request_path.stem
payload = {
    "exit_code": exit_code,
    "status": "success" if exit_code == 0 else "error",
    "stdout": stdout_text,
    "stderr": stderr_text,
}
(results_dir / f"{request_id}.json").write_text(json.dumps(payload, indent=2) + "\n")
PY
}

printf '1..%s\n' "$TEST_COUNT"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aptly-bridge-functional.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

REQUESTS_DIR="$TMP_ROOT/requests"
RESULTS_DIR="$TMP_ROOT/results"
mkdir -p "$REQUESTS_DIR" "$RESULTS_DIR"

APTLY_BRIDGE_REQUESTS_DIR="$REQUESTS_DIR" \
APTLY_BRIDGE_RESULTS_DIR="$RESULTS_DIR" \
APTLY_BRIDGE_WAIT_SECONDS=5 \
APTLY_BRIDGE_POLL_INTERVAL=1 \
"$BRIDGE" submit publish snapshot demo s3:r2: >"$TMP_ROOT/success.stdout" 2>"$TMP_ROOT/success.stderr" &
bridge_pid=$!
request_path=
for _ in $(seq 1 50); do
  request_path=$(find "$REQUESTS_DIR" -maxdepth 1 -type f -name '*.json' | sort | head -n1 || true)
  if [[ -n "$request_path" ]]; then
    emit_result "$RESULTS_DIR" "$request_path" 0 "publish ok\n" "bridge stderr\n"
    break
  fi
  sleep 0.1
done
if wait "$bridge_pid"; then
  if [[ -n "$request_path" ]] &&
     assert_contains "$TMP_ROOT/success.stdout" "publish ok" &&
     assert_contains "$TMP_ROOT/success.stderr" "bridge stderr"; then
    pass "bridge submit returns the queued publish result back to the caller"
  else
    fail "bridge submit returns the queued publish result back to the caller"
  fi
else
  fail "bridge submit returns the queued publish result back to the caller"
fi

rm -f "$RESULTS_DIR"/*.json "$REQUESTS_DIR"/*.json
APTLY_BRIDGE_REQUESTS_DIR="$REQUESTS_DIR" \
APTLY_BRIDGE_RESULTS_DIR="$RESULTS_DIR" \
APTLY_BRIDGE_WAIT_SECONDS=5 \
APTLY_BRIDGE_POLL_INTERVAL=1 \
"$BRIDGE" submit publish snapshot demo s3:r2: >"$TMP_ROOT/fail.stdout" 2>"$TMP_ROOT/fail.stderr" &
bridge_pid=$!
request_path=
for _ in $(seq 1 50); do
  request_path=$(find "$REQUESTS_DIR" -maxdepth 1 -type f -name '*.json' | sort | head -n1 || true)
  if [[ -n "$request_path" ]]; then
    emit_result "$RESULTS_DIR" "$request_path" 7 "" "publish failed\n"
    break
  fi
  sleep 0.1
done
if wait "$bridge_pid"; then
  fail "bridge submit propagates publish failures"
else
  rc=$?
  if [[ "$rc" -eq 7 ]] &&
     [[ -n "$request_path" ]] &&
     assert_contains "$TMP_ROOT/fail.stderr" "publish failed"; then
    pass "bridge submit propagates publish failures"
  else
    fail "bridge submit propagates publish failures"
  fi
fi

[ "$FAIL_COUNT" -eq 0 ]
