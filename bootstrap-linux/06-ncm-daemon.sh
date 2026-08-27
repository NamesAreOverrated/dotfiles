#!/usr/bin/env bash

# ── ncm-daemon binary ──
repo_install ncm-daemon socat jq pipewire

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
