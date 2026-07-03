# FZF colors for light terminal theme

# For standalone fzf
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--color=bg+:#d5c4a1,bg:#eeeeee,spinner:#9d0006,hl:#928374 \
--color=fg:#3c3836,header:#928374,info:#79740e,pointer:#9d0006 \
--color=marker:#9d0006,fg+:#3c3836,prompt:#9d0006,hl+:#9d0006"

# For fzf-tab (zsh completion)
zstyle ':fzf-tab:*' fzf-flags \
    '--color=bg+:#d5c4a1,spinner:#9d0006,hl:#928374' \
    '--color=fg:#3c3836,header:#928374,info:#79740e,pointer:#9d0006' \
    '--color=marker:#9d0006,fg+:#3c3836,prompt:#9d0006,hl+:#9d0006'
