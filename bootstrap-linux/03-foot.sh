if ! has foot; then
    echo "  Skipping (foot not found)"
    return
fi

echo "Linking foot config..."
link "$DOTFILES/foot/foot.ini" "$HOME/.config/foot/foot.ini"
