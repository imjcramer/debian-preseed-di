# Debian LAN Installer

This repository is a stripped LAN-hosted Debian 13 installer bundle for automated bare-metal installs. It keeps only the install path needed for installation delivery, runtime partition rendering, storage layout, target fstab rendering, class-selected kernel packages, first-boot storage services, and GRUB profile generation.

- `Balanced`: daily-driver default with security and performance kept in balance.
- `Hardened`: stricter logging, auditing, and runtime restrictions.
- `Performance`: higher-throughput tuning without dropping core security controls.

## Storage Contract

The installer builds a mixed Btrfs, XFS, ext4, LUKS-on-ext4, vfat, tmpfs, and zram layout.

- `/` is Btrfs and uses these subvolumes: `@`, `@root`, `@srv`, `@usr_local`, `@var_spool`.
- `/home` is Btrfs and uses these subvolumes: `@home`, `@home_downloads`, `@home_public`, `@home_pictures`, `@home_workspace`.
- `/opt` is a dedicated Btrfs filesystem with the `@opt` subvolume.
- `/data` is a dedicated XFS filesystem mounted once at the top level.
- `/data/run` is a `100 MiB` tmpfs mounted below `/data`; `/etc/tmpfiles.d/20-data-run.conf` recreates `/run/media/<account>` and rewires `/data/run/mnt` to that path as a symlink at boot.
- `/pool` is a dedicated XFS filesystem mounted once at the top level.
- `/var/tmp` and `/var/log/journal` are dedicated ext4 filesystems.
- `/var/lib/shim-signed` is a dedicated `100 MiB` LUKS2-encrypted ext4 filesystem for Secure Boot state on Btrfs/VM profiles and on F2FS/eMMC profiles when `SECURE_BOOT_STATE_MODE=luks`; it is mounted during installation, intentionally omitted from `fstab`, and reopened on demand with the shipped `luks-mok-*` helpers. F2FS/eMMC profiles keep the historical direct-on-root state path when `SECURE_BOOT_STATE_MODE=direct`.
- the last two Debian-owned partitions are left raw and unformatted: slot `11` is opened at boot as the ephemeral plain-dm-crypt mapper `/dev/mapper/swap-fallback` and activated directly as the lower-priority fallback swap partition; slot `12` is opened at boot as `/dev/mapper/zram-writeback` for zram writeback.
- `/data/run`, `/var/log`, `/var/cache`, `/var/lib/apt/lists`, `/var/lib/systemd/coredump`, `/tmp`, and `/dev/shm` are tmpfs mounts.
- `/var/log/journal` stays persistent below the tmpfs-mounted `/var/log`.
- `/var/log` no longer has a dedicated partition.
- `zram0` is enabled from first boot through custom helper and systemd units, and its active size is derived on the target from the configured RAM percentage plus the encrypted writeback mapper capacity.
- the fallback swap partition size is derived from live RAM during installation, then clamped to the dedicated raw swap-partition floor and activated at priority `10` through `/dev/mapper/swap-fallback`.

The storage layout is rendered from the selected concrete profile under `d-i/debian/hosts/profiles/<family>/<role>.env`, shared policy under `d-i/debian/hosts/shared/*.env`, and the filesystem-family runtime helpers under `d-i/debian/scripts/runtime/{btrfs,f2fs}.sh`. When the selected profile resolves `SECURE_BOOT_STATE_MODE=luks`, the partman recipe declares `/var/lib/shim-signed` directly as an encrypted ext4 partition, seeded through `partman-crypto` so the whole partition is LUKS2-encrypted during partitioning, while the target-side `crypttab` auto-open entry is removed later so the filesystem still stays manual-only after installation. The Btrfs tiers are still reformatted by the finish hook with the explicit `crc32c` checksum profile, and that hook explicitly preloads the Btrfs/hash helpers before the first Btrfs staging mount. The partman finish hook writes tmpfs entries only to the installed target fstab; the installer-facing partman fstab cache deliberately omits tmpfs entries so d-i does not mount volatile tmpfs paths during installation. Late command then cleans the profile-enabled volatile backing paths as its final step before handoff to first boot. On the installed system, `/data/run` is mounted from fstab with `x-systemd.requires-mounts-for=/data` and a fixed `size=100M`, while the other tmpfs mounts use percentage-based `size=%` options. The volatile-directory preparation unit still runs in `sysinit` before `systemd-tmpfiles-setup.service` so `/var/log`, `/var/cache`, and `/var/lib/apt/lists` are already mounted when tmpfiles starts creating boot-time state; `20-data-run.conf` then recreates `/run/media/<account>` and replaces `/data/run/mnt` with a symlink to that private media path.

## Serve It On The LAN

From the repository root, serve the tree over HTTP:

```bash
python3 -m http.server 8080
```

The installer must be able to reach:

```text
http://<lan-host>:8080/d-i/debian/preseed.cfg
```

## Boot The Debian Installer

Boot the Debian installer in expert or advanced mode and append the installation URL plus the early locale answers on the kernel command line:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8080/d-i/debian/preseed.cfg
```

Use `auto=true` literally, not just `auto`. Debian Installer asks localization questions extremely early; `auto=true` is what delays them until after network answer-file automation is available, and the explicit `locale`/`language`/`country` boot parameters provide a second, early-safe answer path.

The served seed base is the containing `d-i/debian/` directory, not the repo
root. With `url=http://<lan-host>:8080/d-i/debian/preseed.cfg`, the runtime
normalizes that to `http://<lan-host>:8080/d-i/debian`; with
`file=/media/usb/d-i/debian/preseed.cfg`, it normalizes to
`/media/usb/d-i/debian`. It then fetches sibling phase entrypoints such as
`scripts/preseed/answers.sh`, `scripts/early/dispatch.sh`,
`scripts/partman/dispatch.sh`, and `scripts/late/dispatch.sh` below that tree
through the shared bootstrap helper.

The class-group contract is defined by `d-i/debian/classes/CLASSES.conf`. Most groups allow at most one selected class; `gpu` and `addon` may select multiple classes. The installer auto-detects `arch`, `cpu`, `gpu`, and `disk` classes through `d-i/debian/scripts/preseed/class-auto.sh` and appends them to the manual `classes=` value. A manual class from an auto group overrides detection for that group. NVIDIA is intentionally not auto-selected; add the `nvidia` addon class when the proprietary NVIDIA stack should be installed on hosts with detected NVIDIA display hardware.

Manual `class-select` groups are:

- `site`: `prod`, `lab`, `dmz`
- `role`: `desktop`, `server`
- `security`: `standard`, `enhanced`
- `network`: `dhcp`, `static`

