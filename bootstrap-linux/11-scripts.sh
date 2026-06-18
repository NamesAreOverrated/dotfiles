if [ -f "$DOTFILES/local/bin/powerctl" ]; then
    echo "Linking powerctl..."
    link "$DOTFILES/local/bin/powerctl" "$HOME/.local/bin/powerctl"
fi


