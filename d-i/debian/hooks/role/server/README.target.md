Server-specific target assets belong here when a class helper needs files that
must not apply to desktop installs. Shared target assets stay under
`hooks/shared/target/`. Mirror the installed path directly under `target/`,
for example `target/etc/...` or `target/usr/local/...`.
