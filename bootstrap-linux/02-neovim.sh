if ! has nvim; then
    echo "  Skipping (nvim not found)"
    return
fi

echo "Linking nvim config..."
link "$DOTFILES/nvim" "$HOME/.config/nvim"

# Write EDITOR vars to ~/.config/env (consumed by env script)
mkdir -p "$HOME/.config"

for var in EDITOR SUDO_EDITOR; do
    if ! grep -q "^${var}=" "$HOME/.config/env" 2>/dev/null; then
        echo "$var=nvim" >> "$HOME/.config/env"
        echo "  Added $var=nvim to ~/.config/env"
    fi
done

echo "Done! Open Neovim to install plugins."