Auto `class-auto` groups are:

- `arch`: `amd64`, `arm64`
- `cpu`: `intel`, `amd`
- `gpu`: `intel-uhd`, `amd-radeon`, `generic`
- `disk`: `nvme` (generic bare-metal Btrfs/XFS baseline), `emmc`, `vm`

The current optional manual groups are:

- `service`: `web`, `db`, `gitlab-runner`
- `debug`: `debug`
- `addon`: direct `d-i/debian/classes/class-addon/<name>.cfg` files, including `devops`, `forky`, `nvidia`, `podman`, `ssh`, `timeshift`, and `wifi`

Bare class tokens are resolved across the manifest-declared classes, so the normal compact form is still:

Example:

```text
classes=lab,desktop,standard,dhcp primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

That means:

- Adding a manifest-declared class gives you bare-token resolution and optional metadata such as helpers, dependencies, and storage dispatch.
- Adding an additive class does not require dispatcher/code changes: add `d-i/debian/classes/class-addon/<name>.cfg` and select it as `<name>` in `classes=`.
- Adding a select class group uses `d-i/debian/classes/class-select/<group>/<class>.cfg` and `group/class` in `classes=`.
- Group-qualified tokens also accept `group:class` and `group.class`; prefer `group/class` in manual references and use commas between selected classes on the kernel cmdline because that survives more bootloaders cleanly than semicolons.
- Adding new host/storage behavior should be declared in `d-i/debian/classes/CLASSES.conf`, not inline inside the class fragment.
- The optional `debug` class does nothing unless you explicitly include `debug` in `classes=`. When selected, it enables installer-side stage/category logging and archives `/tmp/preseed-logs/` into `/var/lib/preseed/logs/installer/` on the target.

Every install derives the primary account name, primary account password, and
root password from `primary_user=`, `primary_password=`, and `root_password=`
on the installer kernel command line. These values must be single printable
tokens without whitespace; `primary_user` must match the Debian account-name
shape `^[a-z_][a-z0-9_-]*$`. Desktop installs also stage the
vdirsyncer/khal/todoman calendar stack for the primary account, so
`classes=...,desktop,...` requires
`fruux_username=<fruux-user>` and `fruux_password=<fruux-app-password>` on the
installer kernel command line. These values must be single printable tokens
without whitespace. They are redacted from the repo's own installer logs, but
kernel command-line values are still visible to the bootloader and installer
runtime, so use deployment-specific account secrets and a scoped Fruux app
password.

To use ordinary wired DHCP networking, select the `dhcp` network class without
the `wifi` addon:

```text
classes=lab,desktop,standard,dhcp primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

The installer still lets d-i use automatic `netcfg` selection for DHCP installs.
DHCP targets do not receive the `preseed-network` helper or service.

To use static IPv4/IPv6 networking, select the `static` network class. The
`netcfg/get_*` kernel parameters remain installer-time answers only; the
installed system is configured during `late_command` from
the selected `d-i/debian/hosts/profiles/<family>/<role>.env`.

```text
classes=lab,desktop,standard,static primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password> netcfg/get_domain=example.test netcfg/get_ipaddress=192.0.2.50 netcfg/get_netmask=255.255.255.0 netcfg/get_gateway=192.0.2.1 netcfg/get_nameservers=192.0.2.53
```

`d-i/debian/classes/class-select/network/static.cfg` forces manual/static
netcfg mode, and `d-i/debian/scripts/preseed/answers.sh` appends the concrete
`netcfg/get_domain`, `netcfg/get_ipaddress`, `netcfg/get_netmask`,
`netcfg/get_gateway`, and `netcfg/get_nameservers` values after class fragments
so cmdline-derived answers win for d-i itself. The installed target does not
reuse those static IPv4 values. Instead,
`d-i/debian/scripts/late/preseed-network-generate.pl` selects unused addresses
from `IPV4_STATIC_RANGE` and `IPV6_STATIC_RANGE`, writes
`/etc/network/interfaces`, `/etc/network/interfaces.d/50-preseed-network`, and
root-only `/etc/default/preseed-network`, then stages MAC-matched
`/etc/systemd/network/10-preseed-ethernet.link` and
`/etc/systemd/network/11-preseed-wifi.link` when applicable. It also writes a
NetworkManager keyfile unmanaged rule that matches both the deterministic
`preeth0`/`prewifi0` names and the detected MAC addresses, and late command
stages NetworkManager's dispatcher D-Bus activation alias when the vendor unit
is installed so dbus-broker can activate `org.freedesktop.nm_dispatcher` after
reboots. For example,
`IPV4_STATIC_RANGE="192.168.50.133/28"` is treated as a 16-address host-start
pool (`192.168.50.133` through `192.168.50.148`), while
`IPV4_CIDR="24"` renders the chosen address as `/24` with netmask
`255.255.255.0`.

Static installs stage `preseed-network.service` as a oneshot validation gate.
At boot it does not rewrite networking. It validates the generated ifupdown
files, root-only defaults, adapter MACs, IPv4/IPv6 CIDRs, and Wi-Fi security
stanzas before `networking.service`, `NetworkManager.service`, or
`systemd-networkd.service` can continue.

To use WPA Wi-Fi with static IPv4/IPv6 target networking, add the `wifi`
addon class. The installed system only receives a Wi-Fi stanza when this addon
is selected.

```text
classes=lab,desktop,standard,static,wifi primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password> netcfg/wireless_essid=ExampleSSID netcfg/wireless_essid_again=ExampleSSID netcfg/wireless_security_type=wpa netcfg/wireless_wpa=<wpa-psk> netcfg/get_domain=example.test netcfg/get_ipaddress=192.0.2.50 netcfg/get_netmask=255.255.255.0 netcfg/get_gateway=192.0.2.1 netcfg/get_nameservers=192.0.2.53
```

`netcfg/wireless_security_type` is used only for d-i netcfg compatibility; the
installed Wi-Fi stanza uses `WIFI_PSK_SECURITY` from
the selected `d-i/debian/hosts/profiles/<family>/<role>.env` (`sae` by
default). If `netcfg/wireless_wpa` is left empty, the tracked `wifi.cfg`
keeps the WPA passphrase question unseen so d-i can still ask for it or a
private deployment overlay can seed it without committing a secret. Prefer that
overlay path for production networks because kernel command-line values are
visible through the bootloader and installer runtime even though this repo
redacts the accepted WPA key names from its own diagnostic logs. Static Wi-Fi
target networking requires `ifupdown` and `wpasupplicant`, which are included
explicitly because this profile disables package recommends; `ethtool` is also
included so the late-command generated ifupdown stanzas can apply best-effort
adapter offload and queue settings.

