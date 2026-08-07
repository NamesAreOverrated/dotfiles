if has trsh; then
    echo "  trsh already installed"
else
    printf "  Install trsh? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        need curl || return
        mkdir -p "$HOME/.local/bin"
        if [ "$IS_MUSL" = 1 ]; then
            ASSET="trsh-musl"
        else
            ASSET="trsh-glibc"
        fi
        URL="https://github.com/NamesAreOverrated/dotfiles/releases/download/trsh-latest/$ASSET"
        echo "  Downloading $ASSET ..."
        if curl -fsSL "$URL" -o "$HOME/.local/bin/trsh"; then
            chmod +x "$HOME/.local/bin/trsh"
            echo "  Downloaded to ~/.local/bin/trsh"
        else
            echo "  Download failed — release not yet available"
            echo "  Build from source:"
            echo "    cd ~/Projects/trsh && cargo build --release"
            echo "    cp target/release/trsh ~/.local/bin/"
        fi
    fi
fi

# --- trsh aliases ---
if has trsh && ! grep -q '^alias rm-list=' "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << 'EOF'

# --- trsh aliases ---
alias rm='trsh put'
alias rm-list='trsh list'
alias rm-restore='trsh restore'
alias rm-empty='trsh empty'
alias rm-purge='command rm'
EOF
    echo "  Added trsh aliases to ~/.bashrc (start a new shell or source it)"
fi
