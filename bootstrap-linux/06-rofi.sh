if ! has rofi; then
    echo "  Skipping (rofi not found)"
    return
fi

echo "Linking rofi config..."
link "$DOTFILES/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
link "$DOTFILES/rofi/themes/catppuccin-mocha.rasi" "$HOME/.config/rofi/themes/catppuccin-mocha.rasi"
