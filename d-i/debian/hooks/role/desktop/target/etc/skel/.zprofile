# Zsh login profile. Shared shell state belongs in ~/.profile.

if [ -r "$HOME/.profile" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.profile"
fi