When `wifi` is selected without `network/static`, the installed target receives
only the generated static Wi-Fi IPv4/IPv6 stanzas. When both `static` and
`wifi` are selected, late command generates two IPv4 addresses and two IPv6
addresses from the selected profile pools: one pair for `preeth0` and one pair
for `prewifi0`.

To install and enable a hardened OpenSSH server during `late_command`, add the
`ssh` addon class:

```text
classes=lab,desktop,standard,dhcp,ssh primary_user=<user> primary_password=<user-password> root_password=<root-password> ssh_port=<port> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled, `d-i/debian/classes/class-addon/ssh.cfg` adds
`openssh-server` to the selected package set. The shared late-command path then
validates and renders `d-i/debian/ssh/sshd_config`, installs
`d-i/debian/ssh/config` as the target user's `~/.ssh/config`, and writes
`d-i/debian/ssh/lan_ed25519.pub` into that user's `~/.ssh/authorized_keys`. The
target user, home path, `AllowUsers`, and `Port` are rendered from
`primary_user=` and `ssh_port=` on the kernel command line; SSH login is
limited to that user, root/password/keyboard-interactive auth are
disabled, and the shipped configs restrict public-key, host-key, KEX, cipher,
and MAC algorithms to the hardened Ed25519/Curve25519/AEAD/ETM set. When the
`ssh` addon is selected and nftables staging is enabled, the installer also
merges the `ssh-server` firewall overlay so inbound SSH is allowed on that
rendered port from the managed IPv4 and IPv6 network CIDRs for the selected
host profile and first-boot network handoff.

The `server` and `desktop` roles also install `openssh-client` and stage two
transfer helpers:

```sh
xssh-send --dest-ip <ip address> --port <ssh port> [--user <remote-user>] <local-path> [remote-path]
xssh-retrieve --remote-ip <ip address> --port <ssh port> [--user <remote-user>] <remote-path> [local-path]
```

Both helpers use recursive `scp`, work with files or directories, and print an
explicit completion line on success.

To install the development and CI toolchain and route interactive build/cache
state to `/pool`, add the `devops` addon class:

```text
classes=lab,desktop,standard,dhcp,devops primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled, `d-i/debian/classes/class-addon/devops.cfg` adds the development
package set, and the class late helper stages `/etc/profile.d/70-devops-storage.sh`
plus `/etc/tmpfiles.d/80-devops-storage.conf`. The profile exports
`DEVOPS_BUILD_HOME`, `DEVOPS_CACHE_HOME`, and `DEVOPS_DB_HOME` under
`/pool/build/<user>`, `/pool/cache/<user>`, and `/pool/db/<user>`, then maps
common tool caches such as Cargo, Rustup, `sccache`, pip, pipx, pre-commit,
mypy, npm, Go, Gradle, Ansible, and ccache into those roots. When `sccache` is
installed, the profile also exports `RUSTC_WRAPPER=sccache` unless the session
already set a different Rust compiler wrapper.

To install the proprietary NVIDIA driver and firmware stack, add the `nvidia`
addon class:

```text
classes=lab,desktop,standard,dhcp,nvidia primary_user=<user> primary_password=<user-password> root_password=<root-password> fruux_username=<fruux-user> fruux_password=<fruux-app-password>
```

When enabled and an NVIDIA PCI display adapter is detected,
`d-i/debian/classes/class-addon/nvidia.cfg` adds `firmware-misc-nonfree` and
`nvidia-driver` to the selected package set. The shared late-command path then
stages the NVIDIA modprobe configuration and initramfs module list. If the
addon is selected on a host without detected NVIDIA display hardware, the
installer skips the NVIDIA package fragment and keeps only the auto-detected
GPU classes. Without an effective addon, the target receives an NVIDIA
blacklist so unattended installs do not auto-enable the proprietary stack.

To install the hardened rootless Podman baseline, add the `podman` addon
class:

```text
classes=lab,server,standard,dhcp,podman primary_user=<user> primary_password=<user-password> root_password=<root-password>
```

When enabled, `d-i/debian/classes/class-addon/podman.cfg` adds the managed
rootless Podman package set. The shared late-command path then provisions a
locked `podsvc` system account with `/usr/sbin/nologin`, managed rootless
config under `/data/config/podman`, rootless state under `/pool/podman`,
managed subordinate UID/GID ranges in `/etc/subuid` and `/etc/subgid`, Quadlet
user drop-ins under the managed containers config, and nftables-backed
rootless network configuration. On the `server` role, the installer also stages
the rootless Podman API socket path so Docker-compatible clients can target
`unix:///run/user/<uid>/podman/podman.sock` through `DOCKER_HOST` or
`CONTAINER_HOST` once the server-side linger bootstrap has activated the user
manager.

The addon also installs `/usr/local/sbin/podbin` and renders its managed
defaults under `/etc/default/podbin`. During install it creates the ed25519 key
pair `/data/pki/ssh/.keys/podbin_ed25519` and
`/data/pki/ssh/.keys/podbin_ed25519.pub`. `podbin --create-user <username>`
creates a locked system Podman user with per-user rootless config/state under
the managed Podman roots; the reserved `podsvc` service account remains the
installer-managed Podman service user and is not a podbin workload account.
By default, `podbin --create-container <username>` builds or reuses the managed
local image `localhost/podbin-runtime:trixie`, which provisions a fixed non-root
container login user `poduser` with shell `/bin/sh`, home `/home/poduser`,
read-only root login disabled in `sshd`, and writable tmpfs-backed home and
`/workspace` paths while the root filesystem stays read-only by default. The
managed image sets `USER` to the poduser UID/GID, and the generated Quadlet also
sets `[Container] User=<poduser-uid>:<poduser-gid>` so the container service
process starts as `poduser` rather than as container root.
Container creation now prompts only for the image, SSH/high-port mapping, bind
address, and read-only rootfs policy; the container SSH user, authorized-keys
path, and runtime shell stay fixed to the managed non-root contract unless root
intentionally selects a custom image that matches it. `podbin --start-container`
and `--connect-container` remain the daily-user path via the account sudoers
delegation, while `--create-user`, `--create-container`, `--open-container`,
and `--delete-container` stay on the root-admin path; `--open-container` still
execs into the selected container as the managed runtime UID/GID, not as root.
The connect path records host keys in the managed podbin known-hosts file
instead of the normal root SSH profile.

## Runtime Inputs

