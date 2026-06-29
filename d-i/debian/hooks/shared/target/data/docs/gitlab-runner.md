# GitLab runner helper guide

This guide is staged only when the `service/gitlab-runner` class is selected.

## Managed users

- `glab-aptly`: dedicated Aptly publishing runner
- `glab-user`: shared build runner user
- `glab-bazel`: dedicated Bazel + BuildBuddy runner user

These managed users intentionally use `/usr/sbin/nologin`. `sudo -iu glab-user`,
`sudo -iu glab-bazel`, or `sudo -iu glab-aptly` is expected to fail and is not
the supported debugging path.

Persistent Podman storage for those runners stays under `/pool/podman/<user>`.
The shared `/pool/podman` parent stays traversal-only so rootless OCI helpers
can still reach those per-user graphroots even if they momentarily lose
supplemental groups during container startup. Rootless Podman image-copy temp
and Buildah temp stay under `/pool/podman/<user>/tmp`, while runtime PID/lock
state stays under `/run/user/<uid>/run`, `/run/user/<uid>/libpod/tmp`, and
`/run/user/<uid>/gitlab-runner/tmp`.

## Managed files

- `/etc/default/gitlab-runner/gitlab-runner-shared.env`
- `/etc/default/gitlab-runner/gitlab-runner-aptly.env`
- `/etc/default/gitlab-runner/gitlab-runner-build.env`
- `/etc/default/gitlab-runner/gitlab-runner-bazel.env`
- `/data/config/runners/glab-aptly/config.toml`
- `/data/config/runners/glab-aptly/.runner_system_id`
- `/data/config/runners/glab-aptly/home/.config/sbuild/config.pl`
- `/pool/cache/aptly/tools/sbuild/stable-amd64-sbuild.tar.gz`
- `/pool/cache/aptly/tools/sbuild/unstable-amd64-sbuild.tar.gz`
- `/data/config/runners/glab-user/config.toml`
- `/data/config/runners/glab-user/.runner_system_id`
- `/data/config/runners/glab-bazel/config.toml`
- `/data/config/runners/glab-bazel/.runner_system_id`
- `/data/services/usr/glab-bazel/.bazelrc`
- `/data/services/usr/glab-bazel/.config/buildbuddy/auth.bazelrc`
- `/data/config/runners/glab-bazel/home/.bazelrc`
- `/data/config/runners/glab-bazel/home/.config/buildbuddy/auth.bazelrc`
- `/pool/aptly/.aptly.conf`

## Operator entrypoints

Use `glab-helper` from an admin account with `sudo` access:

```sh
sudo glab-helper --user glab-aptly status gitlab-runner.service
sudo glab-helper --user glab-user journalctl -u gitlab-runner.service -n 100 --no-pager
sudo glab-helper --user glab-user podman ps
sudo glab-helper --user glab-bazel status gitlab-runner.service
sudo glab-helper --user glab-bazel gitlab-runner-managed once
sudo glab-helper --user glab-aptly aptly-managed publish snapshot repo-name s3:r2:
```

Use `gitlab-runner-managed` through `glab-helper`. The `refresh` and `once`
control-plane paths are intended to run with `sudo` so the rendered control
files stay root-managed, while the runner service itself still executes as the
managed user.

The rendered control files inside `/data/config/runners/<user>/` stay
root-owned but use the managed runner account's primary group so the service
can read its own `config.toml` and managed user unit without depending on a
supplementary `devops` group refresh in the user manager.

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
sudo glab-helper --user glab-bazel gitlab-runner-managed refresh --require-active
```

## What the helper does

- `refresh`: renders the managed runner config
- `preflight`: validates the rootless Podman executor context, checks that the
  managed runner paths, Podman state roots, and `.runner_system_id` state file
  are owned and writable by the service user, and confirms the Podman backend
  is reachable and still rootless over `netavark`
- `ensure-images`: builds only the managed local runner images that are missing
  and prepares the Aptly runner's local `stable`/`testing`/`unstable` unshare tarballs
- `once`: runs `refresh --require-active`, then `preflight`, then
  `ensure-images`, and finally starts or restarts the user service so updated
  unit settings and rendered config take effect immediately

The Bazel runner additionally renders managed BuildBuddy auth includes into the
`glab-bazel` service home under `/data/services/usr/glab-bazel/.config/buildbuddy/auth.bazelrc`
and the runner job home under
`/data/config/runners/glab-bazel/home/.config/buildbuddy/auth.bazelrc`,
installs matching `~/.bazelrc` try-import files in both homes, and bind-mounts
the host `bazelisk` binary into both `/usr/local/bin/bazel` and
`/usr/local/bin/bazelisk` inside Bazel CI containers.

The staged `gitlab-runner` nftables service overlay keeps those Bazel jobs
usable under hardened policy by enabling host DNS/NTP/HTTP(S) egress plus
Podman bridge forwarding and masquerade. That preserves outbound access to the
BuildBuddy GRPCS endpoint and invocation results URL from inside runner job
containers.

## GitLab CI targeting

The managed tag contract is:

- Bazel jobs -> `bazel,release,internal`
- Aptly publication jobs -> `aptly,publish,internal`
- Shared build jobs -> `build,release,internal`

Minimal Bazel job:

```yaml
bazel-test:
  tags: [bazel, release, internal]
  script:
    - bazel test //...
