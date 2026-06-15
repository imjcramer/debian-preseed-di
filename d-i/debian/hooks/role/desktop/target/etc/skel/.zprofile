# Zsh login profile. Shared shell state belongs in ~/.profile.

if [ -z "${__DEBIAN_PRESEED_PROFILE_LOADED:-}" ] && [ -r "$HOME/.profile" ]; then
  () {
    emulate -L sh
    # shellcheck disable=SC1091
    . "$HOME/.profile"
  }
fi
