if [ -f "$DOTFILES/fonts/afio.zip" ]; then
    need unzip || return

    echo "Installing afio font..."
    FONT_DIR="$HOME/.local/share/fonts/afio"
    mkdir -p "$FONT_DIR"
    unzip -jo "$DOTFILES/fonts/afio.zip" -d "$FONT_DIR"
    cp "$DOTFILES/fonts/LICENSE-MIT" "$DOTFILES/fonts/LICENSE-APACHE" "$FONT_DIR/" 2>/dev/null || true
    fc-cache -fv "$FONT_DIR" &>/dev/null
    echo "  Font installed"
else
    echo "  Skipping fonts (afio.zip not found)"
fi

echo "Installing Graphite cursor theme..."
CURSOR_SRC="$DOTFILES/local/share/icons/Graphite-dark-mocha"
if [ -d "$CURSOR_SRC" ]; then
    mkdir -p "$HOME/.local/share/icons"
    cp -r "$CURSOR_SRC" "$HOME/.local/share/icons/"
    echo "  Cursor theme installed"
fi
