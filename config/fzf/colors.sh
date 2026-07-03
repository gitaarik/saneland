# FZF colors - reads theme from shared state file
# This file is sourced by zsh, so we can use shell logic

_current_theme="dark"
if [[ -f ~/.cache/current-theme ]]; then
    _current_theme=$(cat ~/.cache/current-theme)
fi

if [[ "$_current_theme" == "light" ]]; then
    # Light theme colors
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--color=bg+:#d5c4a1,bg:#eeeeee,spinner:#9d0006,hl:#928374 \
--color=fg:#3c3836,header:#928374,info:#79740e,pointer:#9d0006 \
--color=marker:#9d0006,fg+:#3c3836,prompt:#9d0006,hl+:#9d0006"

    zstyle ':fzf-tab:*' fzf-flags \
        '--color=bg+:#d5c4a1,spinner:#9d0006,hl:#928374' \
        '--color=fg:#3c3836,header:#928374,info:#79740e,pointer:#9d0006' \
        '--color=marker:#9d0006,fg+:#3c3836,prompt:#9d0006,hl+:#9d0006'
else
    # Dark theme colors (default)
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--color=bg+:#3c3836,bg:#000000,spinner:#fb4934,hl:#928374 \
--color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934 \
--color=marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934"

    zstyle ':fzf-tab:*' fzf-flags \
        '--color=bg+:#3c3836,spinner:#fb4934,hl:#928374' \
        '--color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934' \
        '--color=marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934'
fi

unset _current_theme
