#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT_DIR/d-i/debian/scripts/late/podman.sh"

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
}

installer_fatal() {
  printf 'fatal: %s\n' "$*" >&2
  exit 1
}

printf '1..%s\n' "$TEST_COUNT"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/podman-registries-render.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT
RENDERED="$TMP_ROOT/registries.conf"

# shellcheck disable=SC1090
. "$HELPER"

PODMAN_SHORT_NAME_MODE="disabled"
PODMAN_UNQUALIFIED_SEARCH_REGISTRIES=""
PODMAN_BLOCKED_REGISTRIES=""
PODMAN_TLS_ENABLE=0
PODMAN_TLS_REGISTRIES=""

podman_render_registries_conf_file "$RENDERED"

if grep -q '^short-name-mode = "disabled"$' "$RENDERED" &&
   grep -q '^unqualified-search-registries = \[\]$' "$RENDERED"; then
  pass "renderer emits the static registries header for the TLS-disabled case"
else
  fail "renderer emits the static registries header for the TLS-disabled case"
fi

if [ "$(wc -l <"$RENDERED")" -eq 2 ] &&
   ! grep -q '__INSTALLER_' "$RENDERED"; then
  pass "renderer omits unresolved placeholder lines when both registry block sets are empty"
else
  fail "renderer omits unresolved placeholder lines when both registry block sets are empty"
fi

PODMAN_BLOCKED_REGISTRIES="docker.io"
PODMAN_TLS_ENABLE=1
PODMAN_TLS_REGISTRIES="127.0.0.1:5000,localhost:5000"

podman_render_registries_conf_file "$RENDERED"

if [ "$(grep -c '^\[\[registry\]\]$' "$RENDERED")" -eq 3 ] &&
   grep -q '^location = "docker.io"$' "$RENDERED" &&
   grep -q '^blocked = true$' "$RENDERED"; then
  pass "renderer emits blocked registry blocks when they are configured"
else
  fail "renderer emits blocked registry blocks when they are configured"
fi

if [ "$(grep -c '^blocked = false$' "$RENDERED")" -eq 2 ] &&
   grep -q '^location = "127.0.0.1:5000"$' "$RENDERED" &&
   grep -q '^location = "localhost:5000"$' "$RENDERED" &&
   [ "$(grep -c '^insecure = false$' "$RENDERED")" -eq 3 ]; then
  pass "renderer emits explicit TLS registry blocks without marking them insecure"
else
  fail "renderer emits explicit TLS registry blocks without marking them insecure"
fi

[ "$FAIL_COUNT" -eq 0 ]
