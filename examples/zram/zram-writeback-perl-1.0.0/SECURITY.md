# Security notes

## Data at rest

zram writeback can persist swapped memory to the configured backing device. That memory may contain credentials, private keys, tokens, browser session data, database pages or application secrets.

Use a dedicated dm-crypt/LUKS mapping for `backing_dev` when confidentiality matters. Do not use an unencrypted raw partition on laptops, developer workstations, multi-tenant systems or hosts that process secrets.

## Least privilege and isolation

The systemd units run as root because zram sysfs and swap control require elevated privileges. The long-running daemon unit enables conservative hardening where it does not break sysfs operation:

- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectHome=yes`
- `ProtectControlGroups=yes`
- `MemoryDenyWriteExecute=yes`
- `RestrictRealtime=yes`
- `RestrictAddressFamilies=AF_UNIX`

Do not enable `ProtectKernelTunables=yes` for this service; the daemon must write kernel sysfs knobs under `/sys/block/zramX`.

## Abuse resistance

The implementation includes:

- explicit configuration validation,
- placeholder backing device rejection,
- writeback budget enforcement,
- per-device lock serialization,
- EAGAIN retry limits,
- safe default refusal to reset an initialized zram device,
- no shell interpolation for sysfs writes.

## Operational risks

- Aggressive writeback can burn flash endurance. Keep `daily_budget_mib` conservative.
- Aggressive `zstd` passes can increase latency. Tune `max_pages_*` from PSI and workload behavior.
- `CONFIG_ZRAM_MEMORY_TRACKING` exposes detailed page state through debugfs. Treat debugfs as privileged diagnostic surface.
