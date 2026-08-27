# --- Random small tools ---

if has starship; then
    echo "Linking starship.toml..."
    link "$DOTFILES/starship.toml" "$HOME/.config/starship.toml"

    if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'
eval "$(starship init bash)"
EOF
        echo "  Added starship init to ~/.bashrc"
    fi
fi

if has mako; then
    echo "Linking mako config..."
    link "$DOTFILES/mako/config" "$HOME/.config/mako/config"
else
    echo "  Skipping (mako not found)"
fi

echo "Linking AppImage installing helper..."
link "$DOTFILES/local/bin/aimg" "$HOME/.local/bin/aimg"

echo "Linking gtk themes..."
link "$DOTFILES/gtk-3.0" "$HOME/.config/gtk-3.0"
link "$DOTFILES/gtk-4.0" "$HOME/.config/gtk-4.0"

repo_install tiny-query
