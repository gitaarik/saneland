# FZF colors for dark terminal theme

# For standalone fzf
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--color=bg+:#3c3836,bg:#000000,spinner:#fb4934,hl:#928374 \
--color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934 \
--color=marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934"

# For fzf-tab (zsh completion)
zstyle ':fzf-tab:*' fzf-flags \
    '--color=bg+:#3c3836,spinner:#fb4934,hl:#928374' \
    '--color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934' \
    '--color=marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934'
