# Bash login profile. Shared shell state belongs in ~/.profile.

if [ -z "${__DEBIAN_PRESEED_PROFILE_LOADED:-}" ] && [ -r "$HOME/.profile" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.profile"
fi

case $- in
  *i*)
    if [ -r "$HOME/.bashrc" ]; then
      # shellcheck disable=SC1091
      . "$HOME/.bashrc"
    fi
    ;;
esac
