# podbin helper guide

This guide is staged only when the `addon/podman` path enables the `podbin`
helper.

## Purpose

`/usr/local/sbin/podbin` provisions a managed rootless Podman user and a
non-root SSH-capable container workflow on top of the staged Podman templates.

## Commands

- `podbin --create-user <username>`
- `podbin --create-container <username>`
- `podbin --delete-container <username>`
- `podbin --start-container <username>`
- `podbin --connect-container <username>`
- `podbin --open-container <username>`

## Typical flow

```sh
sudo podbin --create-user alice
sudo podbin --create-container alice
sudo podbin --start-container alice
sudo podbin --connect-container alice
```

## Managed defaults

- defaults file: `/etc/default/podbin`
- template root: `/data/config/podman/templates/podbin`
- user config root: `/data/config/podman/users`
- user state root: `/pool/podman`
- SSH known hosts file: `/data/config/podman/podbin/known_hosts`

## Notes

- The runtime container user is fixed to a managed non-root account.
- The helper refuses reserved account names and reserved low ports.
- The helper renders its managed files from staged templates rather than
  inlining shell-generated config files.
