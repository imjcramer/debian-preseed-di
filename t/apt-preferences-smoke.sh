#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/apt-preferences-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=4
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
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

make_source_tree() {
  source_root=$1
  mkdir -p "$source_root/classes"
  cp "$ROOT_DIR/d-i/debian/repo.env" "$source_root/repo.env"
  cp "$ROOT_DIR/d-i/debian/classes/CLASSES.conf" "$source_root/classes/CLASSES.conf"
  cat >>"$source_root/classes/CLASSES.conf" <<'EOF'

[class.addon.testprefs]
description=test additive apt preference merge
debian_apt_preferences=sid dbus forky test

[class.addon.minprefs]
description=test override without repo defaults
debian_apt_preferences=sid test
EOF
}

run_case() {
  case_name=$1
  selected_refs=$2
  output_path=$3
  error_path=$4

  source_root="$TMP_DIR/$case_name"
  mkdir -p "$source_root"
  make_source_tree "$source_root"

  if (
    set -eu
    INSTALLER_SOURCE_ROOT=$source_root
    INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-$case_name"
    INSTALLER_SELECTED_CLASS_REFS=$selected_refs
    export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR INSTALLER_SELECTED_CLASS_REFS
    # shellcheck disable=SC1090
    . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
    printf 'config=%s\n' "$(installer_apt_preferences_config)"
    printf 'names='
    installer_configured_apt_preferences | paste -sd, -
    printf '\n'
  ) >"$output_path" 2>"$error_path"; then
    return 0
  fi

  return 1
}

extract_value() {
  key=$1
  output_path=$2
  sed -n "s/^${key}=//p" "$output_path" | head -n 1
}

printf '1..%s\n' "$TEST_COUNT"

fallback_out="$TMP_DIR/fallback.out"
fallback_err="$TMP_DIR/fallback.err"
if run_case fallback "" "$fallback_out" "$fallback_err"; then
  if [ "$(extract_value config "$fallback_out")" = "sid,forky,dbus" ] &&
     [ "$(extract_value names "$fallback_out")" = "sid.pref,forky.pref,dbus.pref" ]; then
    pass "repo.env apt preferences remain the fallback"
  else
    fail "repo.env apt preferences remain the fallback" "$fallback_out"
  fi
else
  fail "repo.env apt preferences remain the fallback" "$fallback_err"
fi

forky_out="$TMP_DIR/forky.out"
forky_err="$TMP_DIR/forky.err"
if run_case forky "addon/forky" "$forky_out" "$forky_err"; then
  if [ "$(extract_value config "$forky_out")" = "trixie,sid,dbus" ] &&
     [ "$(extract_value names "$forky_out")" = "trixie.pref,sid.pref,dbus.pref" ]; then
    pass "single class apt preference metadata overrides repo.env"
  else
    fail "single class apt preference metadata overrides repo.env" "$forky_out"
  fi
else
  fail "single class apt preference metadata overrides repo.env" "$forky_err"
fi

merged_out="$TMP_DIR/merged.out"
merged_err="$TMP_DIR/merged.err"
if run_case merged "addon/forky addon/testprefs" "$merged_out" "$merged_err"; then
  if [ "$(extract_value config "$merged_out")" = "trixie,sid,dbus,forky,test" ] &&
     [ "$(extract_value names "$merged_out")" = "trixie.pref,sid.pref,dbus.pref,forky.pref,test.pref" ]; then
    pass "multiple class apt preference metadata merges with deduplication"
  else
    fail "multiple class apt preference metadata merges with deduplication" "$merged_out"
  fi
else
  fail "multiple class apt preference metadata merges with deduplication" "$merged_err"
fi

override_out="$TMP_DIR/override.out"
override_err="$TMP_DIR/override.err"
if run_case override "addon/minprefs" "$override_out" "$override_err"; then
  if [ "$(extract_value config "$override_out")" = "sid,test" ] &&
     [ "$(extract_value names "$override_out")" = "sid.pref,test.pref" ]; then
    pass "class metadata replaces repo.env instead of appending it"
  else
    fail "class metadata replaces repo.env instead of appending it" "$override_out"
  fi
else
  fail "class metadata replaces repo.env instead of appending it" "$override_err"
fi

[ "$FAIL_COUNT" -eq 0 ]
