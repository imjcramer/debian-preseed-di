# AGENTS.override.md

This override applies to this repository root and all child paths.

## mcr/main scope extension
- On `mcr/main`, edits are additionally allowed for the managed APT policy asset flow:
  - `d-i/debian/hooks/shared/target/etc/apt/apt.conf.d/**`
  - `d-i/debian/scripts/late/storage-maintenance.sh`
  - `t/late-policy-smoke.sh`

## APT policy contract
- Keep unattended-upgrades policy in `52unattended-upgrades`.
- Keep generic APT transport behavior in a dedicated snippet under `etc/apt/apt.conf.d/`.
- When disabling pdiffs, use `Acquire::PDiffs "false";` in its own managed snippet instead of adding it to an `Unattended-Upgrade::*` policy file.
