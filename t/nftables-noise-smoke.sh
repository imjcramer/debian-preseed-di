#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

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

printf '1..%s\n' "$TEST_COUNT"

generator="$ROOT_DIR/d-i/debian/hooks/shared/target/usr/local/sbin/nft-policy-generate.py"
server_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/nftables/profiles/server.yml"
desktop_profile="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/nftables/profiles/desktop.yml"

if grep -q '^def build_link_local_noise_drop_rules' "$generator" &&
   grep -q 'meta pkttype { broadcast, multicast } counter drop' "$generator"; then
  pass "nftables generator adds explicit silent drops for unmatched broadcast and multicast noise"
else
  fail "nftables generator adds explicit silent drops for unmatched broadcast and multicast noise"
fi

if grep -q 'if egress_enforced(policy):' "$generator" &&
   grep -q 'silent link-local noise output' "$generator"; then
  pass "nftables generator limits silent output noise drops to profiles with enforced egress"
else
  fail "nftables generator limits silent output noise drops to profiles with enforced egress"
fi

if grep -q '^egress:$' "$server_profile" &&
   grep -q '^  mode: strict$' "$server_profile" &&
   grep -q '^  enforce: false$' "$server_profile"; then
  pass "server profile keeps strict egress expressed through mode while the generator decides output-drop handling"
else
  fail "server profile keeps strict egress expressed through mode while the generator decides output-drop handling"
fi

if grep -q '^  egress_audit:$' "$desktop_profile" &&
   grep -q '^    enabled: true$' "$desktop_profile"; then
  pass "desktop profile still keeps explicit outbound audit enabled after noise-drop changes"
else
  fail "desktop profile still keeps explicit outbound audit enabled after noise-drop changes"
fi

[ "$FAIL_COUNT" -eq 0 ]
