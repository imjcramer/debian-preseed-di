Hook assets resolve explicitly by scope:

- `hooks/shared/...` for installer assets shared by every storage family
- `hooks/hardware/<group>/<class>/target/...` for auto-detected hardware
  target payloads such as disk, CPU, GPU, and architecture-specific assets
- `hooks/role/<role>/...` for role-specific late-command and target assets such
  as `desktop` and `server`
- `hooks/services/<service>/target/...` for service-specific target payloads
  that are only installed when the matching optional service class is selected

The selected installer classes define the storage family up front, and the
dispatchers call the shared d-i, partman, and late-command implementations with
that family as data. Host profiles own profile-specific env policy directly,
while shared host policy lives under `hosts/shared/*.env`. There is no
per-family hook tree because the former family hooks were only thin wrappers
around shared logic.

Use `hooks/shared` only for assets that are safe across every storage family.
Use `hooks/hardware` for target configuration that should follow auto-detected
hardware classes.
Use `hooks/role/<role>` only when the selected role class needs
role-specific late-command or target assets.
Use `hooks/services/<service>` only for optional service payloads that belong
to one selected service role and do not belong in shared, hardware, or role
scope.

Within each `target/` tree, mirror the installed path directly beneath
`target/`, for example:

- `target/etc/systemd/system/` for units, timers, and drop-ins
- `target/usr/local/sbin/` for staged helper executables
- `target/usr/libexec/` for staged library-style helpers
- `target/etc/polkit-1/rules.d/`, `target/etc/udisks2/`, `target/etc/udev/`, `target/etc/tmpfiles.d/`, `target/etc/default/`, `target/etc/modules-load.d/`, `target/etc/modprobe.d/`, `target/etc/sysctl.d/`, and similar for target configuration payloads
