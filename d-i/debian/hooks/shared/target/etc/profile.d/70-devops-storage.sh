# Managed by debian-preseed-di.
# Route development build outputs, caches, and tool state to /pool.

devops_storage_return() {
  return 0 2>/dev/null || exit 0
}

case "${USER:-}" in
  ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@-]*)
    devops_storage_return
    ;;
esac

DEVOPS_POOL_ROOT="${DEVOPS_POOL_ROOT:-__INSTALLER_DIR_POOL__}"
[ -d "$DEVOPS_POOL_ROOT" ] || devops_storage_return

DEVOPS_BUILD_HOME="${DEVOPS_BUILD_HOME:-${DEVOPS_POOL_ROOT}/build/${USER}}"
DEVOPS_CACHE_HOME="${DEVOPS_CACHE_HOME:-${DEVOPS_POOL_ROOT}/cache/${USER}}"
DEVOPS_DB_HOME="${DEVOPS_DB_HOME:-${DEVOPS_POOL_ROOT}/db/${USER}}"

for devops_dir in "$DEVOPS_BUILD_HOME" "$DEVOPS_CACHE_HOME" "$DEVOPS_DB_HOME"; do
  [ -d "$devops_dir" ] || mkdir -p "$devops_dir" 2>/dev/null || true
done
unset devops_dir

export DEVOPS_POOL_ROOT DEVOPS_BUILD_HOME DEVOPS_CACHE_HOME DEVOPS_DB_HOME

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${DEVOPS_CACHE_HOME}/xdg}"
export CARGO_HOME="${CARGO_HOME:-${DEVOPS_CACHE_HOME}/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-${DEVOPS_CACHE_HOME}/rustup}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${DEVOPS_BUILD_HOME}/cargo-target}"
export SCCACHE_DIR="${SCCACHE_DIR:-${DEVOPS_CACHE_HOME}/sccache}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${DEVOPS_CACHE_HOME}/pip}"
export PIPX_HOME="${PIPX_HOME:-${DEVOPS_DB_HOME}/pipx}"
if [ -n "${HOME:-}" ]; then
  export PIPX_BIN_DIR="${PIPX_BIN_DIR:-${HOME}/.local/bin}"
fi
export PRE_COMMIT_HOME="${PRE_COMMIT_HOME:-${DEVOPS_CACHE_HOME}/pre-commit}"
export MYPY_CACHE_DIR="${MYPY_CACHE_DIR:-${DEVOPS_CACHE_HOME}/mypy}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${DEVOPS_CACHE_HOME}/npm}"
export GOPATH="${GOPATH:-${DEVOPS_BUILD_HOME}/go}"
export GOCACHE="${GOCACHE:-${DEVOPS_CACHE_HOME}/go-build}"
export GOMODCACHE="${GOMODCACHE:-${DEVOPS_CACHE_HOME}/go-mod}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-${DEVOPS_CACHE_HOME}/gradle}"
export ANSIBLE_HOME="${ANSIBLE_HOME:-${DEVOPS_DB_HOME}/ansible}"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${DEVOPS_CACHE_HOME}/ansible/tmp}"
export CCACHE_DIR="${CCACHE_DIR:-${DEVOPS_CACHE_HOME}/ccache}"

if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER="${RUSTC_WRAPPER:-sccache}"
fi

unset -f devops_storage_return
