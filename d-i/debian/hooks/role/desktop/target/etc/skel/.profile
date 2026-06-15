__DEBIAN_PRESEED_PROFILE_LOADED=1
export __DEBIAN_PRESEED_PROFILE_LOADED

path_prepend() {
  [ -n "${1:-}" ] || return 0
  [ -d "$1" ] || return 0
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

path_append() {
  [ -n "${1:-}" ] || return 0
  [ -d "$1" ] || return 0
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="${PATH:+$PATH:}$1" ;;
  esac
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/bin"
path_append /usr/local/sbin
path_append /usr/sbin
export PATH

export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRSX}"
export LESSHISTFILE="${LESSHISTFILE:--}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if [ -r "$XDG_CONFIG_HOME/starship.toml" ]; then
  export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml"
fi

export FZF_DEFAULT_OPTS_FILE="${FZF_DEFAULT_OPTS_FILE:-$XDG_CONFIG_HOME/fzf/default-opts}"
if [ -r "$FZF_DEFAULT_OPTS_FILE" ]; then
  FZF_DEFAULT_OPTS=$(
    sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$FZF_DEFAULT_OPTS_FILE" 2>/dev/null |
      tr '\n' ' '
  )
  export FZF_DEFAULT_OPTS
fi

__fzf_fd=
if command -v fd >/dev/null 2>&1; then
  __fzf_fd=fd
elif command -v fdfind >/dev/null 2>&1; then
  __fzf_fd=fdfind
  alias fd='fdfind'
fi
if [ -n "$__fzf_fd" ]; then
  export FZF_CTRL_T_COMMAND="${FZF_CTRL_T_COMMAND:-$__fzf_fd --hidden --follow --exclude .git .}"
  export FZF_ALT_C_COMMAND="${FZF_ALT_C_COMMAND:-$__fzf_fd --type d --hidden --follow --exclude .git .}"
else
  export FZF_CTRL_T_COMMAND="${FZF_CTRL_T_COMMAND:-find . -type f}"
  export FZF_ALT_C_COMMAND="${FZF_ALT_C_COMMAND:-find . -type d}"
fi

alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias btop='btop --utf-force'

if [ -x /usr/local/sbin/luks-mok-open ] &&
   [ -x /usr/local/sbin/luks-mok-close ] &&
   [ -x /usr/local/sbin/luks-mok-passwd ]; then
  alias luks-mok-open='sudo /usr/local/sbin/luks-mok-open'
  alias luks-mok-close='sudo /usr/local/sbin/luks-mok-close'
  alias luks-mok-passwd='sudo /usr/local/sbin/luks-mok-passwd'
fi

unset __fzf_fd
unset -f path_prepend path_append
