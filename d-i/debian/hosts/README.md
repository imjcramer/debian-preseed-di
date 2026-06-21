The host env contract is split into concrete profiles plus shared policy:

- `hosts/profiles/<family>/<role>.env`
- `hosts/shared/identity.env`
- `hosts/shared/account.env`
- `hosts/shared/runtime.env`
- `hosts/shared/<role>.env` (`desktop.env` or `server.env`)
- `hosts/shared/layout.env`
- `hosts/shared/layout-btrfs.env` or `hosts/shared/layout-f2fs.env`
- `hosts/shared/boot.env`
- optional service overrides under `hosts/services/<service>/<role>.env`

The loader assembles the concrete host policy env in this order:

1. `hosts/profiles/<family>/<role>.env`
2. `hosts/shared/identity.env`
3. `hosts/shared/runtime.env`
4. `hosts/shared/<role>.env`
5. `hosts/shared/layout.env`
6. `hosts/shared/layout-<storage-family>.env`
7. `hosts/shared/boot.env`
8. selected `hosts/services/<service>/<role>.env`

Account policy is loaded separately from `hosts/shared/account.env`.

When the optional `service` class group is selected, the matching service env
is appended after the shared host policy so service-owned host settings take
precedence. The resolver first tries a service directory that matches the
selected class name and also accepts `*-runner` classes mapping to
`hosts/services/<prefix>/`.

The concrete profile loads first because shared env files derive tmpfs, zram,
device, GRUB, desktop or server addon policy, sysctl, and installed static
networking policy from the role-specific `SIZE_*`, `BOOTPROFILE_*`, `GRUB_*`,
`IPV4_*`, `IPV6_*`, `WIFI_*`, `NFTABLES_LOG_LEVEL`, `ZRAM_LOG_LEVEL`,
`SYSTEMD_LOG_LEVEL`, and slot values owned by the selected profile.
`hosts/shared/layout.env` carries only cross-family mount primitives and
tmpfs/dm-crypt backing policy; `layout-btrfs.env` and `layout-f2fs.env` own
their layout labels, mount, mkfs, formatter sizing, and GRUB root policy.
In the F2FS family, `/pool` remains ext4 and therefore uses `MNT_EXT4_POOL_OPTS`.
Keep `IPV4_STATIC_RANGE` and `IPV6_STATIC_RANGE` non-overlapping across every
concrete profile because late command selects host addresses from those pools.
Installed-system log defaults are intentionally sparse: nftables defaults to
`none`, while zram and systemd/network helpers default to `error`.
`NFTABLES_LOG_LEVEL` controls generator diagnostic output only; packet logging
is controlled by nftables profile or service overlay `logging.*.enabled`
fields, not by log level.
`NFTABLES_LOG_LEVEL`, `ZRAM_LOG_LEVEL`, and `SYSTEMD_LOG_LEVEL` accept
`none|error|warning|info|debug`.
These installed-system log levels are independent from the selected `debug`
installer class, which only controls d-i installation log capture.

The selected installer classes remain authoritative:

- `disk=nvme` selects `hosts/profiles/btrfs/<desktop|server>.env` for the generic bare-metal Btrfs/XFS baseline.
- `disk=vm` selects `hosts/profiles/vm/<desktop|server>.env`.
- `disk=emmc` selects `hosts/profiles/f2fs/<desktop|server>.env`.

The `disk` class is auto-detected unless it is explicitly supplied in
`classes=`.

Current family intent:

- `profiles/btrfs/desktop.env` uses the desktop Btrfs/XFS size floors and targets.
- `profiles/btrfs/server.env` keeps the same slot contract but reserves a larger `/pool`.
- `profiles/f2fs/desktop.env` keeps a dedicated `/home` partition and can insert a dedicated encrypted `/var/lib/shim-signed` partition when `SECURE_BOOT_STATE_MODE=luks`.
- `profiles/f2fs/server.env` keeps `/home` on the root filesystem, does not allocate a separate home partition, and can insert the same encrypted Secure Boot state partition when `SECURE_BOOT_STATE_MODE=luks`.
- `profiles/vm/desktop.env` keeps the Btrfs/XFS storage contract for virtual machines.
- `profiles/vm/server.env` uses the same guest storage family with guest-oriented GRUB and module policy.

Storage sysctl layering:

- `hooks/shared/target/etc/sysctl.d/10-*.conf` and `20-*.conf` stay common across every host.
- `hosts/shared/runtime.env` owns the shared `FILE_SYSCTL_*` target paths.
- `hooks/shared/target/etc/sysctl.d/25-storage-static.conf.tmpl` renders storage overrides from the assembled host policy env.
- `hooks/shared/target/etc/sysctl.d/profiles/*/40-*.conf` remains the shared bootprofile baseline.
- `hooks/shared/target/etc/sysctl.d/profiles/*/50-storage-*.conf.tmpl` renders disk and role-specific bootprofile overlays that `bootprofile-apply` syncs into `/run/sysctl.d`.
