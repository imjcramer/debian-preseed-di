#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nvidia-desktop-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=8
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

printf '1..%s\n' "$TEST_COUNT"

nvidia_class="$ROOT_DIR/d-i/debian/classes/class-addon/nvidia.cfg"
addons_cfg="$ROOT_DIR/d-i/debian/classes/configs/addons.cfg"
if grep -Eq '(^|[[:space:]])nvidia-driver-595-open([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-settings([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-suspend-common([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-vaapi-driver([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])nvidia-vdpau-driver([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])libnvidia-egl-wayland1([[:space:]]|$)' "$nvidia_class" &&
   grep -Eq '(^|[[:space:]])switcheroo-control([[:space:]]|$)' "$nvidia_class" &&
   ! grep -Eq '(^|[[:space:]])bumblebee([[:space:]]|$)' "$nvidia_class" &&
   grep -q '^DebianAptPreferences: nvidia, x11$' "$addons_cfg"; then
  pass "nvidia addon installs the managed Wayland and media stack and declares apt pinning"
else
  fail "nvidia addon installs the managed Wayland and media stack and declares apt pinning"
fi

desktop_packages="$ROOT_DIR/d-i/debian/classes/class-select/role/desktop.cfg"
if grep -Eq '(^|[[:space:]])mesa-utils([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])mesa-va-drivers([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])mesa-vdpau-drivers([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])vainfo([[:space:]]|$)' "$desktop_packages" &&
   grep -Eq '(^|[[:space:]])libva-wayland2([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])mesa-vulkan-drivers([[:space:]]|$)' "$desktop_packages" &&
   ! grep -Eq '(^|[[:space:]])vulkan-tools([[:space:]]|$)' "$desktop_packages"; then
  pass "desktop role installs the shared VAAPI tooling baseline without Vulkan packages"
else
  fail "desktop role installs the shared VAAPI tooling baseline without Vulkan packages"
fi

intel_gpu_class="$ROOT_DIR/d-i/debian/classes/class-auto/gpu/intel-uhd.cfg"
if grep -Eq '(^|[[:space:]])intel-media-va-driver([[:space:]]|$)' "$intel_gpu_class"; then
  pass "intel graphics class installs the modern Intel media driver"
else
  fail "intel graphics class installs the modern Intel media driver"
fi

nvidia_pref="$ROOT_DIR/d-i/debian/hooks/shared/target/etc/apt/preferences.d/nvidia.pref"
if grep -q '^Pin: release o=xanmod$' "$nvidia_pref" &&
   grep -q '^Pin-Priority: 900$' "$nvidia_pref" &&
   grep -q '^Package: nvidia-driver-595-open nvidia-settings nvidia-suspend-common nvidia-vaapi-driver nvidia-vdpau-driver libnvidia-egl-wayland1$' "$nvidia_pref"; then
  pass "nvidia apt preference prefers the XanMod NVIDIA driver set"
else
  fail "nvidia apt preference prefers the XanMod NVIDIA driver set"
fi

prefs_out="$TMP_DIR/prefs.out"
prefs_err="$TMP_DIR/prefs.err"
if (
  set -eu
  INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian"
  INSTALLER_RUNTIME_DIR="$TMP_DIR/runtime-prefs"
  INSTALLER_SELECTED_CLASS_REFS='addon/nvidia'
  export INSTALLER_SOURCE_ROOT INSTALLER_RUNTIME_DIR INSTALLER_SELECTED_CLASS_REFS
  # shellcheck disable=SC1090
  . "$ROOT_DIR/d-i/debian/scripts/common/lib.sh"
  installer_configured_apt_preferences | paste -sd, -
) >"$prefs_out" 2>"$prefs_err"; then
  if [ "$(cat "$prefs_out")" = "nvidia.pref,x11.pref" ]; then
    pass "nvidia addon resolves the dedicated apt preference file"
  else
    fail "nvidia addon resolves the dedicated apt preference file" "$prefs_out"
  fi
else
  fail "nvidia addon resolves the dedicated apt preference file" "$prefs_err"
fi

waybar_icon="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/waybar/icons/nvidia.svg"
if [ -r "$waybar_icon" ] &&
   grep -q '<svg' "$waybar_icon"; then
  pass "nvidia icon is staged under the Waybar skel icons directory"
else
  fail "nvidia icon is staged under the Waybar skel icons directory"
fi

waybar_template="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/waybar/config.tmpl"
waybar_style="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/skel/.config/waybar/style.css"
if grep -q '"custom/dgpu"' "$waybar_template" &&
   grep -q '#custom-dgpu' "$waybar_style" &&
   grep -q 'background-image: url("icons/nvidia.svg");' "$waybar_style"; then
  pass "Waybar carries the conditional dGPU module hook and NVIDIA icon styling"
else
  fail "Waybar carries the conditional dGPU module hook and NVIDIA icon styling"
fi

dgpu_launcher="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/usr/local/bin/labwc-dgpu-launcher"
chromium_flags="$ROOT_DIR/d-i/debian/hooks/role/desktop/target/etc/chromium.d/90-preseed-performance-flags.tmpl"
if grep -q 'launch_argv = \["switcherooctl", "launch", "--"\]' "$dgpu_launcher" &&
   grep -q 'drun-print_desktop_file=true' "$dgpu_launcher" &&
   grep -q 'resolve_selection' "$dgpu_launcher" &&
   grep -q 'expand_exec_tokens' "$dgpu_launcher" &&
   grep -q '^CHROMIUM_FLAGS=.*--ozone-platform-hint=auto' "$chromium_flags" &&
   grep -q 'AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxZeroCopyGL' "$chromium_flags" &&
   ! grep -q '^CHROMIUM_FLAGS=.*VaapiOnNvidiaGPUs' "$chromium_flags"; then
  pass "dGPU launcher uses switcherooctl and Chromium keeps the managed Wayland GPU defaults"
else
  fail "dGPU launcher uses switcherooctl and Chromium keeps the managed Wayland GPU defaults"
fi

[ "$FAIL_COUNT" -eq 0 ]
