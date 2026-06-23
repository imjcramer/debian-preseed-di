#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="${ROOT_DIR}/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-admin-action"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-admin-action.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=3
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

make_case() {
  case_name=$1
  case_dir="${TMP_DIR}/${case_name}"
  bin_dir="${case_dir}/bin"
  home_dir="${case_dir}/home"
  log_file="${case_dir}/actions.log"

  mkdir -p "$bin_dir" "$home_dir/.config/labwc"
  : >"$log_file"

  cat >"${bin_dir}/systemctl" <<'EOF'
#!/bin/sh
set -eu
printf 'systemctl %s\n' "$*" >>"$ACTION_LOG"
exit "${SYSTEMCTL_EXIT_CODE:-0}"
EOF
  chmod 0755 "${bin_dir}/systemctl"

  cat >"${home_dir}/.config/labwc/shutdown" <<'EOF'
#!/bin/sh
set -eu
printf 'shutdown-hook\n' >>"$ACTION_LOG"
EOF
  chmod 0755 "${home_dir}/.config/labwc/shutdown"

  printf '%s\n' "$case_dir"
}

printf '1..%s\n' "$TEST_COUNT"

case_dir=$(make_case reboot-success)
if PATH="${case_dir}/bin:/usr/bin:/bin" \
   HOME="${case_dir}/home" \
   ACTION_LOG="${case_dir}/actions.log" \
   SYSTEMCTL_EXIT_CODE=0 \
   /bin/sh "$SCRIPT" reboot &&
   [ "$(cat "${case_dir}/actions.log")" = "systemctl reboot
shutdown-hook" ]; then
  pass "reboot keeps the session alive for auth and runs the shutdown hook only after success"
else
  fail "reboot keeps the session alive for auth and runs the shutdown hook only after success"
fi

case_dir=$(make_case poweroff-failure)
if PATH="${case_dir}/bin:/usr/bin:/bin" \
   HOME="${case_dir}/home" \
   ACTION_LOG="${case_dir}/actions.log" \
   SYSTEMCTL_EXIT_CODE=1 \
   /bin/sh "$SCRIPT" poweroff; then
  fail "poweroff propagates systemctl failures without tearing down the session first"
elif [ "$(cat "${case_dir}/actions.log")" = "systemctl poweroff" ]; then
  pass "poweroff propagates systemctl failures without tearing down the session first"
else
  fail "poweroff propagates systemctl failures without tearing down the session first"
fi

case_dir=$(make_case suspend-success)
if PATH="${case_dir}/bin:/usr/bin:/bin" \
   HOME="${case_dir}/home" \
   ACTION_LOG="${case_dir}/actions.log" \
   SYSTEMCTL_EXIT_CODE=0 \
   /bin/sh "$SCRIPT" suspend &&
   [ "$(cat "${case_dir}/actions.log")" = "systemctl suspend" ]; then
  pass "suspend skips the shutdown hook and only issues the suspend request"
else
  fail "suspend skips the shutdown hook and only issues the suspend request"
fi
