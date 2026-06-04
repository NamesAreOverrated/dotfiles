if ! has waybar; then
    echo "  Skipping (waybar not found)"
    return
fi

echo "Linking waybar config..."
link "$DOTFILES/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc"
link "$DOTFILES/waybar/style.css" "$HOME/.config/waybar/style.css"
