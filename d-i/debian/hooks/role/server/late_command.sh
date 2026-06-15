#!/bin/sh
set -eu

printf '[late:role:server] seed=%s host=%s\n' "${1:-}" "${2:-}" >&2
