# zram-writeback-perl

Production-oriented Perl implementation for Debian Trixie and XanMod/Linux kernels with zram multi-compression, idle tracking, recompression, writeback budgets and PSI-driven policy decisions.

## Policy summary

The shipped policy uses:

| Tier | Algorithm | zram role | Target |
|---:|---|---|---|
| 0 | `lz4` | primary compressor | all hot/new swap pages |
| 1 | `lzo-rle` | secondary priority 1 | idle pages likely to be reused |
| 2 | `zstd` | secondary priority 2 | huge idle pages |
| 3 | `zstd` | secondary priority 3 | huge non-idle pages under pressure, with lower `max_pages` |

Writeback is deliberately conservative:

1. Normal: mark idle, recompress idle/huge_idle, compact, no writeback.
2. Pressure: recompress idle/huge_idle/limited huge, compact, write back incompressible pages if budget allows.
3. Emergency: run larger recompress passes, then write back incompressible and huge_idle pages if budget allows.
4. Budget exhausted: recompress/compact only; leave pages in zram.

## Contents

```text
sbin/zram-writeback                 CLI/daemon entry point
lib/Zram/Writeback/*.pm             Perl modules
etc/zram-writeback.conf             Main policy configuration
etc/default/zram-writeback          systemd environment defaults
systemd/*.service *.timer           setup, daemon, one-shot pass and budget units
modules-load.d/zram-writeback.conf  Load zram at boot
modprobe.d/zram-writeback.conf      zram num_devices default
tmpfiles.d/zram-writeback.conf      Runtime/state directory creation
man/zram-writeback.8                Manual page
docs/kernel-config.md               Kernel CONFIG checklist
docs/policy.md                      Policy details and tuning notes
t/*.t                               Unit tests
install.sh / uninstall.sh           Direct Debian install helpers
debian/                             Debian packaging skeleton
```

## Dependencies

Runtime dependencies are intentionally minimal:

- Perl from Debian base system.
- Core Perl modules only: `Getopt::Long`, `JSON::PP`, `Fcntl`, `POSIX`, `Time::HiRes`, `FindBin`, `Test::More` for tests.
- `systemd`, `mkswap`, `swapon`, `swapoff`, `modprobe`.
- Kernel support for zram, multi-comp recompression, idle tracking and writeback.

No CPAN modules are required.

## Required kernel features

At minimum:

```text
CONFIG_SWAP=y
CONFIG_ZRAM=m or y
CONFIG_ZSMALLOC=y
CONFIG_ZRAM_BACKEND_LZ4=y
CONFIG_ZRAM_BACKEND_LZO=y
CONFIG_ZRAM_BACKEND_ZSTD=y
CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_WRITEBACK=y
CONFIG_ZRAM_TRACK_ENTRY_ACTIME=y
CONFIG_PSI=y
```

Recommended diagnostics:

```text
CONFIG_DEBUG_FS=y
CONFIG_ZRAM_MEMORY_TRACKING=y
CONFIG_ZSMALLOC_STAT=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
```

See `docs/kernel-config.md` for the full list.

## Installation

```sh
sudo ./install.sh
sudo editor /etc/zram-writeback.conf
sudo zram-writeback validate --config /etc/zram-writeback.conf
```

Before enabling setup, replace:

```ini
backing_dev = /dev/disk/by-partuuid/REPLACE_WITH_DEDICATED_ENCRYPTED_ZRAM_WRITEBACK_PARTITION
```

with a real dedicated partition. Use dm-crypt/LUKS if the host can swap secrets.

Enable either the daemon or the timer-based one-shot pass. Do not enable both unless you intentionally want both schedulers.

Daemon mode:

```sh
sudo systemctl enable --now zram-writeback-setup.service
sudo systemctl enable --now zram-writebackd.service
sudo systemctl enable --now zram-writeback-budget.timer
```

Timer mode:

```sh
sudo systemctl enable --now zram-writeback-setup.service
sudo systemctl enable --now zram-writeback-pass.timer
sudo systemctl enable --now zram-writeback-budget.timer
```

## CLI

```sh
zram-writeback validate --config /etc/zram-writeback.conf
zram-writeback setup --config /etc/zram-writeback.conf
zram-writeback setup --config /etc/zram-writeback.conf --force-reset
zram-writeback run-pass --config /etc/zram-writeback.conf
zram-writeback run-pass --config /etc/zram-writeback.conf --state emergency
zram-writeback budget-reset --config /etc/zram-writeback.conf
zram-writeback status --config /etc/zram-writeback.conf
zram-writeback daemon --config /etc/zram-writeback.conf --interval 60
```

## Testing

```sh
make test
```

The tests avoid touching real `/sys` zram attributes.

## Operational notes

- `setup` configures `comp_algorithm`, `backing_dev`, `compressed_writeback`, `writeback_batch_size`, recompression algorithms, algorithm parameters and writeback budget before `disksize`.
- `setup` refuses to reset an initialized device unless `--force-reset` is passed or `reset_if_initialized=true` is set.
- The daemon serializes operations using `/run/lock/zram-writeback-zram0.lock`.
- Sysfs writes are performed with `syswrite`, not shell redirection.
- `EAGAIN` is retried because recompress and writeback can temporarily collide in the kernel.
- `algorithm_params` failures default to warnings because algorithm parameter support is kernel/algorithm-specific.

## Security model

- The daemon must run as root because it writes zram sysfs attributes and may run `mkswap`/`swapon` during setup.
- Backing storage can contain swapped memory. Use a dedicated encrypted block device.
- Do not share the writeback backing partition with a filesystem.
- Keep debugfs unmounted or restricted unless `block_state` diagnostics are needed.
- Avoid enabling zswap in front of this zram-first policy unless you have measured a benefit.
