# Interactive Bash configuration for the managed desktop account.

case $- in
  *i*) ;;
  *) return 0 ;;
esac

if [ -z "${__DEBIAN_PRESEED_PROFILE_LOADED:-}" ] && [ -r "$HOME/.profile" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.profile"
fi

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s checkwinsize cmdhist histappend

mkdir -p -- "$(dirname "$HISTFILE")" 2>/dev/null || true

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias btop='btop --utf-force'

if [ -r /usr/share/bash-completion/bash_completion ]; then
  # shellcheck disable=SC1091
  . /usr/share/bash-completion/bash_completion
elif [ -r /etc/bash_completion ]; then
  # shellcheck disable=SC1091
  . /etc/bash_completion
fi

if [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  # shellcheck disable=SC1091
  . /usr/share/doc/fzf/examples/key-bindings.bash
fi
if [ -r /usr/share/doc/fzf/examples/completion.bash ]; then
  # shellcheck disable=SC1091
  . /usr/share/doc/fzf/examples/completion.bash
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
