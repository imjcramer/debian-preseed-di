# podbin helper guide

This guide is staged only when the `addon/podman` path enables the `podbin`
helper.

## Purpose

`/usr/local/sbin/podbin` provisions a managed rootless Podman user and a
non-root SSH-capable container workflow on top of the staged Podman templates.
When the desktop Podman addon is enabled, the same helper also bridges the
primary daily account into the managed `podsvc` rootless Podman service user.

## Commands

- `podbin --create-user <username>`
- `podbin --create-container <username>`
- `podbin --delete-container <username>`
- `podbin --start-container <username>`
- `podbin --connect-container <username>`
- `podbin --open-container <username>`
- `podbin --service-env`
- `podbin --service-podman <podman-args...>`
- `podbin --service-systemctl <systemctl-user-args...>`
- `podbin --service-journalctl <journalctl-user-args...>`
- `podbin --service-shell`

## Typical flow

```sh
sudo podbin --create-user alice
sudo podbin --create-container alice
sudo podbin --start-container alice
sudo podbin --connect-container alice
```

## Manage the staged rootless Podman service account

The primary daily account can manage the staged `podsvc` rootless Podman
runtime through `sudo` without taking over the service account directly.

```sh
sudo podbin --service-env
sudo podbin --service-podman info
sudo podbin --service-podman ps --all
sudo podbin --service-systemctl status podman.socket
sudo podbin --service-journalctl -u podman.service -n 200
sudo podbin --service-shell
```

Optional shell aliases for the daily account:

```sh
alias podsvc-podman='sudo /usr/local/sbin/podbin --service-podman'
alias podsvc-systemctl='sudo /usr/local/sbin/podbin --service-systemctl'
alias podsvc-journal='sudo /usr/local/sbin/podbin --service-journalctl'
```

The generated sudoers policy keeps common low-risk inspection and access
commands passwordless, including `--service-env`, read-only
`--service-podman` queries such as `info`, `ps`, `images`, `inspect`, `logs`,
and `--service-systemctl`/`--service-journalctl` status views. Mutating
actions such as `--create-user`, `--create-container`, `--delete-container`,
`--service-shell`, or write-capable `--service-podman` commands still require
ordinary password-backed `sudo`.

## Managed defaults

- defaults file: `/etc/default/podbin`
- template root: `/data/config/podman/templates/podbin`
- user config root: `/data/config/podman/users`
- user state root: `/pool/podman`
- SSH known hosts file: `/data/config/podman/podbin/known_hosts`

## Notes

- The runtime container user is fixed to a managed non-root account.
- The staged `podsvc` service account stays locked and non-login; `podbin`
  runs the Podman CLI, `systemctl --user`, and shell bridge with the correct
  runtime environment on the caller's behalf.
- The helper refuses reserved account names and reserved low ports.
- The helper renders its managed files from staged templates rather than
  inlining shell-generated config files.
