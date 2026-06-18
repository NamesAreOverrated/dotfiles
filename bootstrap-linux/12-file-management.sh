if has termfilebrowser; then
    echo "  termfilebrowser already installed"
else
    printf "  Install termfilebrowser? [y/N] "
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