The host policy is split into concrete profiles and shared policy. The
concrete profile under `d-i/debian/hosts/profiles/<family>/<role>.env` is the
primary role-specific source of truth for:

- partition slot numbers and `SIZE_*` storage sizing values
- bootprofile labels and GRUB policy such as `GRUB_DEFAULT_ENTRY` and the
  `GRUB_PROFILE_*_FLAGS` sets
- NFT, tmpfs, Secure Boot state, and ZRAM first-boot policy
- installed-system troubleshooting levels through `NFTABLES_LOG_LEVEL`,
  `ZRAM_LOG_LEVEL`, and `SYSTEMD_LOG_LEVEL`; defaults are sparse
  (`none` for nftables generator diagnostics, `error` for zram and systemd/network logs)
- optional boot-time service masks through `GRUB_SYSTEMD_MASK_FLAGS`; NVMe
  Btrfs profiles mask `nvmf-autoconnect.service` by default so NVMe-oF remains
  opt-in, while profiles without masks still define `GRUB_SYSTEMD_MASK_FLAGS=""`
- disk/profile-specific sysctl dirty-writeback and reclaim budgets rendered into the
  staged `25-*.conf` target overrides and the bootprofile-owned
  `profiles/*/50-*.conf` overlays synced into `/run/sysctl.d`

Shared identity, account, runtime path, role-shared policy, layout primitive,
and boot defaults live under `d-i/debian/hosts/shared/*.env`. The host-policy
assembler now layers `hosts/shared/<role>.env` so desktop-only knobs stay in
`desktop.env` while shared server addon policy such as Podman can live in
`server.env`. `hosts/shared/layout.env` carries the cross-family mount security
fragments, tmpfs policy, common mount fragments, and ephemeral dm-crypt backing
for every profile. `layout-btrfs.env` owns the Btrfs/XFS labels, staging
paths, mount, mkfs, LUKS, and GRUB root policy for `btrfs-*` and `vm-*`, while
`layout-f2fs.env` owns the F2FS/eMMC labels, mount, mkfs, LUKS, and GRUB root
policy. In the F2FS family, optional `/pool` is still ext4 and uses the
explicit `MNT_EXT4_POOL_OPTS` contract.
`hosts/shared/runtime.env` carries shared sysctl target paths. The selected
`disk` class chooses the host profile and shared storage family; the concrete
profile supplies the rendered storage sysctl values.

The served repository stays read-only. `d-i/debian/scripts/early/dispatch.sh`
selects one of the six concrete host profiles, fetches the assembled
host policy env, fetches account policy separately from
`hosts/shared/account.env`, parses the installer kernel cmdline,
generates the final target hostname once as `SYSTEM_PREFIX-###`, renders the
runtime fragments inside the installer under `/tmp/install-runtime`, and seeds
debconf from that generated runtime state before partman starts. The concrete
profile is sourced before shared policy so shared env files can derive from
role-specific `SIZE_*`, `BOOTPROFILE_*`, `GRUB_*`, and slot values. User and
root account hashes stay in `d-i/debian/hosts/shared/account.env`;
they are not duplicated in tracked answer fragments. Target-side staged assets
now live under `d-i/debian/hooks/shared/target/**`,
`d-i/debian/hooks/hardware/<group>/<class>/target/**`, and optional
`d-i/debian/hooks/role/<role>/target/**`, with the hierarchy beneath each
`target/` root mirroring the installed system directly such as `target/etc/...`
or `target/usr/local/...`. Shared target policy also installs udev, UDisks2,
and ordered polkit rules under `target/etc` so removable-media authorization is
present on the installed system. The selected disk class chooses
the shared storage hook family directly: `nvme -> btrfs`, `vm -> vm`
with Btrfs layout policy, and `emmc -> f2fs`.

The runtime hooks derive `INSTALL_DISK_CANDIDATES` and the default
`DEV_INSTALL_DISK` from the selected disk class:

- `nvme` -> `/dev/nvme0n1 /dev/nvme*n* /dev/sd*`, default `/dev/nvme0n1`
- `vm` -> `/dev/nvme0n1 /dev/nvme*n* /dev/vd* /dev/sd* /dev/mmcblk*`, default `/dev/vda`
- `emmc` -> `/dev/mmcblk0 /dev/mmcblk*`, default `/dev/mmcblk0`

If you need to override the target disk, set `DEV_INSTALL_DISK` and optionally
`INSTALL_DISK_CANDIDATES` in the selected concrete host env before serving the
repo. The runtime hooks derive the effective `DEV_PART_*` device paths from the
final disk plus the explicit slot numbers in that host env.

Partition sizing is controlled through the selected concrete profile under `d-i/debian/hosts/profiles/<family>/<role>.env` plus shared layout policy under `d-i/debian/hosts/shared/*.env`, then materialized into effective `DEV_PART_*_MB` values inside `/tmp/install-runtime/runtime.env`. The runtime sizing logic uses the live install disk, fallback swap policy, hard floors, and explicit target sizes. On a 512 GiB install disk it aims for `/home=80 GiB`, `/data=100 GiB`, `/pool=150 GiB`, and a `32 GiB` raw zram backing partition before any remaining budget is given back to `/`. The F2FS/eMMC profiles keep a small fixed safety reserve so 29.25 GiB media can still fit the reduced F2FS minimum layout. In dual-boot mode the installer measures and validates the reused EFI partition plus every preserved pre-Debian slot before it computes the remaining Debian budget and renders the partman recipe. Tmpfs and zram runtime sizes are no longer emitted into `runtime.env`; they stay target-owned and percentage-based. Runtime device identity is still emitted: `ZRAM_BACKING_RAW_DEVICE` and `SWAP_FALLBACK_RAW_DEVICE` point at the raw partitions, while `ZRAM_BACKING_DEVICE` and `SWAP_FALLBACK_MAPPER` point at the boot-time plain dm-crypt mappers.

