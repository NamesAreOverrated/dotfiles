if [ -f "$DOTFILES/local/bin/powerctl" ]; then
    echo "Linking powerctl..."
    link "$DOTFILES/local/bin/powerctl" "$HOME/.local/bin/powerctl"
fi

if has pactl && has rofi && [ -f "$DOTFILES/local/bin/rofi-volmixer" ]; then
    echo "Linking rofi-volmixer..."
    link "$DOTFILES/local/bin/rofi-volmixer" "$HOME/.local/bin/rofi-volmixer"
fi
