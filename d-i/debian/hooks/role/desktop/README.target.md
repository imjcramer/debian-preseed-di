Desktop-specific target assets belong here when a class helper needs files that
must not apply to server installs. Shared target assets stay under
`hooks/shared/target/`. Mirror the installed path directly under `target/`,
for example `target/etc/...` or `target/usr/local/...`.

The desktop role stages Labwc session assets, Waybar/Wofi/Mako/Kanshi user
defaults, Zsh/Starship/fzf/btop defaults, portal and KWallet defaults, and a
`labwc-dock` wrapper for `crystal-dock`. Waybar now uses the compositor's
native `ext/workspaces` protocol instead of a custom backend. Xwayland is
installed only as an on-demand compatibility layer; the staged Labwc
configuration must not include X11 startup assets such as `xinitrc`. Crystal
Dock reads per-desktop configuration from `~/.config/crystal-dock/labwc/`; the
role also stages the same preset under `/etc/xdg/crystal-dock/labwc/` so
Crystal Dock can copy it on first run when a home directory does not already
contain a dock configuration. The managed `labwc-output-refresh` helper
serializes output changes and re-seats session chrome after real topology
changes so Waybar and Crystal Dock stay aligned across hotplug and resume.
