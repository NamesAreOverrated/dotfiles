if ! has starship; then
    echo "  Skipping (starship not found)"
    return
fi

echo "Linking starship.toml..."
link "$DOTFILES/starship.toml" "$HOME/.config/starship.toml"


if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" << 'EOF'
eval "$(starship init bash)"
EOF
    echo "  Added starship init to ~/.bashrc"
fi