```

Minimal Aptly publication job:

```yaml
aptly-publish-testing:
  tags: [aptly, publish, internal]
  variables:
    APTLY_CHANNEL: testing
  script:
    - aptly publish snapshot repo-name
```

Use `aptly-managed` for the persistent Aptly state:

```sh
sudo glab-helper --user glab-aptly aptly-managed render-config
sudo glab-helper --user glab-aptly aptly-managed --channel stable publish snapshot repo-name
sudo glab-helper --user glab-aptly aptly-managed --channel testing publish switch testing repo-name-20260617
sudo glab-helper --user glab-aptly aptly-managed --channel unstable publish switch unstable repo-name-20260617
```

Direct `aptly publish ...` inside the runner container is now bridged into a
host-side queue instead of signing in-container. The `.aptly.conf` file is
owned by `glab-aptly:glab-aptly` with mode `0600`, and the state under
`/pool/aptly/.aptly` stays on that same managed runner account.

Set `APTLY_CHANNEL=stable`, `APTLY_CHANNEL=testing`, or
`APTLY_CHANNEL=unstable` inside CI before calling `aptly publish ...`. The
bridge now accepts `publish repo`, `publish snapshot`, and `publish switch`,
and the host helper applies channel policy after the new publication is
confirmed live:

- `stable`: keep the live snapshot plus one older snapshot, with no age expiry
- `testing`: keep up to three snapshots total and retire older testing snapshots
  once their Aptly `CreatedAt` age exceeds `14` days
- `unstable`: keep up to four snapshots total and retire older unstable
  snapshots once their Aptly `CreatedAt` age exceeds `21` days

Retention state is tracked under `/pool/aptly/.managed/channels`.

The installed bridge units are:

- `aptly-bridge.path`
- `aptly-bridge.service`

The staged `/etc/tmpfiles.d/80-gitlab-runner-storage.conf` policy also
recreates the dedicated `/pool/build/...`, `/pool/cache/...`, `/pool/aptly/...`,
and `/pool/podman/...` service-account directories for `glab-aptly`,
`glab-user`, and `glab-bazel` on boot so runner preflight can recover cleanly
after manual cleanup.

## Shell-profile note

GitLab's shell profile loading guidance does not map directly to this repo's
runner path. The managed runners use the Docker executor backed by Podman, and
GitLab documents that Docker jobs are piped to `/bin/bash` inside the job
container, not to a `--login` shell. Host-side `glab-user`, `glab-bazel`, or
`glab-aptly` dotfiles such as `.bashrc`, `.profile`, or `.bash_logout`
therefore are not part of the normal Docker job execution path here.

Use `glab-helper` for diagnostics instead of trying to log in as the managed
user with `sudo -iu`.

## Bootstrap flow

1. Populate the token fields in `/etc/default/gitlab-runner/*.env`.
2. Populate the Aptly R2 and signing fields if the Aptly runner will publish.
3. Populate `GITLAB_RUNNER_BUILDBUDDY_API` in `gitlab-runner-bazel.env` with a writable BuildBuddy org API key.
4. Run `aptly-managed render-config` for `glab-aptly`.
5. Run `once` for `glab-aptly`.
6. Run `once` for `glab-user`.
7. Run `once` for `glab-bazel`.
8. Check service status and logs.
9. Verify `aptly-bridge.path` is active before using `aptly publish ...` from CI.

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
