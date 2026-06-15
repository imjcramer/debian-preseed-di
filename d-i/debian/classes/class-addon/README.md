# Add-on Classes

Place direct `*.cfg` class fragments here for local additive classes. For
example, `testing.cfg` can be selected on the installer kernel command line as
`classes=...,testing`.

`nvidia.cfg` installs the NVIDIA driver and firmware stack when selected as
`classes=...,nvidia` and an NVIDIA PCI display adapter is detected. NVIDIA is
intentionally not auto-selected from PCI detection.

`ssh.cfg` installs the target OpenSSH server package and enables the
shared late-command SSH configuration/key staging path when selected as
`classes=...,ssh`.

`wifi.cfg` preselects WPA Wi-Fi and static netcfg mode when selected as
`classes=...,wifi`; concrete ESSID, WPA, and static IPv4 values are appended
from kernel `netcfg/*` parameters by `scripts/preseed/answers.sh`.

`devops.cfg` installs the development and CI toolchain when selected as
`classes=...,devops`; its late helper stages `/pool`-backed build, cache, and
tool database defaults for interactive development workloads, including
`sccache` cache placement for Rust and native builds.

`podman.cfg` installs the managed rootless Podman / Buildah package baseline
when selected as `classes=...,podman`; the shared late-command Podman module
then provisions the locked `podsvc` service account, managed `/data/config/podman`
config roots, `/pool/podman` state roots, Quadlet defaults, and the
server-role rootless API socket bootstrap.

`dualboot.cfg` enables the reused-ESP dual-boot path when selected as
`classes=...,dualboot`. It requires `dualboot_efi=<n>` and
`dualboot_debian=<n>` on the installer kernel command line, installs
`os-prober`, and flips GRUB installer answers to probe other operating systems.

`timeshift.cfg` installs Timeshift and enables the managed Btrfs snapshot /
GRUB snapshot-menu integration when selected as `classes=...,timeshift`. The
class is restricted to Btrfs-root storage profiles through `CLASSES.conf`.
