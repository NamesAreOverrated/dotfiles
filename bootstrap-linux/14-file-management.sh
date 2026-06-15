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

if has termfilebrowser; then
    echo "  termfilebrowser already installed"
else
    printf "  Download termfilebrowser binary? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        need curl || return
        mkdir -p "$HOME/.local/bin"
        if [ "$IS_MUSL" = 1 ]; then
            ASSET="termfilebrowser-musl"
        else
            ASSET="termfilebrowser-glibc"
        fi
        URL="https://github.com/NamesAreOverrated/dotfiles/releases/download/termfilebrowser-latest/$ASSET"
        echo "  Downloading $ASSET ..."
        if curl -fsSL "$URL" -o "$HOME/.local/bin/termfilebrowser"; then
            chmod +x "$HOME/.local/bin/termfilebrowser"
            echo "  Downloaded to ~/.local/bin/termfilebrowser"
        else
            echo "  Download failed — release not yet available"
            echo "  Build from source:"
            echo "    cd ~/Projects/rust-file-browser && cargo build --release"
            echo "    cp target/release/termfilebrowser ~/.local/bin/"
        fi
    fi
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
