# GitLab runner helper guide

This guide is staged only when the `service/gitlab-runner` class is selected.

## Managed users

- `glab-aptly`: dedicated Aptly publishing runner
- `glab-user`: shared build and task runner user
- `aptly`: dedicated Aptly state and signing owner

These managed users intentionally use `/usr/sbin/nologin`. `sudo -iu glab-user`
or `sudo -iu glab-aptly` is expected to fail and is not the supported
debugging path.

Persistent Podman storage for those runners stays under `/pool/podman/<user>`,
but rootless Podman runtime state now stays under `/run/user/<uid>/run` and
`/run/user/<uid>/libpod/tmp` so helpers such as `pasta` write PID and runtime
files on the user runtime filesystem instead of under `/pool`.

## Managed files

- `/etc/default/gitlab-runner/gitlab-runner-shared.env`
- `/etc/default/gitlab-runner/gitlab-runner-aptly.env`
- `/etc/default/gitlab-runner/gitlab-runner-build.env`
- `/etc/default/gitlab-runner/gitlab-runner-task.env`
- `/data/config/runners/glab-aptly/config.toml`
- `/data/config/runners/glab-aptly/.runner_system_id`
- `/data/config/runners/glab-user/config.toml`
- `/data/config/runners/glab-user/.runner_system_id`
- `/pool/aptly/.aptly.conf`

## Operator entrypoints

Use `glab-helper` from an admin account with `sudo` access:

```sh
sudo glab-helper --user glab-aptly status gitlab-runner.service
sudo glab-helper --user glab-user journalctl -u gitlab-runner.service -n 100 --no-pager
sudo glab-helper --user glab-user podman ps
sudo glab-helper --user glab-aptly aptly-managed publish snapshot repo-name s3:r2:
```

Use `gitlab-runner-managed` through `glab-helper`. The `refresh` and `once`
control-plane paths are intended to run with `sudo` so the rendered control
files stay root-managed, while the runner service itself still executes as the
managed user.

Supported subcommands:

- `refresh [--require-active]`
- `preflight`
- `ensure-images`
- `once`

Examples:

```sh
sudo glab-helper --user glab-aptly gitlab-runner-managed preflight
sudo glab-helper --user glab-aptly gitlab-runner-managed once
sudo glab-helper --user glab-user gitlab-runner-managed refresh --require-active
sudo glab-helper --user glab-user gitlab-runner-managed ensure-images
```

## What the helper does

- `refresh`: renders the managed runner config
- `preflight`: validates the rootless Podman executor context, checks that the
  managed runner paths, Podman state roots, and `.runner_system_id` state file
  are owned and writable by the service user, and confirms the Podman backend
  is reachable and still rootless over `netavark`
- `ensure-images`: builds only the managed local runner images that are missing
- `once`: runs `refresh --require-active`, then `preflight`, then
  `ensure-images`, and finally starts or reloads the user service

Use `aptly-managed` for the persistent Aptly state:

```sh
sudo glab-helper --user glab-aptly aptly-managed render-config
sudo glab-helper --user glab-aptly aptly-managed publish snapshot repo-name s3:r2:
```

Direct `aptly publish ...` inside the runner container is now bridged into a
host-side queue instead of signing in-container. The `.aptly.conf` file is
owned by `aptly:aptly` with mode `0600`, and the state under
`/pool/aptly/.aptly` is reserved for that account.

The installed bridge units are:

- `aptly-bridge.path`
- `aptly-bridge.service`

## Shell-profile note

GitLab's shell profile loading guidance does not map directly to this repo's
runner path. The managed runners use the Docker executor backed by Podman, and
GitLab documents that Docker jobs are piped to `/bin/bash` inside the job
container, not to a `--login` shell. Host-side `glab-user` or `glab-aptly`
dotfiles such as `.bashrc`, `.profile`, or `.bash_logout` therefore are not
part of the normal Docker job execution path here.

Use `glab-helper` for diagnostics instead of trying to log in as the managed
user with `sudo -iu`.

## Bootstrap flow

1. Populate the token fields in `/etc/default/gitlab-runner/*.env`.
2. Populate the Aptly R2 and signing fields if the Aptly runner will publish.
3. Run `aptly-managed render-config` for `glab-aptly`.
4. Run `once` for `glab-aptly`.
5. Run `once` for `glab-user`.
6. Check service status and logs.
7. Verify `aptly-bridge.path` is active before using `aptly publish ...` from CI.

The installer stages `gitlab-runner.service` into each managed service home but
does not enable it until `once` succeeds. That keeps fresh installs from
spinning in a restart loop before tokens and `config.toml` exist. After that,
the unit restarts only on failure and uses bounded systemd start limits instead
of retrying forever.

## Failure note

If GitLab Runner reports `unable to upgrade to tcp`, that message comes from the
Docker-compatible Podman control channel used for container exec and attach. It
does not, by itself, prove a guest job network or nftables egress problem.
Run `gitlab-runner-managed preflight` first and then inspect the matching user
service journal.