The target `zram-setup.service` serializes setup, reset, and stop operations
against the same `/run/zram/zram-writeback.lock` used by writeback passes, and
is ordered to finish before `multi-user.target` without waiting on debugfs. The
setup helper owns bounded waits for the raw by-partuuid backing device and
dm-crypt mapper readiness, so udev-late device nodes fail explicitly instead of
causing the one-shot unit to be skipped by a path condition. Reset uses
`zramctl --reset` first when available, waits for swapoff and open holders to
drain, verifies the device reaches the uninitialized state, and fails hard if
both zramctl and sysfs reset paths are rejected.
Maintenance actions run through one `zram-writeback.service` entrypoint for
timer-driven passes plus `zram-writebackd.service` for adaptive PSI pressure
events. The idle and cold-tier timers both trigger the one-shot service, while
the daemon registers `/proc/pressure/memory` triggers and dispatches only
pressure or emergency passes with cooldown and recovery hysteresis. The Perl
policy chooses `normal`, `pressure`, or `emergency` behavior from MemAvailable
and PSI without spawning separate action-specific interpreters. The generated
`/etc/zram-writeback.conf` owns maintenance policy: feature gates are explicit
`0`/`1` integers, recompression tiers are explicit, and cold-tier `MIN_*_PAGES`
values are real positive trigger counts rather than implicit disable switches.
Cold-tier passes first check the configured zram fill percentage before scanning
debugfs block state, then apply independent page caps for idle, huge-idle, and
huge recompression, an explicit incompressible writeback page cap, and a
pages-per-spec cap for generated `page_index`/`page_indexes` writeback chunks.
The default tiering keeps `lz4` as the primary compressor, uses `lzo-rle` at
priority 1 for reusable idle pages, uses `zstd` at priority 2 for huge idle
pages, and uses a smaller priority-3 `zstd` pass for huge non-idle pages only
under pressure or emergency. Normal runs recompress and compact only; pressure
runs can write back incompressible pages when the kernel writeback budget still
has room; emergency runs can additionally write back huge idle pages. When the
budget is exhausted, policy leaves pages in zram and limits the pass to
recompression and compaction.

Lifecycle operations remain shell-owned: `zram-device-setup start`, `stop`,
`reset`, `wait-backing`, and minimal `status` own module loading, dm-crypt
mapper readiness, zram reset, `mkswap`, and `swapon`/`swapoff`. The shell helper
does not execute Perl or print runtime metrics; its status output is limited to
device presence, init state, swap activation, mapper existence/writability, and
zram sysfs presence. Perl owns rich runtime status, parsed swap/backing-device
state, feature support, parsed `mm_stat`/`io_stat`/`bd_stat` fields, and debugfs
`block_state` availability. The Perl maintenance unit remains ordered with
`Requires=` and `After=` on `zram-setup.service` so runtime policy only starts
after the boot device setup has completed. Under the writeback service hardening,
only `/run/zram` is kept writable for lock, budget, and metrics state. The
optional Perl `reset-state` command only removes runtime policy artifacts under
`/run/zram`; it does not swap off devices, reset zram, or close dm-crypt
mappings.

The staged zram policy assumes the installed target uses the repository's
XanMod kernel path, not an older fallback kernel contract. In practice this
means the target must provide `CONFIG_ZRAM_WRITEBACK`,
`CONFIG_ZRAM_MEMORY_TRACKING`, `CONFIG_ZRAM_TRACK_ENTRY_ACTIME`, and
`CONFIG_ZRAM_MULTI_COMP`, plus Linux 7.0+ `writeback` interface semantics that
accept key/value `type=...`, multiple `page_index=...` tokens, and mixed
`page_indexes=LOW-HIGH` ranges in a single call. The setup path intentionally
fails fast when those required zram sysfs capabilities are absent.

## Install Paths

If you do not select the `dualboot` addon class, the installer behaves like the full-disk install path:

- the target disk is wiped
- a new GPT label is written
- Debian owns slots `1` through `12`

The detailed slot contract below describes the Btrfs storage family used by the
`btrfs-*` bare-metal NVMe profiles and the `vm-*` VM profiles. The `emmc`
F2FS family uses the reduced full-disk map owned by its concrete profiles
instead. In direct Secure Boot state mode that map is `1=/boot/efi`,
`2=/boot`, `3=/`, optional `4=/home` or `/pool`, `5=/var/log/journal`,
`6=raw swap fallback`, and `7=raw zram writeback`. When
`SECURE_BOOT_STATE_MODE=luks`, the runtime inserts `5=/var/lib/shim-signed`
as LUKS2 + ext4 and shifts the persistent journal, raw swap, and raw zram
partitions to slots `6`, `7`, and `8`.

The Btrfs full-disk slot contract is:

- slot `1`: `/boot/efi`
- slot `2`: `/boot`
- slot `3`: `/`
- slot `4`: `/home`
- slot `5`: `/opt`
- slot `6`: `/data`
- slot `7`: `/pool`
- slot `8`: `/var/tmp`
- slot `9`: `/var/lib/shim-signed` (LUKS2 + ext4)
- slot `10`: `/var/log/journal`
- slot `11`: raw swap fallback partition, opened at boot as `/dev/mapper/swap-fallback`
- slot `12`: raw zram writeback partition, opened at boot as `/dev/mapper/zram-writeback`

Dual-boot is enabled only when the kernel cmdline includes the `dualboot`
addon class and both required slot values:

- `classes=...,dualboot`
- `dualboot_efi=<n>`
- `dualboot_debian=<n>`

Omitting either slot value exits the install before partitioning.

The installer entrypoint accepts any of `url=`, `preseed/url=`, `file=`, or
`preseed/file=` as long as the value points at
`d-i/debian/preseed.cfg`. The runtime normalizes that value back to the served
`d-i/debian/` root before it fetches class fragments, hook assets, and phase
dispatchers.

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8080/d-i/debian/preseed.cfg classes=lab,desktop,standard,dhcp,dualboot dualboot_efi=1 dualboot_debian=5
```

Override example:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US url=http://<lan-host>:8080/d-i/debian/preseed.cfg classes=lab,desktop,standard,dhcp,dualboot dualboot_efi=2 dualboot_debian=6
```

The dual-boot contract is UEFI + GPT on the same disk:

- `dualboot_efi=<n>` reuses the existing EFI System Partition at slot `n` and mounts it as `/boot/efi` without formatting it
- `dualboot_debian=<n>` makes Debian `/boot` start at slot `n`
- every slot from `1` up to `dualboot_debian - 1`, except the reused EFI slot, is preserved
- Debian then consumes 11 contiguous slots: `/boot`, `/`, `/home`, `/opt`, `/data`, `/pool`, `/var/tmp`, `/var/lib/shim-signed`, `/var/log/journal`, raw swap fallback, raw zram writeback

Example: `classes=...,dualboot dualboot_efi=1 dualboot_debian=5`

- slot `1`: reused ESP
- slots `2`, `3`, `4`: preserved
- slots `5` through `15`: Debian-owned partitions

