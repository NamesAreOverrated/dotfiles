if ! has starship; then
    echo "  Skipping (starship not found)"
    return
fi

echo "Linking starship.toml..."
link "$DOTFILES/starship.toml" "$HOME/.config/starship.toml"

if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q "starship init fish" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'
# Starship prompt init
starship init fish | source
FISH_EOF
        echo "  Added starship init to ~/.config/fish/config.fish"
    fi
else
    if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'
eval "$(starship init bash)"
EOF
        echo "  Added starship init to ~/.bashrc"
    fi
fi
