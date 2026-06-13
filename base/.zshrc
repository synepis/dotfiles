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
# git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
# git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- VI mode setup ---
bindkey -v # vi mode 
KEYTIMEOUT=20

# Load fzf keybindings and completion
source <(fzf --zsh)

# My common vim rebinding
bindkey -M viins 'jk' vi-cmd-mode
bindkey -M vicmd 'H' beginning-of-line 
bindkey -M vicmd 'L' end-of-line 

# Fix backspace in insert mode
bindkey -M viins "^?" backward-delete-char

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history

# Smart autocompletion
# Allow case-insensitive completion unless you type a capital letter
# Also handles partial completion with '-' (e.g. 'u-b' -> 'usr-bin')
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

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

# Copy paste 
# Save original widgets 
zle -A vi-yank       orig-vi-yank
zle -A vi-put-after  orig-vi-put-after

# Clipboard yank widget (uses normal vi operator motions) 
vi-yank-clipboard() {
  # Perform real vi yank (including operator-pending)
  zle orig-vi-yank

  # After the yank, the yanked text is in $CUTBUFFER
  printf "%s" "$CUTBUFFER" | wl-copy
}
zle -N vi-yank-clipboard

# Clipboard paste widget 
vi-put-after-clipboard() {
  # Paste from Wayland clipboard into CUTBUFFER
  CUTBUFFER=$(wl-paste)

  # Use normal "put after" behavior
  zle orig-vi-put-after
}
zle -N vi-put-after-clipboard

# Bind in vicmd map 
bindkey -M vicmd 'y' vi-yank-clipboard
bindkey -M vicmd 'p' vi-put-after-clipboard

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

# Samba drive
alias samba-on="sudo systemctl start smb nmb"
alias samba-off="sudo systemctl stop smb nmb"

# Golang
export PATH=$PATH:/usr/local/go/bin

# Zig
export PATH=$PATH:"$HOME/sdk/zig-x86_64-linux-0.16.0/"

# Custom for this computer
source ~/.zshrc_local

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

