#!/bin/sh
# Shared late_command target asset and template helper utilities. This file is sourced, not executed.

module_value_to_lines() {
  value=${1:-}
  if [ -n "$value" ]; then
    printf '%s\n' "$value" | tr ' ' '\n'
  else
    printf '\n'
  fi
}

target_asset_host_path() {
  target_path=$1

  case "$target_path" in
    /target|/target/*)
      printf '%s\n' "$target_path"
      ;;
    /*)
      printf '/target%s\n' "$target_path"
      ;;
    *)
      installer_fatal "target asset path must be absolute: ${target_path}"
      ;;
  esac
}

ensure_target_asset_parent() {
  target_path=$1
  target_host_path=$(target_asset_host_path "$target_path")
  target_parent=$(dirname "$target_host_path")

  [ -d "$target_parent" ] || install -d -m 0755 "$target_parent"
}

target_asset_contains_installer_placeholders() {
  asset_path=$1

  [ -r "$asset_path" ] || return 1
  LC_ALL=C grep -q '__INSTALLER_' "$asset_path"
}

target_asset_assert_no_unresolved_installer_placeholders() {
  asset_path=$1
  asset_label=${2:-$asset_path}

  target_asset_contains_installer_placeholders "$asset_path" || return 0

  unresolved_tokens=$(
    LC_ALL=C grep -o '__INSTALLER_[A-Z0-9_]\+__' "$asset_path" 2>/dev/null |
      sort -u |
      tr '\n' ' '
  )
  unresolved_tokens=${unresolved_tokens%" "}
  [ -n "$unresolved_tokens" ] || unresolved_tokens="unknown placeholder(s)"
  installer_fatal "${asset_label} has unresolved installer placeholders: ${unresolved_tokens}"
}

stage_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  tmp_asset="${TMP_ENV_DIR}/asset.$$.tmp"

  fetch_hook "$repo_path" "$tmp_asset"
  ensure_target_asset_parent "$target_path"
  install -m "$mode" "$tmp_asset" "/target${target_path}"
  rm -f "$tmp_asset"
}

remove_target_asset() {
  target_path=$1
  rm -f "$(target_asset_host_path "$target_path")"
}

render_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  tmp_asset="${TMP_ENV_DIR}/asset.$$.tmp"

  fetch_hook "$repo_path" "$tmp_asset"
  ensure_target_asset_parent "$target_path"
  render_target_template "$tmp_asset" "/target${target_path}" "$mode"
  rm -f "$tmp_asset"
}

render_target_asset_with_placeholder_map() {
  repo_path=$1
  target_path=$2
  mode=$3
  map_func=$4

  stage_target_asset "$repo_path" "$target_path" "$mode"
  apply_placeholder_map_to_target "/target${target_path}" "$map_func"
}

render_target_asset_if_path() {
  repo_path=$1
  target_path=$2
  fallback_path=$3
  mode=$4

  if [ -n "$target_path" ]; then
    render_target_asset "$repo_path" "$target_path" "$mode"
  else
    remove_target_asset "$fallback_path"
  fi
}

stage_target_asset_if_path() {
  repo_path=$1
  target_path=$2
  fallback_path=$3
  mode=$4

  if [ -n "$target_path" ]; then
    stage_target_asset "$repo_path" "$target_path" "$mode"
  else
    remove_target_asset "$fallback_path"
  fi
}

stage_target_docs_index() {
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET data/docs/README.md)" "${DIR_DATA_DOCS}/README.md" 0644
  target_chown_helper_doc_path "${DIR_DATA_DOCS}/README.md"
}

target_helper_doc_owner_ids() {
  if [ -n "${TARGET_HELPER_DOC_OWNER_IDS:-}" ]; then
    printf '%s\n' "$TARGET_HELPER_DOC_OWNER_IDS"
    return 0
  fi

  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set before staging helper docs}"
  helper_doc_owner_ids=$(awk -F: -v wanted_user="$ACCOUNT_USERNAME" '$1 == wanted_user { print $3 ":" $4; exit }' /target/etc/passwd)
  [ -n "$helper_doc_owner_ids" ] || installer_fatal "target helper doc owner is missing from /target/etc/passwd: ${ACCOUNT_USERNAME}"
  TARGET_HELPER_DOC_OWNER_IDS=$helper_doc_owner_ids
  printf '%s\n' "$TARGET_HELPER_DOC_OWNER_IDS"
}

target_chown_helper_doc_path() {
  doc_target_path=$1
  helper_doc_owner_ids=$(target_helper_doc_owner_ids)
  doc_host_path=$(target_asset_host_path "$doc_target_path")

  chown "$helper_doc_owner_ids" "$doc_host_path"
}

stage_target_helper_doc() {
  repo_relpath=$1
  doc_name=$2

  [ -n "${DIR_DATA_DOCS:-}" ] || installer_fatal "DIR_DATA_DOCS must be set before staging helper docs"
  stage_target_docs_index
  doc_target_path="${DIR_DATA_DOCS}/${doc_name}"
  stage_target_asset "$(installer_repo_join_var DIR_HOOKS_SHARED_TARGET "data/docs/${repo_relpath}")" "${doc_target_path}" 0644
  target_chown_helper_doc_path "$doc_target_path"
}

remove_target_asset_and_empty_parent() {
  target_path=$1
  target_host_path=$(target_asset_host_path "$target_path")
  target_parent=$(dirname "$target_host_path")

  rm -f "$target_host_path"
  rmdir "$target_parent" 2>/dev/null || true
}

sysctl_profile_placeholder_map() {
  profiles="BALANCED HARDENED PERFORMANCE"
  keys="SWAPPINESS PAGE_CLUSTER VFS_CACHE_PRESSURE WATERMARK_BOOST_FACTOR WATERMARK_SCALE_FACTOR COMPACTION_PROACTIVENESS EXTFRAG_THRESHOLD DIRTY_BACKGROUND_BYTES DIRTY_BYTES DIRTY_EXPIRE_CENTISECS DIRTY_WRITEBACK_CENTISECS DIRTYTIME_EXPIRE_SECONDS STAT_INTERVAL ZONE_RECLAIM_MODE AIO_MAX_NR INOTIFY_MAX_USER_INSTANCES INOTIFY_MAX_USER_WATCHES INOTIFY_MAX_QUEUED_EVENTS SOMAXCONN NETDEV_MAX_BACKLOG TCP_MAX_SYN_BACKLOG TCP_FASTOPEN TCP_KEEPALIVE_TIME TCP_FIN_TIMEOUT"

  for profile in $profiles; do
    for key in $keys; do
      var="SYSCTL_PROFILE_${profile}_${key}"
      eval "value=\${$var-}"
      [ -n "$value" ] || installer_fatal "${var} must be set"
      case "$value" in
        *[!0123456789]*)
          installer_fatal "${var} must be a non-negative integer"
          ;;
      esac
      printf '%s=%s\n' "$var" "$value"
    done
  done
}

apply_placeholder_map_to_target() {
  target_path=$1
  map_func=$2
  rendered_tmp="${target_path}.map.$$"
  map_tmp="${TMP_ENV_DIR}/target-placeholder-map.$$.tmp"

  set --
  if ! "$map_func" >"$map_tmp"; then
    rm -f "$map_tmp"
    installer_fatal "failed to render placeholder map ${map_func} for ${target_path}"
  fi
  while IFS= read -r map_line || [ -n "$map_line" ]; do
    map_name=${map_line%%=*}
    map_value=${map_line#*=}
    [ -n "$map_name" ] || continue
    set -- "$@" "$map_name" "$map_value"
  done <"$map_tmp"
  rm -f "$map_tmp"
  installer_apply_scalar_placeholders "$target_path" "$rendered_tmp" "$@" || {
    rm -f "$map_tmp"
    rm -f "$rendered_tmp"
    installer_fatal "failed to apply placeholder map ${map_func} to ${target_path}"
  }
  mv "$rendered_tmp" "$target_path"
}

replace_placeholder_line_block() {
  target_path=$1
  placeholder=$2
  replacement=$3
  rendered_tmp="${target_path}.line.$$"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$placeholder" ]; then
      [ -n "$replacement" ] && printf '%s\n' "$replacement"
      continue
    fi
    printf '%s\n' "$line"
  done <"$target_path" >"$rendered_tmp"
  mv "$rendered_tmp" "$target_path"
}

apply_sysctl_profile_placeholders() {
  target_path=$1
  apply_placeholder_map_to_target "$target_path" sysctl_profile_placeholder_map
}
