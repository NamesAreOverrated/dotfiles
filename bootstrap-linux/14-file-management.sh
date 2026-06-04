if ! has rofi; then
    echo "  Skipping (rofi not found)"
    return
fi

printf "  Set up file management (termfilebrowser + openwith)? [y/N] "
read -r ans
if [[ ! "$ans" =~ ^[yY] ]]; then
    echo "  Skipping"
    return
fi

if [ -f "$DOTFILES/local/bin/termfilebrowser" ]; then
    echo "Linking termfilebrowser..."
    link "$DOTFILES/local/bin/termfilebrowser" "$HOME/.local/bin/termfilebrowser"
fi

echo "Installing openwith script and config..."
link "$DOTFILES/openwith/openwith" "$HOME/.local/bin/openwith"
link "$DOTFILES/openwith/config" "$HOME/.config/openwith/config"

echo "Installing openwith desktop entry..."
link "$DOTFILES/local/share/applications/openwith.desktop" "$HOME/.local/share/applications/openwith.desktop"

echo "Registering openwith as default for all MIME types..."
{
    echo "[Default Applications]"
    find /usr/share/mime -mindepth 2 -maxdepth 2 -name '*.xml' \
      -not -path '*/packages/*' \
    | sed 's|.*/mime/||; s|\.xml$||' \
    | sort -u \
    | awk '{printf "%s=openwith.desktop\n", $0}'
    echo "inode/x-empty=openwith.desktop"
} > "$HOME/.config/mimeapps.list"
echo "  Registered $(wc -l < "$HOME/.config/mimeapps.list") MIME types"