In dual-boot mode the partman preparation hook preserves the existing GPT label, verifies that `dualboot_efi=<n>` points at a real vfat GPT EFI System Partition, measures every pre-Debian partition slot, and steers partman to the target disk instead of whole-disk partitioning. If Debian-owned slots already exist from an earlier run, the partman option deletes only slots from `dualboot_debian` upward through partman before selecting the newly freed span; otherwise it selects the largest existing free span on `DEV_INSTALL_DISK`. The generated recipe contains only Debian-owned partitions, so the reused ESP and Windows-side slots are not recreated inside the selected free span; after autopartition succeeds, the partman option marks the existing `DEV_PART_EFI` partition as `method=efi` in partman state so partman-efi and GRUB recognize it without formatting it. When the `dualboot` addon class is selected, `d-i/debian/classes/class-addon/dualboot.cfg` keeps `os-prober` in `pkgsel/include`, flips GRUB installer answers to probe other operating systems, and late-command repairs the package if pkgsel missed it before the final GRUB update. On the target side GRUB is configured for `os-prober` discovery with `GRUB_DISABLE_OS_PROBER=false`, so other supported operating systems are detected by GRUB itself instead of by a hard-coded custom chainloader entry.

## Installer Flow

1. `d-i/debian/preseed.cfg` resolves `url=`, `preseed/url=`, `file=`, or `preseed/file=` to the served tree root, then wires the early, partman, and late dispatchers from that tree.
2. The shared bootstrap helper reuses the resolved seed source, records installer context under `/tmp/install-runtime`, caches fetched seed assets under `/tmp/install-runtime/cache/seed`, and fetches the real phase entrypoint directly for `prepare-context`, `apply`, `early`, `partman`, or `late`. `d-i/debian/scripts/preseed/dispatch.sh` remains only as compatibility glue for direct/manual invocation.
3. `d-i/debian/scripts/preseed/answers.sh` fetches only the selected class fragments under `d-i/debian/classes/**` that actually carry debconf deltas, merges additive `anna/choose_modules` and `pkgsel/include` answers, writes the generated Secure Boot package environment, and applies the generated debconf selections so class fragments do not overwrite one another. Tasksel is explicitly disabled in the active installer path, and any class fragment that tries to seed tasksel now aborts the install instead of silently enabling installer-selected tasks.
4. `d-i/debian/scripts/early/dispatch.sh` calls the shared d-i early hook with the selected storage family, generates the final hostname from `SYSTEM_PREFIX`, renders the identity/account/partman fragments under `/tmp/install-runtime`, and seeds debconf before the installer reaches netcfg, account setup, or partman.
5. `d-i/debian/scripts/partman/dispatch.sh` calls the selected shared partman path, which either wipes the whole disk for the default full-disk install path or preserves the existing pre-Debian slots for dual-boot, then installs a generated shared partman finish hook.
6. The generated shared `99-storage-layout` partman finish hook formats the managed filesystems, preserves the raw swap fallback and zram writeback partitions as block devices, mounts the persistent graph under `/target`, prepares volatile backing directories without mounting tmpfs, writes the target-side fstab, and writes a tmpfs-free partman fstab cache for d-i.
7. A shared installer apt-setup generator at `d-i/debian/hooks/shared/apt-setup/generators/99-apt-preferences` is injected into `/usr/lib/apt-setup/generators/` during d-i early setup so it retrieves `d-i/debian/repo.env`, reads `DEBIAN_APT_PREFERENCES`, and installs the selected managed preference files from the repo preferences directory into `/target/etc/apt/preferences.d` while apt-setup configures target APT state.
8. The shared late-command dispatcher validates the mounted target, stages tracked assets from `d-i/debian/hooks/shared/target/**` and `d-i/debian/hooks/hardware/<group>/<class>/target/**`, runs optional role late hooks from `d-i/debian/hooks/role/<role>/late_command.sh`, installs the managed Secure Boot helper and kernel hook scripts, applies the kernel/bootloader/storage runtime policy, and finishes the GRUB, zram, journald, APT, and first-boot service configuration. Service enablement is staged by writing the target systemd symlink graph directly; the installer does not call `systemctl enable`, `systemctl set-default`, or `systemctl is-enabled` inside `/target`.
9. A shared installer hook at `d-i/debian/hooks/shared/finish-install.d/99-normalize-finish` is injected into `/usr/lib/finish-install.d/` during d-i early setup so it runs after `preseed/late_command` and later numbered finish-install hooks. It unmounts any leftover nested target mounts below volatile paths, wipes the backing directories for tmpfs-enabled `/var/log`, `/var/cache`, `/var/lib/apt/lists`, `/data/run`, `/var/lib/systemd/coredump`, and `/dev/shm`, verifies those backing directories are empty, and normalizes `/tmp` immediately before the installer hands off to first boot.

When Secure Boot is enabled, the late hook attempts to queue the managed `MOK.der` certificate import through `mokutil`, writes the Secure Boot config with shell-safe single quoting, asks `mokutil --generate-hash` to create the MokManager password hash, queues the import with `--hash-file`, requires `mokutil --timeout -1` so first-boot MokManager enrollment waits without a countdown, and sets shim's fallback no-reboot flag. If the target already has same-common-name enrolled MOKs but not the generated certificate, stale duplicate deletion is deferred until after enrollment so the import remains the only boot-critical pending request; when the generated certificate is already enrolled, duplicate cleanup is attempted and any `mokutil` queue failure is logged without blocking the installed system. If EFI variable access is unavailable during installation, the hook now fails instead of silently leaving manual enrollment as the only path. Before `update-grub`, the late hook signs and verifies every bootable `/boot/vmlinuz-*` image with the generated MOK, forces the removable EFI fallback path to be a byte-for-byte copy of signed shim, and makes the firmware BootOrder/BootNext entry point at shim rather than GRUB. After `update-grub` and MOK import queueing, it sets GRUB's one-shot next boot to `installer-mok-enrollment` so the first target boot enters MokManager instead of trying to execute a MOK-signed kernel before the MOK is enrolled. The managed GRUB menu keeps both the top-level menu and profile submenus at an indefinite wait and the managed MokManager path is also pinned to no timeout. In dual-boot installs, os-prober output is invoked only from the managed `40_custom` generator when available, so detected foreign OS entries remain in the custom menu path instead of enabling native GRUB generators. They appear before the dynamic Debian entry for the most recently booted profile and kernel, then the `Balanced`, `Performance`, and `Hardened` profile submenus, `BTRFS Snapshots`, `Boot from Rescue USB`, `MOK Enrollment`, and finally `UEFI Firmware Settings`. The installer keeps the GRUB profile generator in `40_custom`, disables duplicate and unmanaged GRUB menu generators including `05_debian_theme`, and writes the same managed menu to `/boot/grub/custom.cfg` without enabling a separate GRUB theme or managed font override. The display drop-in keeps `gfxterm` for the GRUB menu at the 1024x768 firmware mode commonly associated with legacy VGA 766, leaves the GRUB menu uncolored, and sets the managed Linux menu payload to text so kernel KMS can re-probe the real runtime display cleanly. When the optional `timeshift` addon is selected on a Btrfs-root host, the late hook also stages managed Timeshift snapshot timers plus a GRUB snapshot refresh helper so `BTRFS Snapshots` loads `/boot/grub/grub-btrfs.cfg` generated from the current Timeshift snapshot set and profile flags. The generated GRUB `Boot from Rescue USB` entry requires UEFI GRUB, derives the installer rescue USB search UUID from the mounted FAT installer seed medium when available, falls back to a removable-EFI file search otherwise, and chainloads the architecture-specific removable EFI path (`/EFI/BOOT/BOOTX64.EFI` on `amd64`, `/EFI/BOOT/BOOTAA64.EFI` on `arm64`). The generated GRUB `MOK Enrollment` entry documents the existing `/var/lib/shim-signed/secure-boot/MOK.der` certificate, searches the ESP, and chainloads the architecture-specific MokManager binary under `EFI/debian` (`mmx64.efi` on `amd64`, `mmaa64.efi` on `arm64`), so selecting it starts MokManager against the generated certificate. The same certificate is also copied to `/boot/efi/MOK Enrollment/MOK.der` for operator access from the ESP. The generated signing certificate intentionally omits shim's module-signing-only EKU OID `1.3.6.1.4.1.2312.16.1.2`, because shim and GRUB ignore that class of key for kernel image validation and would reject installer-signed boot images with `bad shim signature`. Debian still requires the actual MOK enrollment to be confirmed on the boot console, so the operator must enter the account username in MokManager on the following reboot; the account password hash cannot be reused as a MokManager hash. When `SECURE_BOOT_STATE_MODE=luks`, open the encrypted Secure Boot state after installation with `luks-mok-open` before any kernel-signing or MOK-management work, close it with `luks-mok-close`, and rotate its passphrase with `luks-mok-passwd`.

