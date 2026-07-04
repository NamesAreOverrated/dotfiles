#!/usr/bin/env bash

# ── ncm-daemon binary ──

if has ncm-daemon; then
    echo "  ncm-daemon already installed"
else
    printf "  Install ncm-daemon? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        need curl || return
        mkdir -p "$HOME/.local/bin"
        if [ "$IS_MUSL" = 1 ]; then
            ASSET="ncm-daemon-musl"
        else
            ASSET="ncm-daemon-glibc"
        fi
        URL="https://github.com/NamesAreOverrated/dotfiles/releases/download/ncm-daemon-latest/$ASSET"
        echo "  Downloading $ASSET ..."
        if curl -fsSL "$URL" -o "$HOME/.local/bin/ncm-daemon"; then
            chmod +x "$HOME/.local/bin/ncm-daemon"
            echo "  Downloaded to ~/.local/bin/ncm-daemon"
        else
            echo "  Download failed — release not yet available"
            echo "  Build from source:"
            echo "    git clone git@github.com:NamesAreOverrated/ncm-daemon.git ~/Projects/ncm-daemon"
            echo "    cd ~/Projects/ncm-daemon && ./build"
            echo "    cp ncm-daemon ~/.local/bin/"
        fi
    fi
fi

# ── Systemd user service ──

if has ncm-daemon && has systemctl; then
    SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    if [ -d "$SERVICE_DIR" ] && systemctl --user is-enabled ncm-daemon.service &>/dev/null; then
        echo "  ncm-daemon.service already enabled"
    else
        printf "  Enable ncm-daemon as a user service? [y/N] "
        read -r ans
        if [[ "$ans" =~ ^[yY] ]]; then
            mkdir -p "$SERVICE_DIR"
            cat > "$SERVICE_DIR/ncm-daemon.service" << 'SERVICE'
[Unit]
Description=ncm-daemon — NetEase Cloud Music daemon

[Service]
ExecStart=%h/.local/bin/ncm-daemon daemon
Restart=on-failure
RestartSec=5
Type=simple

[Install]
WantedBy=default.target
SERVICE
            systemctl --user enable ncm-daemon.service
            systemctl --user start ncm-daemon.service
            echo "  ncm-daemon.service enabled and started"
        fi
    fi
fi
