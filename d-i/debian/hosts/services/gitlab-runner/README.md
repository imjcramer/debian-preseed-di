# GitLab Runner Service Assets

This directory defines the managed GitLab Runner install payload for the
optional `service/gitlab-runner` class.

## Staged files

The installer copies these files into the target host:

- host policy override source: `hosts/services/gitlab-runner/server.env`
- `/etc/default/gitlab-runner/gitlab-runner-shared.env`
- `/etc/default/gitlab-runner/gitlab-runner-aptly.env`
- `/etc/default/gitlab-runner/gitlab-runner-build.env`
- `/etc/default/gitlab-runner/README.md`

The shared env file sets the managed state roots:

- runner env dir: `/etc/default/gitlab-runner`
- runner state: `/data/config/runners`
- managed runner homes: `/data/services/usr`
- rootless Podman config: `/data/config/podman`
- rootless Podman state: `/pool/podman`

Runtime split:

- `/data/config/runners/<user>` holds rendered runner state such as
  `config.toml`, managed unit templates, and the dedicated job-home bind mount
  used inside containers
- `/data/services/usr/<user>` is the real managed user home and is where the
  runner service now keeps `HOME` plus `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
  `XDG_CACHE_HOME`, and `XDG_STATE_HOME` so Podman and user-systemd state stay
  coherent
- `/pool/podman/<user>` keeps persistent rootless Podman storage such as
  graphroot, imagestore, volumes, and static metadata
- `/pool/podman` remains a traversal-only parent instead of a shared devops
  work tree so rootless OCI helpers can still open user-owned graphroots even
  if a helper process does not retain supplemental groups during startup
- `/pool/podman/<user>/tmp` keeps rootless image-copy and Buildah temp on
  `/pool`
- `/run/user/<uid>/run`, `/run/user/<uid>/libpod/tmp`, and
  `/run/user/<uid>/gitlab-runner/tmp` keep runtime PID/lock/temp state on the
  designated user runtime filesystem

## Managed users

- `glab-aptly`: dedicated Aptly publishing runner
- `glab-user`: shared build runner user

The Aptly runner and the shared build runner use separate user services.
Persistent Aptly state, signing material, and the in-container Aptly/sbuild
workflows now stay on the dedicated `glab-aptly` account end to end.

These managed users are intentionally provisioned with `/usr/sbin/nologin`.
That means `sudo -iu glab-user` is expected to fail and is not the supported
operator path for this service role.

GitLab's shell documentation matters here in one narrow way: the shell-profile
loading section applies to executors that use `--login` shells, such as
`shell`, `ssh`, `parallels`, and `virtualbox`. This repo uses the Docker
executor backed by rootless Podman, and GitLab documents that Docker jobs run
through plain `/bin/bash` inside the job container rather than a login shell.
Host-side `.bashrc`, `.profile`, and `.bash_logout` for `glab-user` or
`glab-aptly` therefore are not part of the Docker job path.

## Token and secret contract

Populate the env files before or after install with valid runner auth tokens.
The helper flow does not call `gitlab-runner register`; it writes the token
into the generated `config.toml` and starts the service with that config.

For the Aptly runner, these values may be literal strings or absolute file
paths that contain the secret payload:

- `GITLAB_RUNNER_APTLY_TOKEN`
- `GITLAB_RUNNER_APTLY_R2_ACCESS_KEY_ID`
- `GITLAB_RUNNER_APTLY_R2_SECRET_ACCESS_KEY`
- `GITLAB_RUNNER_APTLY_GPG_SIGNING_KEY`
- `GITLAB_RUNNER_APTLY_GPG_SIGNING_PASSPHRASE`

The build token may also be provided as a literal value or absolute file path:

- `GITLAB_RUNNER_BUILD_TOKEN`

For the shared `glab-user` service, a blank build token disables the rendered
runner stanza and `refresh --require-active` fails closed.

## Helper commands

Use `/usr/local/sbin/glab-helper` from an admin account that has `sudo`
permission. The helper ensures the user manager is ready for user-scoped
operations, keeps Podman and `systemctl --user` bound to the managed runner
user, and runs the controlled Aptly / config-render helpers with root
privileges:

- `systemctl` user actions
- `journalctl --user`
- `podman`
- `aptly-managed`
- `gitlab-runner-managed`

Examples:

```sh
sudo glab-helper --user glab-aptly status gitlab-runner.service
sudo glab-helper --user glab-aptly start gitlab-runner.service
sudo glab-helper --user glab-aptly restart gitlab-runner.service
sudo glab-helper --user glab-aptly journalctl -u gitlab-runner.service -n 200 --no-pager
sudo glab-helper --user glab-aptly podman ps
sudo glab-helper --user glab-aptly aptly-managed publish snapshot repo-name s3:r2:
sudo glab-helper --user glab-user status gitlab-runner.service
sudo glab-helper --user glab-user journalctl -u gitlab-runner.service -n 200 --no-pager
```

## gitlab-runner-managed commands

Use `/usr/local/sbin/gitlab-runner-managed` through `glab-helper`. The
`refresh` and `once` control-plane paths are intended to run with `sudo` so the
rendered control files stay root-managed, while the runner service itself still
executes as the managed user.

Supported commands:

- `refresh [--require-active]`
- `preflight`
- `once`
- `ensure-images`

Examples:

```sh
sudo glab-helper --user glab-aptly gitlab-runner-managed preflight
sudo glab-helper --user glab-aptly gitlab-runner-managed refresh
sudo glab-helper --user glab-aptly gitlab-runner-managed once
sudo glab-helper --user glab-aptly gitlab-runner-managed ensure-images

