#!/bin/sh
set -eu

target_root=${1:-/target}
[ -d "$target_root" ] || exit 0

stage_unit_enablement() {
  unit=$1
  for unit_dir in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
    if [ -e "${target_root}${unit_dir}/${unit}" ]; then
      install -d -m 0755 "${target_root}/etc/systemd/system/multi-user.target.wants"
      ln -sf "${unit_dir}/${unit}" "${target_root}/etc/systemd/system/multi-user.target.wants/${unit}"
      return 0
    fi
  done
}

stage_unit_enablement nginx.service
