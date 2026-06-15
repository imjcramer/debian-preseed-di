# Interactive Zsh configuration for the managed desktop account.

[[ -o interactive ]] || return 0

if (( ${+__DEBIAN_PRESEED_ZSHRC_LOADED} )); then
  return 0
fi
typeset -g __DEBIAN_PRESEED_ZSHRC_LOADED=1

if [[ -z ${__DEBIAN_PRESEED_PROFILE_LOADED-} && -r $HOME/.profile ]]; then
  () {
    emulate -L sh
    # shellcheck disable=SC1091
    . "$HOME/.profile"
  }
fi

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

setopt append_history
setopt auto_cd
setopt complete_in_word
setopt extended_history
setopt hist_expire_dups_first
setopt hist_find_no_dups
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt inc_append_history
setopt interactive_comments
setopt no_beep
setopt prompt_subst
setopt share_history
unsetopt nomatch

zmodload zsh/complist
autoload -Uz compinit
zsh_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
if mkdir -p "$zsh_cache_dir" 2>/dev/null; then
  mkdir -p "${HISTFILE:h}" 2>/dev/null || true
  compinit -i -d "$zsh_cache_dir/zcompdump"
else
  compinit -i
fi
unset zsh_cache_dir

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' menu select
if [ -n "${LS_COLORS:-}" ]; then
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*:warnings' format '%F{red}no matches%f'
zstyle ':completion:*' squeeze-slashes true

bindkey -e
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3~' delete-char

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias btop='btop --utf-force'

if [ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  . /usr/share/doc/fzf/examples/key-bindings.zsh
fi
if [ -r /usr/share/doc/fzf/examples/completion.zsh ]; then
  . /usr/share/doc/fzf/examples/completion.zsh
fi

if [ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  . /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  PROMPT='%F{yellow}[%n]%f %F{cyan}%m%f %F{green}%~%f %# '
fi

if [ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  typeset -A ZSH_HIGHLIGHT_STYLES
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
  ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=yellow'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[function]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[command]='fg=green'
  ZSH_HIGHLIGHT_STYLES[path]='fg=blue,underline'
  . /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
