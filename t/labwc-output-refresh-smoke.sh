#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-output-refresh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-output-refresh.XXXXXX")
BIN_DIR="${TMP_DIR}/bin"
HOME_DIR="${TMP_DIR}/home"
STATE_FILE="${TMP_DIR}/wlr-randr.state"
NEXT_STATE_FILE="${TMP_DIR}/wlr-randr.next"
TRANSITION_MARKER="${TMP_DIR}/wlr-randr.transitioned"
LOG_FILE="${TMP_DIR}/wlr-randr.log"
ACTION_LOG="${TMP_DIR}/actions.log"

TEST_COUNT=7
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

install -d -m 0700 "$BIN_DIR" "$HOME_DIR/.config/waybar"
: >"$HOME_DIR/.config/waybar/config"
: >"$HOME_DIR/.config/waybar/style.css"

cat >"${BIN_DIR}/wlr-randr" <<'EOF'
#!/bin/sh
set -eu
if [ "$#" -eq 0 ]; then
  cat "$WLR_RANDR_STATE"
  exit 0
fi
printf '%s\n' "$*" >>"$WLR_RANDR_LOG"
if [ -n "${WLR_RANDR_NEXT_STATE:-}" ] &&
   [ -r "$WLR_RANDR_NEXT_STATE" ] &&
   [ ! -e "$WLR_RANDR_TRANSITION_MARKER" ]; then
  cp "$WLR_RANDR_NEXT_STATE" "$WLR_RANDR_STATE"
  : >"$WLR_RANDR_TRANSITION_MARKER"
fi
EOF
chmod 0700 "${BIN_DIR}/wlr-randr"

cat >"${BIN_DIR}/wlopm" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0700 "${BIN_DIR}/wlopm"

cat >"${BIN_DIR}/pgrep" <<'EOF'
#!/bin/sh
set -eu
process_name=
for arg in "$@"; do
  process_name=$arg
done
case "$process_name" in
  waybar)
    [ "${PGREP_WAYBAR:-false}" = true ]
    ;;
  crystal-dock)
    [ "${PGREP_DOCK:-false}" = true ]
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 0700 "${BIN_DIR}/pgrep"

cat >"${BIN_DIR}/pkill" <<'EOF'
#!/bin/sh
set -eu
printf 'pkill %s\n' "$*" >>"$ACTION_LOG"
exit 0
EOF
chmod 0700 "${BIN_DIR}/pkill"

cat >"${BIN_DIR}/waybar" <<'EOF'
#!/bin/sh
set -eu
printf 'waybar %s\n' "$*" >>"$ACTION_LOG"
exit 0
EOF
chmod 0700 "${BIN_DIR}/waybar"

cat >"${BIN_DIR}/labwc-dock" <<'EOF'
#!/bin/sh
set -eu
printf 'labwc-dock %s\n' "$*" >>"$ACTION_LOG"
exit 0
EOF
chmod 0700 "${BIN_DIR}/labwc-dock"

write_state() {
  cat >"$STATE_FILE"
}

write_next_state() {
  cat >"$NEXT_STATE_FILE"
}

