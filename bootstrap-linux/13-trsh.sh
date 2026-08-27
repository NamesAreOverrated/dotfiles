repo_install trsh

# --- trsh aliases ---
if has trsh && ! grep -q '^alias rm-list=' "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << 'EOF'

# --- trsh aliases ---
alias rm='trsh put'
alias rm-list='trsh list'
alias rm-restore='trsh restore'
alias rm-empty='trsh empty'
alias rm-purge='command rm'
EOF
    echo "  Added trsh aliases to ~/.bashrc (start a new shell or source it)"
fi
