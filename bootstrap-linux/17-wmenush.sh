#!/usr/bin/env bash

# ── wmenush binary ──

if has wmenush; then
    echo "  wmenush already installed"
else
    printf "  Install wmenush? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        need curl || return
        mkdir -p "$HOME/.local/bin"
        if [ "$IS_MUSL" = 1 ]; then
            ASSET="wmenush-musl"
        else
            ASSET="wmenush-glibc"
        fi
        URL="https://github.com/NamesAreOverrated/wmenush/releases/download/latest/$ASSET"
        echo "  Downloading $ASSET ..."
        if curl -fsSL "$URL" -o "$HOME/.local/bin/wmenush"; then
            chmod +x "$HOME/.local/bin/wmenush"
            echo "  Downloaded to ~/.local/bin/wmenush"
        else
            echo "  Download failed — release not yet available"
            echo "  Build from source:"
            echo "    cd ~/Projects/wmenush && cargo build --release"
            echo "    cp target/release/wmenush ~/.local/bin/"
        fi
    fi
fi

# ── Theme configs ──

if [ -d "$DOTFILES/wmenush" ]; then
    mkdir -p "$HOME/.config/wmenush"
    for f in theme.toml theme-wallpaper.toml theme-launcher.toml; do
        link "$DOTFILES/wmenush/$f" "$HOME/.config/wmenush/$f"
    done
fi

# ── Wrapper scripts ──

# wm-launcher — no system dependency
link "$DOTFILES/local/bin/wm-launcher" "$HOME/.local/bin/wm-launcher"

# wm-volmixer — requires PulseAudio/PipeWire
if has pactl; then
    link "$DOTFILES/local/bin/wm-volmixer" "$HOME/.local/bin/wm-volmixer"
else
    echo "  Skipping wm-volmixer (pactl not found)"
fi

# wm-network — requires NetworkManager
if has nmcli; then
    link "$DOTFILES/local/bin/wm-network" "$HOME/.local/bin/wm-network"
else
    echo "  Skipping wm-network (nmcli not found)"
fi

# wm-wallpaper — requires swaybg
if has swaybg; then
    link "$DOTFILES/local/bin/wm-wallpaper" "$HOME/.local/bin/wm-wallpaper"
else
    echo "  Skipping wm-wallpaper (swaybg not found)"
fi

# ── Proxy config migration ──

if [ -f "$HOME/.config/rofi-network" ]; then
    if [ ! -f "$HOME/.config/wm-network" ]; then
        mv "$HOME/.config/rofi-network" "$HOME/.config/wm-network"
        echo "  Migrated ~/.config/rofi-network → ~/.config/wm-network"
    else
        rm "$HOME/.config/rofi-network"
        echo "  Removed old ~/.config/rofi-network (replaced by ~/.config/wm-network)"
    fi
fi

# Update proxy sourcing in .bashrc
if [ -f "$HOME/.bashrc" ]; then
    sed -i \
        -e 's|# Proxy config (managed by rofi-network)|# Proxy config (managed by wm-network)|' \
        -e 's|ROFI_NET_CFG="$HOME/.config/rofi-network"|PROXY_CFG="$HOME/.config/wm-network"|' \
        -e 's|if \[ -f "$ROFI_NET_CFG" \] && \[ "$(sed -n '\''2p'\'' "$ROFI_NET_CFG")" = "1" \];|if [ -f "$PROXY_CFG" ] \&\& [ "$(sed -n '\''2p'\'' "$PROXY_CFG")" = "1" ];|' \
        -e 's|PROXY="http://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|PROXY="http://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        -e 's|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$ROFI_NET_CFG")"|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$PROXY_CFG")"|' \
        -e 's|export all_proxy="socks5://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|export all_proxy="socks5://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        "$HOME/.bashrc" 2>/dev/null || true
    echo "  Updated proxy sourcing in ~/.bashrc"
fi
