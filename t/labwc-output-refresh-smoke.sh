#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-output-refresh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-output-refresh.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
STATE_FILE="${TMP_DIR}/wlr-randr.state"
LOG_FILE="${TMP_DIR}/wlr-randr.log"

TEST_COUNT=3
TEST_INDEX=0

cleanup() {
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

install -d -m 0700 "$BIN_DIR"
cat >"${BIN_DIR}/wlr-randr" <<'EOF'
#!/bin/sh
set -eu
if [ "$#" -eq 0 ]; then
  cat "$WLR_RANDR_STATE"
  exit 0
fi
printf '%s\n' "$*" >>"$WLR_RANDR_LOG"
EOF
chmod 0700 "${BIN_DIR}/wlr-randr"

cat >"${BIN_DIR}/wlopm" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0700 "${BIN_DIR}/wlopm"

write_state() {
  cat >"$STATE_FILE"
}

run_refresh() {
  : >"$LOG_FILE"
  PATH="${BIN_DIR}:$PATH" \
  WLR_RANDR_STATE="$STATE_FILE" \
  WLR_RANDR_LOG="$LOG_FILE" \
  LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
  LABWC_OUTPUT_POLICY="external-only" \
  LABWC_OUTPUT_SCALE="1" \
    perl "$SCRIPT"
}

printf '1..%s\n' "$TEST_COUNT"

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    3840x2160 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
DP-1 "Secondary"
  Enabled: yes
  Modes:
    2560x1440 px, 60.000000 Hz (preferred)
EOF
run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 3840x2160@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "default external output uses connector preferred mode"
else
  fail "default external output uses connector preferred mode"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 120.000000 Hz
    3840x2160 px, 60.000000 Hz (preferred)
EOF
: >"$LOG_FILE"
PATH="${BIN_DIR}:$PATH" \
WLR_RANDR_STATE="$STATE_FILE" \
WLR_RANDR_LOG="$LOG_FILE" \
LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
LABWC_OUTPUT_POLICY="external-only" \
LABWC_OUTPUT_SCALE="1" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="1920" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="1080" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120" \
  perl "$SCRIPT"
if grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "configured external output mode remains opt-in"
else
  fail "configured external output mode remains opt-in"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1280x720 px, 60.000000 Hz
    2560x1440 px, 60.000000 Hz
    1920x1080 px, 120.000000 Hz
EOF
run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 2560x1440@60.000000Hz --scale 1 --pos 0,0' "$LOG_FILE"; then
  pass "missing preferred marker falls back to largest mode"
else
  fail "missing preferred marker falls back to largest mode"
fi
