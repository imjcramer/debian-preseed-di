#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-dock"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-dock.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
HOME_DIR="${TMP_DIR}/home"
STATE_DIR="${TMP_DIR}/state"
EVENT_LOG="${TMP_DIR}/events.log"
PID_PATH="${STATE_DIR}/labwc/crystal-dock.pid"

TEST_COUNT=2
TEST_INDEX=0

cleanup() {
  if [ -r "$PID_PATH" ]; then
    IFS= read -r dock_pid <"$PID_PATH" || true
    if [ -n "${dock_pid:-}" ]; then
      kill "$dock_pid" >/dev/null 2>&1 || true
      kill -KILL "$dock_pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

install -d -m 0700 "$BIN_DIR" "$HOME_DIR" "$STATE_DIR"

cat >"${BIN_DIR}/dockfakebin" <<'EOF'
#!/bin/sh
set -eu
printf 'start %s\n' "$$" >>"$EVENT_LOG"
trap 'printf "term %s\n" "$$" >>"$EVENT_LOG"; sleep "${FAKE_DOCK_EXIT_DELAY_SECONDS:-0}"; printf "exit %s\n" "$$" >>"$EVENT_LOG"; exit 0' TERM INT
while :; do
  sleep 1
done
EOF
chmod 0700 "${BIN_DIR}/dockfakebin"

run_dock() {
  PATH="${BIN_DIR}:$PATH" \
  EVENT_LOG="$EVENT_LOG" \
  HOME="$HOME_DIR" \
  XDG_STATE_HOME="$STATE_DIR" \
  LABWC_CRYSTAL_DOCK_COMMAND="dockfakebin" \
  LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS="${LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS:-0}" \
  LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS="${LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS:-4}" \
  FAKE_DOCK_EXIT_DELAY_SECONDS="${FAKE_DOCK_EXIT_DELAY_SECONDS:-0}" \
    /bin/sh "$SCRIPT" "${1:-}"
}

printf '1..%s\n' "$TEST_COUNT"

: >"$EVENT_LOG"
run_dock
if [ -r "$PID_PATH" ] &&
   IFS= read -r first_pid <"$PID_PATH" &&
   [ -n "$first_pid" ] &&
   kill -0 "$first_pid" >/dev/null 2>&1 &&
   grep -Eq '^start [0-9]+$' "$EVENT_LOG"; then
  pass "labwc-dock starts the managed crystal dock process and records its pid"
else
  fail "labwc-dock starts the managed crystal dock process and records its pid"
fi

FAKE_DOCK_EXIT_DELAY_SECONDS=1 \
LABWC_CRYSTAL_DOCK_RESTART_DELAY_SECONDS=0 \
LABWC_CRYSTAL_DOCK_STOP_TIMEOUT_SECONDS=4 \
run_dock --restart

if [ -r "$PID_PATH" ] &&
   IFS= read -r second_pid <"$PID_PATH" &&
   [ -n "$second_pid" ] &&
   [ "$second_pid" != "$first_pid" ] &&
   kill -0 "$second_pid" >/dev/null 2>&1 &&
   [ "$(grep -c '^start ' "$EVENT_LOG")" -eq 2 ] &&
   grep -Eq "^term ${first_pid}\$" "$EVENT_LOG" &&
   grep -Eq "^exit ${first_pid}\$" "$EVENT_LOG"; then
  pass "labwc-dock restart waits for the old dock to exit before starting a new one"
else
  fail "labwc-dock restart waits for the old dock to exit before starting a new one"
fi
