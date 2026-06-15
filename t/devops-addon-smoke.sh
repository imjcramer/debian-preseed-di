#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/devops-addon-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=5
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

classes_conf="$ROOT_DIR/d-i/debian/classes/CLASSES.conf"
devops_class="$ROOT_DIR/d-i/debian/classes/class-addon/devops.cfg"
devops_late="$ROOT_DIR/d-i/debian/scripts/late/devops.sh"
storage_maintenance="$ROOT_DIR/d-i/debian/scripts/late/storage-maintenance.sh"

if grep -q '^\[class\.addon\.devops\]$' "$classes_conf" &&
   grep -q '^late_helper=devops$' "$classes_conf"; then
  pass "devops addon is wired to its late helper"
else
  fail "devops addon is wired to its late helper"
fi

if grep -q '^d-i pkgsel/include string .*just .*rustup .*gh/trixie .*glab .*build-essential .*shellcheck .*hyperfine .*sccache' "$devops_class"; then
  pass "devops addon installs the requested development package baseline"
else
  fail "devops addon installs the requested development package baseline"
fi

target_root="$TMP_DIR/target"
account_env="$TMP_DIR/account.env"
bin_dir="$TMP_DIR/bin"
runtime_dir="$TMP_DIR/runtime"
host_env="$TMP_DIR/host.env"
mkdir -p "$target_root/etc" "$bin_dir" "$runtime_dir/bootstrap"
mkdir -p "$target_root/pool/build" "$target_root/pool/cache" "$target_root/pool/db"
cat >"$target_root/etc/passwd" <<'EOF'
root:x:1000:1000:root:/root:/bin/sh
mcramer:x:1000:1000:Matthew Cramer:/home/mcramer:/bin/zsh
EOF
cat >"$account_env" <<'EOF'
ACCOUNT_USERNAME="mcramer"
EOF
cat >"$host_env" <<'EOF'
DIR_POOL="/pool"
DIR_POOL_BUILD="/pool/build"
DIR_POOL_CACHE="/pool/cache"
DIR_POOL_DB="/pool/db"
EOF
printf '%s\n' "$ROOT_DIR/d-i/debian" >"$runtime_dir/bootstrap/seed.file"
cat >"$bin_dir/sccache" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$bin_dir/sccache"

if INSTALLER_LATE_ACCOUNT_ENV="$account_env" \
   INSTALLER_LATE_HOST_ENV="$host_env" \
   INSTALLER_RUNTIME_DIR="$runtime_dir" \
   INSTALLER_BOOTSTRAP_LIB="$ROOT_DIR/d-i/debian/scripts/common/bootstrap.sh" \
   sh "$devops_late" "$target_root" >/dev/null &&
   [ -r "$target_root/etc/profile.d/70-devops-storage.sh" ] &&
   [ -r "$target_root/etc/tmpfiles.d/80-devops-storage.conf" ] &&
   grep -q '^d /pool/build 2770 root devops -$' "$target_root/etc/tmpfiles.d/80-devops-storage.conf" &&
   ! grep -q '__INSTALLER_DIR_POOL_' "$target_root/etc/profile.d/70-devops-storage.sh" &&
   ! grep -q '__INSTALLER_DIR_POOL_' "$target_root/etc/tmpfiles.d/80-devops-storage.conf" &&
   [ -d "$target_root/pool/build/mcramer" ] &&
   [ -d "$target_root/pool/cache/mcramer" ] &&
   [ -d "$target_root/pool/db/mcramer" ]; then
  pass "devops late helper stages /pool storage policy through the managed asset flow"
else
  fail "devops late helper stages /pool storage policy through the managed asset flow"
fi

profile_file="$target_root/etc/profile.d/70-devops-storage.sh"
profile_out=$(
  USER=mcramer HOME=/home/mcramer DEVOPS_POOL_ROOT="$target_root/pool" \
    PATH="$bin_dir:/usr/bin:/bin" sh -eu -c '. "$1"; printf "%s\n%s\n%s\n%s\n%s\n%s\n" "$DEVOPS_BUILD_HOME" "$XDG_CACHE_HOME" "$CARGO_TARGET_DIR" "$PIPX_HOME" "$SCCACHE_DIR" "${RUSTC_WRAPPER:-}"' sh "$profile_file"
)
if printf '%s\n' "$profile_out" | grep -F "$target_root/pool/build/mcramer" >/dev/null &&
   printf '%s\n' "$profile_out" | grep -F "$target_root/pool/cache/mcramer/xdg" >/dev/null &&
   printf '%s\n' "$profile_out" | grep -F "$target_root/pool/build/mcramer/cargo-target" >/dev/null &&
   printf '%s\n' "$profile_out" | grep -F "$target_root/pool/db/mcramer/pipx" >/dev/null &&
   printf '%s\n' "$profile_out" | grep -F "$target_root/pool/cache/mcramer/sccache" >/dev/null &&
   printf '%s\n' "$profile_out" | grep -Fx 'sccache' >/dev/null; then
  pass "devops profile exports /pool-backed build, cache, and db paths"
else
  fail "devops profile exports /pool-backed build, cache, and db paths"
fi

# shellcheck disable=SC2016
if grep -q 'query_pkg=${pkg%%/\*}' "$storage_maintenance" &&
   grep -q 'dpkg-query -W -f=\\${Status} "$query_pkg"' "$storage_maintenance"; then
  pass "pkgsel repair checks installed suite-qualified packages by binary package name"
else
  fail "pkgsel repair checks installed suite-qualified packages by binary package name"
fi

[ "$FAIL_COUNT" -eq 0 ]