sudo glab-helper --user glab-user gitlab-runner-managed preflight
sudo glab-helper --user glab-user gitlab-runner-managed refresh
sudo glab-helper --user glab-user gitlab-runner-managed once
```

Behavior:

- `refresh`: renders the managed `config.toml`
- `preflight`: validates the managed Podman Docker-executor context, checks the
  writable runner roots, Podman state roots, and `.runner_system_id` state
  file, and confirms the backend is still rootless over `netavark`
- `once`: runs `refresh --require-active` and then builds any missing runner
  image after a successful preflight; if the user service is inactive it starts
  it, and if the service is already active it restarts it so updated unit
  sandboxing and managed config take effect immediately. A successful `once`
  now means the user service both reached `active` and stayed active through
  the configured verification window instead of only blipping active once
- `ensure-images`: builds any missing runner image and ensures the Aptly runner
  has local `stable`, `testing`, and `unstable` unshare tarballs plus a managed
  `~/.config/sbuild/config.pl`

`refresh --require-active` fails closed when the selected runner has no token.
That is intentional and prevents starting an empty service definition.
Successful `glab-helper ... gitlab-runner-managed ...` runs also emit an
explicit success footer so interactive operators can distinguish a quiet
success from a silent no-op.

Because the managed runner users are `nologin` accounts, use `glab-helper`
instead of `sudo -iu <user>` for diagnostics and lifecycle operations.

## Aptly notes

The Aptly runner stages its container build context under `/pool/aptly` and
bind-mounts that path into the job container. Its rendered Docker-executor
config uses Podman `keep-id`, so Aptly jobs run as `glab-aptly` inside the
container instead of root. CI jobs can still run
`aptly publish ...`, but the mounted wrapper now submits that request into a
host-side queue that is processed by `aptly-bridge.path` and
`aptly-bridge.service` through the controlled host helper. The generated Aptly
config is written to:

- `/pool/aptly/.aptly.conf`

with ownership `glab-aptly:glab-aptly` and mode `0600`.

Use the controlled helper for Aptly publication and signing:

```sh
sudo glab-helper --user glab-aptly aptly-managed render-config
sudo glab-helper --user glab-aptly aptly-managed --channel stable publish snapshot repo-name
sudo glab-helper --user glab-aptly aptly-managed --channel testing publish switch testing repo-name-20260617
```

Direct container-side publish is no longer a direct signing operation. The job
submits a constrained bridge request instead. Provide either:

- `GITLAB_RUNNER_APTLY_R2_ENDPOINT_URL`
- `GITLAB_RUNNER_APTLY_R2_ACCOUNT_ID`

and also provide:

- `GITLAB_RUNNER_APTLY_R2_BUCKET_NAME`
- `GITLAB_RUNNER_APTLY_R2_ACCESS_KEY_ID`
- `GITLAB_RUNNER_APTLY_R2_SECRET_ACCESS_KEY`

The managed Aptly host path now exposes two publication channels:

- `stable`: maps to distribution `stable`, publishes to `s3:r2:`, keeps the
  current snapshot plus one older snapshot, and has no age-based expiry
- `testing`: maps to distribution `testing`, publishes to `s3:r2:`, keeps up to
  three snapshots total, and drops retired snapshots older than `14` days by
  their Aptly `CreatedAt` timestamp after the new publication is confirmed live

Inside CI, set `APTLY_CHANNEL=stable` or `APTLY_CHANNEL=testing` before calling
`aptly publish ...`. The container-side bridge now accepts `aptly publish repo`,
`aptly publish snapshot`, and `aptly publish switch`; when the target channel
already exists, the host helper automatically converts repeated snapshot
publishes into `publish switch` and repeated local-repo publishes into
`publish update`.

## Rendered state

Managed runner config is rendered under `/data/config/runners/<user>/`.

Expected config paths:

- `/data/config/runners/glab-aptly/config.toml`
- `/data/config/runners/glab-aptly/.runner_system_id`
- `/data/config/runners/glab-aptly/home/.config/sbuild/config.pl`
- `/pool/cache/aptly/tools/sbuild/stable-amd64-sbuild.tar.gz`
- `/pool/cache/aptly/tools/sbuild/unstable-amd64-sbuild.tar.gz`
- `/data/config/runners/glab-user/config.toml`
- `/data/config/runners/glab-user/.runner_system_id`

The rendered Docker-executor config targets the managed rootless Podman socket
through `[runners.docker].host`. It does not export `DOCKER_HOST` or
`CONTAINER_HOST` into job containers and does not bind-mount the Podman socket
into every job by default. It now keeps job-container temp space on a dedicated
`/tmp` volume instead of exporting the host runtime tmp path into the
container. The managed Podman user service also overrides `podman system
service` to run with `--time=0` so the API backend does not expire mid-run.
The control-plane files inside `/data/config/runners/<user>/` are rendered
root-owned with `devops` group read access, while the writable runner work and
job-home trees remain under the managed service account.

The CI publish bridge adds these host-side paths:

- `/pool/aptly/queue/requests`
- `/pool/aptly/queue/results`
- `/pool/aptly/queue/processing`
- `/pool/aptly/.managed/channels`
- `/etc/systemd/system/aptly-bridge.path`
- `/etc/systemd/system/aptly-bridge.service`

The runner user service itself now runs with `HOME=/data/services/usr/<user>`
and matching `XDG_*` roots so the rootless Podman and systemd-user config that
the installer staged under the managed account home is the same config tree the
service actually uses at runtime.

The runner systemd user unit name is always:

- `gitlab-runner.service`

The installer stages that unit into the managed service home, but intentionally
does not enable it until `gitlab-runner-managed once` has rendered a valid
config and verified at least one active token. That avoids a boot-time restart
loop on fresh installs before the runner credentials exist. After enablement,
the unit only restarts on failure and systemd stops retrying after the bounded
start-limit window instead of looping forever.

## First bootstrap checklist

1. Populate the token fields in the env files.
2. Populate Aptly R2 and GPG fields if the Aptly runner will publish.
3. Run `sudo glab-helper --user glab-aptly aptly-managed render-config`.
4. Run `sudo glab-helper --user glab-aptly gitlab-runner-managed once`.
5. Run `sudo glab-helper --user glab-user gitlab-runner-managed once`.
6. Verify service and logs:
7. Verify `systemctl status aptly-bridge.path` before using `aptly publish ...` from CI.

```sh
sudo glab-helper --user glab-aptly status gitlab-runner.service
sudo glab-helper --user glab-user status gitlab-runner.service
sudo glab-helper --user glab-aptly journalctl -u gitlab-runner.service -n 100 --no-pager
sudo glab-helper --user glab-user journalctl -u gitlab-runner.service -n 100 --no-pager
```