For snapshot-only GRUB maintenance while the Secure Boot state is closed, run
`SKIP_MOK_SIGNING=1 update-grub`. This suppresses only the managed MOK
enrollment menu and certificate checks; it does not sign or modify kernels.
The managed `grub-btrfs-refresh.service` exports this value and refreshes only
`/boot/grub/grub-btrfs.cfg`, so Timeshift snapshot events do not need the MOK
state to be open.

The Btrfs and VM families default to a dedicated encrypted
`/var/lib/shim-signed` partition and the `luks-mok-*` helpers. The F2FS
families stage the same Secure Boot toolchain and GRUB/MOK workflow, and their
state path is selected by `SECURE_BOOT_STATE_MODE`: `direct` keeps Secure Boot
state on the root filesystem under `/var/lib/shim-signed/secure-boot`, while
`luks` inserts a dedicated LUKS2 + ext4 `/var/lib/shim-signed` partition into
the reduced F2FS partition map and stages the same `luks-mok-*` helpers used by
the Btrfs profiles.

The F2FS root filesystem is created with
`extra_attr,inode_checksum,sb_checksum,inode_crtime,lost_found,compression`,
and optional F2FS `/home` uses the same feature set without `lost_found`.
These filesystems are then mounted with lzo-rle compression in filesystem
mode. The shared F2FS policy compresses root broadly with
`compress_extension=*`, excludes already-compressed media, archives, package
payloads, and disk images with repeated `nocompress_extension=` entries capped
to the current F2FS extension-list limit, and uses `nodiscard` because the
installed system enables `fstrim.timer`.

## Validation

Review the shared hook implementations, hardware target assets, and staged shared target assets
directly under `d-i/debian/**` before serving installer changes. Runtime class,
host-profile, and late-phase consistency checks now live in the installer code
paths themselves instead of in a separate validation script.

## Installer Logs

Installer logging is disabled unless the `debug` class is explicitly selected
in `classes=`. Without `debug`, the installer does not create
`/tmp/preseed-logs/` and does not copy installer logs into the target.

When `debug` is selected, the installer writes stage/category logs under
`/tmp/preseed-logs/` inside the installer environment. Logs are created when a
stage emits records; the final finish-install hook archives them to
`/target/var/lib/preseed/logs/installer/` and writes an explicit
`status=not-created` marker for any expected stage that did not emit records
before handoff. During a debug run, expect these files:

- `01-boot.log`: boot parameters, kernel/initrd context, hardware detection, selected classes, and storage family.
- `02-preseed.log`: preseed source confirmation, timestamps, generated identity, MAC/IP context, and debconf answer seeding.
- `03-network.log`: installer interfaces, addresses, routes, DNS, and network context.
- `04-disk.log`: disks seen by the installer, serial/model details when exposed by sysfs, and the selected install disk.
- `05-partman.log`: partman early hooks, destructive wipe or dual-boot preservation, recipes, filesystems, target mounts, and resulting layout.
- `06-apt.log`: apt-setup preferences, package policy, and apt metadata refreshes.
- `07-packages.log`: `pkgsel/include` package verification/repair, target package installs/removals, apt install output, dpkg failures, and DKMS output.
- `08-bootloader.log`: GRUB, shim/MOK, Secure Boot, initramfs, kernel signing, EFI/BIOS, and boot-entry work.
- `09-late.log`: late-command target customization, users, SSH, hardening, services, volatile directory normalization, and final log archive.
- `10-desktop.log`: Labwc desktop policy, detected outputs, greetd/default rendering, staged desktop assets, user config installation, service enablement, and desktop command verification.

Log records include fixed stage labels such as `boot`, `preseed_loaded`, `network_configured`, `disk_discovery`, `partman_start`, `partman_done`, `base_install_start`, `apt_config`, `package_install`, `bootloader`, `late_command`, `target_customization`, `first_boot`, and `post_install_validation`.

The same archive includes a bounded, redacted copy of Debian Installer logs
under `/var/lib/preseed/logs/installer/debian-installer/`, including live
`syslog`, `partman`, and `debootstrap` logs when those files are present. When
a debug install fails before the target is complete, the most useful live logs
remain under `/tmp/preseed-logs/` and `/var/log/` inside the installer
environment.

