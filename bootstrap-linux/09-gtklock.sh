if ! has gtklock; then
    echo "  Skipping (gtklock not found)"
    return
fi

echo "Linking gtklock config..."
link "$DOTFILES/gtklock/config.ini" "$HOME/.config/gtklock/config.ini"
link "$DOTFILES/gtklock/style.css" "$HOME/.config/gtklock/style.css"
link "$DOTFILES/gtklock/layout.xml" "$HOME/.config/gtklock/layout.xml"
