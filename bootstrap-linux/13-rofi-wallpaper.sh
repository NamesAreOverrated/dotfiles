if ! has rofi; then
    echo "  Skipping (rofi not found)"
    return
fi

if [ -f "$DOTFILES/local/bin/rofi-wallpaper" ]; then
    echo "Linking rofi-wallpaper..."
    link "$DOTFILES/local/bin/rofi-wallpaper" "$HOME/.local/bin/rofi-wallpaper"
fi
link "$DOTFILES/rofi/themes/rofi-wallpaper.rasi" "$HOME/.config/rofi/themes/rofi-wallpaper.rasi"
