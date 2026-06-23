# podbin wrapper guide

This guide is staged when the `podman` addon enables the managed `podbin`
workflow.

## What podbin manages

`/usr/local/sbin/podbin` sits on top of the installer-managed rootless Podman
layout. It has two distinct jobs:

1. create and maintain dedicated system Podman users below
   `/data/accounts/podman/users`
2. create and operate SSH-capable rootless containers for those users without
   turning them into normal login accounts

It also exposes a controlled bridge into the installer-managed `podsvc`
service account so the primary daily account can inspect the shared rootless
Podman service safely.

## Command summary

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

## Root-admin lifecycle

Root or password-backed `sudo` is required for user and container creation,
deletion, and for opening an administrative shell inside the managed Podman
service account.

### Create a managed Podman user

```sh
sudo podbin --create-user alice
```

What this does:

- creates or validates a system account named `alice`
- keeps the shell locked to `/usr/sbin/nologin`
- stores managed config below `/data/config/podman/users/alice`
- stores rootless state below `/pool/podman/alice`
- prepares the user manager and Quadlet layout needed for container services

The helper rejects normal login-style accounts, reserved names, login homes
under `/home`, and any account that would collide with the reserved `podsvc`
service account.

### Create a managed container

```sh
sudo podbin --create-container alice
```

The helper prompts for:

- container name
- image reference
- container SSH port
- host SSH port
- host bind address
- read-only root filesystem policy

Important defaults and constraints:

- default image: `localhost/podbin-runtime:trixie`
- default bind address: `127.0.0.1`
- default container SSH port: `2222`
- default runtime login user: `poduser`
- default runtime shell: `/bin/sh`
- default authorized keys path: `/home/poduser/.ssh`
- host ports must stay in the managed high-port range

When you keep the managed default image, `podbin` will build it on demand from
the staged templates if it is not already present.

### Start and connect

```sh
sudo podbin --start-container alice
sudo podbin --connect-container alice
```

`--start-container` starts the selected Quadlet-backed user service.
`--connect-container` starts the container if needed, then connects over SSH
with the managed podbin keypair and the dedicated known-hosts file.

### Open an interactive shell inside the container

```sh
sudo podbin --open-container alice
```

This does not enter as container root. The helper explicitly uses the managed
runtime UID/GID, so the session lands inside the container as `poduser`.

### Delete a container

```sh
sudo podbin --delete-container alice
```

Deletion is interactive on purpose. The helper asks for an explicit `yes`
confirmation before it removes the Quadlet unit, container data, and metadata.

## Daily-account bridge to the managed podsvc service

The primary daily account can use `sudo` with `podbin --service-*` to inspect
or operate the installer-managed `podsvc` rootless Podman service without
logging in as `podsvc`.

Typical read-only inspection commands:

```sh
sudo podbin --service-env
sudo podbin --service-podman info
sudo podbin --service-podman ps --all
sudo podbin --service-podman images
sudo podbin --service-systemctl status podman.socket
sudo podbin --service-journalctl -u podman.service -n 200
```

For a deeper service-operations guide, read
`/data/docs/podbin-service-bridge.md`.

## Managed files and paths

- wrapper: `/usr/local/sbin/podbin`
- defaults: `/etc/default/podbin`
- per-user home root: `/data/accounts/podman/users`
- per-user config root: `/data/config/podman/users`
- per-user metadata root: `/data/config/podman/podbin/users`
- Podbin templates: `/data/config/podman/templates/podbin`
- rootless state root: `/pool/podman`
- Podbin SSH keypair: `/data/pki/ssh/.keys/podbin_ed25519`
- Podbin known hosts: `/data/config/podman/podbin/known_hosts`

## Security model

- the managed `podsvc` account stays locked and non-login
- the managed runtime container user stays fixed to a non-root account
- reserved account names and low ports are rejected
- container metadata stays root-owned and mode `0600`
- the helper renders managed config from staged templates instead of ad-hoc
  heredocs
- SSH host keys for container connects are stored in the dedicated podbin
  known-hosts file, not in a caller's normal SSH profile

## Recommended quick start

```sh
sudo podbin --create-user alice
sudo podbin --create-container alice
sudo podbin --start-container alice
sudo podbin --connect-container alice
```

After that, the daily account can inspect the shared rootless Podman service
with `sudo podbin --service-*` commands while container creation and deletion
remain on the root-admin path.
