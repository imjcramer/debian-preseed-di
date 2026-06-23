#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=7
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

desktop_packages="$ROOT_DIR/d-i/debian/classes/class-select/role/desktop.cfg"
desktop_components="$ROOT_DIR/d-i/debian/scripts/desktop/components.sh"
firstboot_validation="$ROOT_DIR/d-i/debian/scripts/firstboot/04-validation.sh"
gtkgreet_css="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/greetd/gtkgreet.css"
mpv_conf="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/mpv/mpv.conf"
mpv_input="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/mpv/input.conf"
target_assets="$ROOT_DIR/d-i/debian/scripts/late/target-assets.sh"
podman_late="$ROOT_DIR/d-i/debian/scripts/late/podman.sh"
docs_index="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/README.md"
podbin_doc="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/podbin.md"
podbin_bridge_doc="$ROOT_DIR/d-i/debian/hooks/shared/target/data/docs/podbin-service-bridge.md"
btrfs_family="$ROOT_DIR/d-i/debian/scripts/late/btrfs-family.sh"
f2fs_family="$ROOT_DIR/d-i/debian/scripts/late/f2fs-family.sh"

if grep -Eq '(^|[[:space:]])mpv([[:space:]]|$)' "$desktop_packages"; then
  pass "desktop package set installs mpv"
else
  fail "desktop package set installs mpv"
fi

if grep -q '/etc/skel/.config/mpv/mpv.conf' "$desktop_components" &&
   grep -q '/etc/skel/.config/mpv/input.conf' "$desktop_components" &&
   grep -q '.config/mpv \\' "$desktop_components" &&
   grep -q '/etc/skel/.config/mpv/mpv.conf' "$firstboot_validation" &&
   grep -q '/etc/skel/.config/mpv/input.conf' "$firstboot_validation" &&
   grep -Eq '^[[:space:]]+mpv[[:space:]]+\\$' "$firstboot_validation"; then
  pass "desktop role stages mpv config and validates it on first boot"
else
  fail "desktop role stages mpv config and validates it on first boot"
fi

if grep -q '^gpu-context=wayland$' "$mpv_conf" &&
   grep -q '^hwdec=auto-safe$' "$mpv_conf" &&
   grep -q '^save-position-on-quit=yes$' "$mpv_conf" &&
   grep -q '^volume-max=150$' "$mpv_conf" &&
   grep -q '^screenshot-directory=~/Pictures$' "$mpv_conf" &&
   grep -q '^WHEEL_UP add volume 2$' "$mpv_input" &&
   grep -q '^MBTN_BACK playlist-prev$' "$mpv_input"; then
  pass "mpv defaults are tuned for Wayland playback and practical desktop controls"
else
  fail "mpv defaults are tuned for Wayland playback and practical desktop controls"
fi

if grep -q '^  min-width: 720px;$' "$gtkgreet_css" &&
   grep -q '^  padding: 36px 40px;$' "$gtkgreet_css" &&
   grep -q '^  font-size: 20px;$' "$gtkgreet_css" &&
   grep -q '^  min-height: 34px;$' "$gtkgreet_css" &&
   grep -q '^  min-width: 420px;$' "$gtkgreet_css" &&
   grep -q '^  min-width: 240px;$' "$gtkgreet_css"; then
  pass "gtkgreet CSS enlarges the login card and entry controls"
else
  fail "gtkgreet CSS enlarges the login card and entry controls"
fi

if grep -q '^stage_target_helper_docs() {$' "$target_assets" &&
   grep -q 'stage_target_helper_docs podbin.md podbin-service-bridge.md' "$podman_late" &&
   grep -q '^stage_target_docs_index$' "$btrfs_family" &&
   grep -q '^stage_target_docs_index$' "$f2fs_family"; then
  pass "late-command docs logic stages the docs index and the full podbin guide set"
else
  fail "late-command docs logic stages the docs index and the full podbin guide set"
fi

if grep -q 'installer always stages this index' "$docs_index" &&
   grep -q '`podbin-service-bridge.md`' "$docs_index" &&
   grep -q '^## Root-admin lifecycle$' "$podbin_doc" &&
   grep -q '^## Daily-account bridge to the managed podsvc service$' "$podbin_doc" &&
   grep -q '^## Security model$' "$podbin_doc" &&
   grep -q '^## Discover the service environment$' "$podbin_bridge_doc" &&
   grep -q '^## Read-only Podman inspection$' "$podbin_bridge_doc" &&
   grep -q '^## Troubleshooting checklist$' "$podbin_bridge_doc"; then
  pass "staged podbin docs cover lifecycle, service bridge, and troubleshooting"
else
  fail "staged podbin docs cover lifecycle, service bridge, and troubleshooting"
fi

if grep -q '^sudo podbin --create-user alice$' "$podbin_doc" &&
   grep -q '^sudo podbin --service-env$' "$podbin_doc" &&
   grep -q '^sudo podbin --service-systemctl status podman.socket$' "$podbin_bridge_doc"; then
  pass "podbin docs include concrete operator command examples"
else
  fail "podbin docs include concrete operator command examples"
fi

[ "$FAIL_COUNT" -eq 0 ]
