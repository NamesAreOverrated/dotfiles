if ! has nvim; then
    echo "  Skipping (nvim not found)"
    return
fi

echo "Linking nvim config..."
link "$DOTFILES/nvim" "$HOME/.config/nvim"

if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q "SUDO_EDITOR" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'
set -gx SUDO_EDITOR nvim
FISH_EOF
        echo "  Added SUDO_EDITOR=nvim to ~/.config/fish/config.fish"
    fi
    if ! grep -q "EDITOR" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        echo 'set -gx EDITOR nvim' >> "$HOME/.config/fish/config.fish"
        echo "  Added EDITOR=nvim to ~/.config/fish/config.fish"
    fi
else
    if ! grep -q "SUDO_EDITOR" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'
export SUDO_EDITOR=nvim
EOF
        echo "  Added SUDO_EDITOR=nvim to ~/.bashrc"
    fi
    if ! grep -q "EDITOR" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export EDITOR=nvim' >> "$HOME/.bashrc"
        echo "  Added EDITOR=nvim to ~/.bashrc"
    fi
fi

echo "Done! Open Neovim to install plugins."