run_refresh() {
  : >"$LOG_FILE"
  : >"$ACTION_LOG"
  rm -f "$TRANSITION_MARKER"

  PATH="${BIN_DIR}:$PATH" \
  HOME="$HOME_DIR" \
  ACTION_LOG="$ACTION_LOG" \
  PGREP_WAYBAR="${PGREP_WAYBAR:-false}" \
  PGREP_DOCK="${PGREP_DOCK:-false}" \
  WAYLAND_DISPLAY="wayland-1" \
  WLR_RANDR_LOG="$LOG_FILE" \
  WLR_RANDR_NEXT_STATE="${WLR_RANDR_NEXT_STATE:-}" \
  WLR_RANDR_STATE="$STATE_FILE" \
  WLR_RANDR_TRANSITION_MARKER="$TRANSITION_MARKER" \
  LABWC_CRYSTAL_DOCK_COMMAND="crystal-dock" \
  LABWC_ENABLE_CRYSTAL_DOCK="${LABWC_ENABLE_CRYSTAL_DOCK:-true}" \
  LABWC_ENABLE_WAYBAR="${LABWC_ENABLE_WAYBAR:-true}" \
  LABWC_OUTPUT_EXTERNAL_SCALE="${LABWC_OUTPUT_EXTERNAL_SCALE:-1.80}" \
  LABWC_OUTPUT_FALLBACK_REFRESH_HZ="${LABWC_OUTPUT_FALLBACK_REFRESH_HZ:-60}" \
  LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
  LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS="${LABWC_OUTPUT_INTERNAL_REFRESH_DELAY_SECONDS:-0}" \
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
if grep -F -q -- '--output HDMI-A-1 --on --mode 3840x2160@60.000000Hz --scale 1.80 --pos 0,0' "$LOG_FILE"; then
  pass "default external output uses connector preferred mode with the managed external scale"
else
  fail "default external output uses connector preferred mode with the managed external scale"
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
HOME="$HOME_DIR" \
ACTION_LOG="$ACTION_LOG" \
WAYLAND_DISPLAY="wayland-1" \
WLR_RANDR_LOG="$LOG_FILE" \
WLR_RANDR_STATE="$STATE_FILE" \
LABWC_OUTPUT_INTERNAL_PREFIXES="eDP LVDS DSI" \
LABWC_OUTPUT_POLICY="external-only" \
LABWC_OUTPUT_SCALE="1" \
LABWC_OUTPUT_EXTERNAL_SCALE="1.80" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_WIDTH="1920" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_HEIGHT="1080" \
LABWC_OUTPUT_EXTERNAL_PREFERRED_REFRESH_HZ="120" \
  perl "$SCRIPT"
if grep -F -q -- '--output HDMI-A-1 --on --mode 1920x1080@120.000000Hz --scale 1.80 --pos 0,0' "$LOG_FILE"; then
  pass "configured external output mode remains opt-in"
else
  fail "configured external output mode remains opt-in"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    2560x1440 px, 144.000000 Hz
    2560x1440 px, 60.000000 Hz
    1920x1080 px, 120.000000 Hz
EOF
LABWC_OUTPUT_FALLBACK_REFRESH_HZ=60 run_refresh
if grep -F -q -- '--output HDMI-A-1 --on --mode 2560x1440@60.000000Hz --scale 1.80 --pos 0,0' "$LOG_FILE"; then
  pass "largest fallback mode prefers the configured fallback refresh"
else
  fail "largest fallback mode prefers the configured fallback refresh"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
PGREP_WAYBAR=true \
PGREP_DOCK=true \
run_refresh
if grep -Eq 'pkill .*-x waybar$' "$ACTION_LOG" &&
   grep -F -q -- 'labwc-dock --restart' "$ACTION_LOG"; then
  pass "stored topology changes still restart session chrome after unplug auto-reconfiguration"
else
  fail "stored topology changes still restart session chrome after unplug auto-reconfiguration"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
PGREP_WAYBAR=true \
PGREP_DOCK=true \
run_refresh
if grep -Eq 'pkill .*-x waybar$' "$ACTION_LOG" &&
   grep -F -q -- "waybar -c $HOME_DIR/.config/waybar/config -s $HOME_DIR/.config/waybar/style.css" "$ACTION_LOG" &&
   grep -F -q -- 'labwc-dock --restart' "$ACTION_LOG"; then
  pass "topology changes restart the running session chrome coherently"
else
  fail "topology changes restart the running session chrome coherently"
fi

write_state <<'EOF'
HDMI-A-1 "External"
  Enabled: yes
  Modes:
    1920x1080 px, 60.000000 Hz (preferred)
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
write_next_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
WLR_RANDR_NEXT_STATE="$NEXT_STATE_FILE" \
PGREP_WAYBAR=false \
PGREP_DOCK=false \
run_refresh
if [ "$(cat "$ACTION_LOG")" = "labwc-dock --restart" ]; then
  pass "topology changes restart crystal dock even when it already disappeared"
else
  fail "topology changes restart crystal dock even when it already disappeared"
fi

write_state <<'EOF'
eDP-1 "Internal"
  Enabled: yes
  Modes:
    1920x1200 px, 60.000000 Hz (preferred)
EOF
PGREP_WAYBAR=true \
PGREP_DOCK=true \
run_refresh
if [ ! -s "$ACTION_LOG" ]; then
  pass "unchanged topology avoids unnecessary waybar and dock restarts"
else
  fail "unchanged topology avoids unnecessary waybar and dock restarts"
fi
