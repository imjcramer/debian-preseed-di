#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zram-module-list.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=1
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

printf '1..%s\n' "$TEST_COUNT"

expected="$TMP_DIR/expected.txt"
actual="$TMP_DIR/actual.txt"
diff_out="$TMP_DIR/diff.txt"

(
  CDPATH='' cd -- "$ROOT_DIR" &&
  find d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback -type f -name '*.pm' -print |
    sed 's#^d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback/##' |
    sort
) >"$expected"

(
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/late/zram-swap.sh"
  zram_perl_modules | sed '/^[[:space:]]*$/d' | sort
) >"$actual"

if diff -u "$expected" "$actual" >"$diff_out"; then
  pass "zram staged Perl module list matches the runtime module tree"
else
  fail "zram staged Perl module list matches the runtime module tree" "$diff_out"
fi
