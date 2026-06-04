if [ ! -f "$DOTFILES/fonts/afio.zip" ]; then
    echo "  Skipping (afio.zip not found)"
    return
fi

if ! has unzip; then
    echo "  Skipping (unzip not found)"
    return
fi

echo "Installing afio font..."
FONT_DIR="$HOME/.local/share/fonts/afio"
mkdir -p "$FONT_DIR"
unzip -jo "$DOTFILES/fonts/afio.zip" -d "$FONT_DIR"
cp "$DOTFILES/fonts/LICENSE-MIT" "$DOTFILES/fonts/LICENSE-APACHE" "$FONT_DIR/" 2>/dev/null || true
fc-cache -fv "$FONT_DIR" &>/dev/null
echo "  Font installed"
