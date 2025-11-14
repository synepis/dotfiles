HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history
setopt share_history hist_ignore_dups

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.
eval "$(starship init zsh)"

# Editor
export EDITOR=nvim
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^E' edit-command-line

# Plugins
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# bindkey -e   # Emacs mode (or bindkey -v for Vi mode)
bindkey -v # vi mode 
KEYTIMEOUT=20

# My common vim rebinding
bindkey -M viins 'jk' vi-cmd-mode
bindkey -M vicmd 'H' beginning-of-line 
bindkey -M vicmd 'L' end-of-line 

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history

# For ease of autocompletion
bindkey -M viins '^L' autosuggest-accept   # insert mode
bindkey -M vicmd '^L' autosuggest-accept   # command mode

# Change cursor shape for different vi modes.
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias vim='nvim'

# Git
alias gs="git status"
alias gp="git pull"
alias gpush="git push"
alias gaa="git add -A"
alias gc="git commit"
alias gcm="git commit -am"
alias gco="git checkout"

#Docker
alias dup="docker-compose up"
alias ddown="docker-compose down -v"

# Golang
export PATH=$PATH:/usr/local/go/bin

# Enable Vertex AI integration
export CLAUDE_CODE_USE_VERTEX=1
export CLOUD_ML_REGION=europe-west1
export ANTHROPIC_VERTEX_PROJECT_ID=vanta-staging
export VERTEX_REGION_CLAUDE_4_0_SONNET=europe-west1
export ANTHROPIC_MODEL='claude-sonnet-4-5@20250929' # latest 4.5

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

