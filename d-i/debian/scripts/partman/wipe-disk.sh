#!/bin/sh
set -eu

fatal() {
  printf '[wipe-disk] fatal: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '[wipe-disk] usage: %s <disk>\n' "${0##*/}" >&2
  exit 1
}

disk=${1:-}
[ -n "$disk" ] || usage
[ -b "$disk" ] || fatal "disk is not a block device: ${disk}"

if command -v wipefs >/dev/null 2>&1; then
  wipefs -a -f "$disk"
fi