The first boot service stages `/usr/local/sbin/firstboot.sh`, runs ordered scripts from `/usr/local/lib/firstboot.d/`, leaves initramfs health logs under `/var/lib/preseed/logs/initramfs/` with numbered hook-stage names such as `01-init-top.log` and `05-init-bottom.log`, and stores firstboot data under `/var/lib/preseed/logs/firstboot/`. Initramfs hooks always spool logs under `/run/preseed-initramfs-health`; firstboot copies that spool into `/var/lib/preseed/logs/initramfs/` after switch-root before validation and cleanup. The cleanup stage removes the firstboot service, removes the repo-managed initramfs health hooks from `/etc/initramfs-tools/scripts/**`, rebuilds initramfs with `update-initramfs -u -k all`, and writes `/var/lib/preseed/firstboot/complete`.

## First-Boot Checks

After installation, validate the live storage contract on the target machine:

```bash
findmnt -no FSTYPE,OPTIONS /data
findmnt -no FSTYPE,OPTIONS /data/run
findmnt -no FSTYPE,OPTIONS /pool
xfs_info /data
xfs_info /pool
findmnt -no FSTYPE,OPTIONS /var/log
findmnt -no FSTYPE,OPTIONS /var/log/journal
findmnt -no FSTYPE,OPTIONS /var/tmp
findmnt -no FSTYPE,OPTIONS /var/cache
findmnt -no FSTYPE,OPTIONS /var/lib/apt/lists
findmnt -no FSTYPE,OPTIONS /var/lib/systemd/coredump
cryptsetup status swap-fallback
cryptsetup status zram-writeback
state_mode=$(sed -n 's/^SECURE_BOOT_STATE_MODE=//p' /etc/default/secure-boot.conf | tr -d "'\"")
if [ "$state_mode" = "luks" ]; then
  luks-mok-open
  findmnt -M /var/lib/shim-signed -no SOURCE,FSTYPE,OPTIONS
else
  test -d /var/lib/shim-signed/secure-boot
fi
ls -l "/boot/efi/MOK Enrollment/MOK.der"
ls -l /boot/grub/fonts/dejavu-sans-mono.pf2
if [ "$state_mode" = "luks" ]; then
  luks-mok-close
fi
stat -c '%a %n' /var/tmp /tmp
test -L /data/run/mnt
test "$(readlink /data/run/mnt)" = "/run/media/mcramer"
swapon --show
lsblk -o NAME,FSTYPE,TYPE,MOUNTPOINTS
test -s /boot/grub/grubenv
grub-editenv list
test "$(readlink -f /etc/systemd/system/dbus.service)" = "$(readlink -f /usr/lib/systemd/system/dbus-broker.service)"
test "$(readlink -f /etc/systemd/user/dbus.service)" = "$(readlink -f /usr/lib/systemd/user/dbus-broker.service)"
dpkg-query -W dbus-broker dbus-user-session dbus-bin dbus-system-bus-common dbus-session-bus-common
! dpkg-query -W dbus
! dpkg-query -W dbus-daemon
! dpkg-query -W dbus-x11
! grep -q 'dbus-run-session' /usr/local/bin/labwc-greeter-session /usr/local/bin/labwc-session
grep -q '/usr/bin/cage -s -m last -- /usr/bin/gtkgreet -s /etc/greetd/gtkgreet.css' /usr/local/bin/labwc-greeter-session
! grep -q 'dbus-update-activation-environment' /usr/local/bin/labwc-autostart
! grep -q 'import-environment' /usr/local/bin/labwc-autostart
grep -q 'labwc-session.target' /usr/local/bin/labwc-autostart
test -r /etc/skel/.config/systemd/user/labwc-session.target
dpkg-query -W udisks2 polkitd
getent group usbmedia
getent group usbadmin
test -r /etc/udisks2/udisks2.conf
test -r /etc/udisks2/mount_options.conf
test -r /etc/udev/udev.conf.d/90-hardening.conf
test -r /etc/udev/rules.d/90-udisks-behavior.rules
for rule in \
  00-admin-identities.rules \
  05-active-local-gate.rules \
  10-pkexec.rules \
  20-login1-power.rules \
  40-networkmanager.rules \
  50-usb-policy.rules \
  55-software-management.rules \
  60-system-services-identity.rules \
  70-hardware-peripherals.rules
do
  test -r "/etc/polkit-1/rules.d/$rule"
done
systemctl get-default
systemctl is-enabled swap-fallback.service zram-setup.service zram-writebackd.service zram-idle-writeback.timer zram-cold-tier.timer fstrim.timer btrfs-scrub.timer btrfs-balance.timer
systemctl cat tmpfs-pre-clean.service --no-pager
systemctl status apt-refresh-lists.service --no-pager  # only when TMPFS_VAR_LIB_APT_LISTS=true
systemctl status fstrim.timer fstrim.service --no-pager
systemctl status swap-fallback.service --no-pager
systemctl status zram-setup.service --no-pager
systemctl status zram-writeback.service --no-pager
test -d "/home/<user>/Workspace"
find /etc /usr/local/sbin /var/lib/preseed -name '*install*' -print
```

When a layer sets a managed `TMPFS_*` policy to true, late command installs a
drop-in for the matching generated `.mount` unit so it requires
`tmpfs-pre-clean.service`. The service is not enabled directly; it is pulled in only
by those tmpfs mount units and runs `/usr/local/sbin/tmpfs-pre-clean` before them to
empty the configured backing directories. It intentionally does not use
`PrivateTmp`, because that would order it after `systemd-tmpfiles-setup.service`
and recreate the `systemd-journal-flush.service` cycle. When `/data/run` is
enabled, the service also requires the `/data` mount before it runs. The managed
tmpfiles fragments only recreate installer-owned child paths so Debian's vendor
tmpfiles fragments keep ownership of `/run/lock`, `/var/log`, `/var/cache`, and
`/var/lib/systemd/coredump`.

`apt-refresh-lists.service` is staged and enabled only when
`TMPFS_VAR_LIB_APT_LISTS=true`. The `/var/lib/apt/lists` mount drop-in orders it
after the volatile apt-lists mount, and the helper only repairs apt list state,
performs bounded Debian mirror connectivity probing, and runs `apt-get update`.
The service also orders itself after `NetworkManager-dispatcher.service` and
waits briefly for that dispatcher unit to become inactive before refreshing apt
metadata, so network-dispatcher work triggered during first boot is not raced.
The managed `apt-daily.service.d` override no longer depends on
`apt-refresh-lists.service`; it only carries the common noninteractive and
hardening settings.

`fstrim.timer` is enabled with a local four-day interval override, while Btrfs scrub and balance are delegated to `btrfsmaintenance` only on Btrfs targets. The generated Btrfs maintenance config logs to the journal, scrubs `/`, `/home`, and `/opt` monthly, runs a mild monthly balance only for `/`, and leaves trim disabled there because `fstrim.timer` owns discard scheduling.
