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
        URL="https://github.com/NamesAreOverrated/dotfiles/releases/download/wmenush-latest/$ASSET"
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

link "$DOTFILES/local/bin/wm-launcher" "$HOME/.local/bin/wm-launcher"

if has pactl; then
    link "$DOTFILES/local/bin/wm-volmixer" "$HOME/.local/bin/wm-volmixer"
else
    echo "  Skipping wm-volmixer (pactl not found)"
fi

if has nmcli; then
    link "$DOTFILES/local/bin/wm-network" "$HOME/.local/bin/wm-network"
else
    echo "  Skipping wm-network (nmcli not found)"
fi

if has swaybg; then
    link "$DOTFILES/local/bin/wm-wallpaper" "$HOME/.local/bin/wm-wallpaper"
else
    echo "  Skipping wm-wallpaper (swaybg not found)"
fi

# ── Proxy config ──

CFG="$HOME/.config/wm-network"

# Migrate old rofi-network config
if [ -f "$HOME/.config/rofi-network" ]; then
    if [ ! -f "$CFG" ]; then
        mv "$HOME/.config/rofi-network" "$CFG"
        echo "  Migrated ~/.config/rofi-network → ~/.config/wm-network"
    else
        rm "$HOME/.config/rofi-network"
        echo "  Removed old ~/.config/rofi-network"
    fi
fi

# Create default proxy config if none exists
if [ ! -f "$CFG" ]; then
    mkdir -p "$HOME/.config"
    printf '%s\n0\n%s\n' "localhost:10808" "localhost,127.0.0.1,::1" > "$CFG"
    echo "  Created default proxy config (disabled)"
fi

# ── Shell proxy sourcing ──

if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q "Proxy config (managed by wm-network)" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'

# Proxy config (managed by wm-network)
set -l proxy_file "$HOME/.config/wm-network"
if test -f "$proxy_file"
    and test (sed -n '2p' "$proxy_file") = "1"
    set -l proxy_addr (sed -n '1p' "$proxy_file")
    set -l no_proxy_val (sed -n '3p' "$proxy_file")
    if test -n "$proxy_addr"
        set -gx http_proxy "http://$proxy_addr"
        set -gx https_proxy "http://$proxy_addr"
        set -gx HTTP_PROXY "http://$proxy_addr"
        set -gx HTTPS_PROXY "http://$proxy_addr"
        set -gx all_proxy "socks5://$proxy_addr"
        set -gx ALL_PROXY "socks5://$proxy_addr"
        if test -n "$no_proxy_val"
            set -gx no_proxy "$no_proxy_val"
        else
            set -gx no_proxy "localhost,127.0.0.1,::1"
        end
        set -gx NO_PROXY "$no_proxy"
    end
end
FISH_EOF
        echo "  Added proxy sourcing to ~/.config/fish/config.fish"
    fi
else
    # Inject bashrc proxy sourcing if not already present
    if ! grep -q "Proxy config (managed by wm-network)" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'

# Proxy config (managed by wm-network)
PROXY_CFG="$HOME/.config/wm-network"
if [ -f "$PROXY_CFG" ] && [ "$(sed -n '2p' "$PROXY_CFG")" = "1" ]; then
    PROXY="http://$(sed -n '1p' "$PROXY_CFG")"
    NO_PROXY_VAL="$(sed -n '3p' "$PROXY_CFG")"
    export http_proxy="$PROXY"
    export https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"
    export HTTPS_PROXY="$PROXY"
    export all_proxy="socks5://$(sed -n '1p' "$PROXY_CFG")"
    export ALL_PROXY="$all_proxy"
    export no_proxy="${NO_PROXY_VAL:-localhost,127.0.0.1,::1}"
    export NO_PROXY="$no_proxy"
fi
EOF
        echo "  Added proxy sourcing to ~/.bashrc"
    fi
fi

# Migrate old rofi-network variable names in bashrc (if fish user ever had rofi)
if [ -f "$HOME/.bashrc" ]; then
    sed -i \
        -e 's|# Proxy config (managed by rofi-network)|# Proxy config (managed by wm-network)|' \
        -e 's|ROFI_NET_CFG="$HOME/.config/rofi-network"|PROXY_CFG="$HOME/.config/wm-network"|' \
        -e 's|if \[ -f "$ROFI_NET_CFG" \] && \[ "$(sed -n '\''2p'\'' "$ROFI_NET_CFG")" = "1" \];|if [ -f "$PROXY_CFG" ] \&\& [ "$(sed -n '\''2p'\'' "$PROXY_CFG")" = "1" ];|' \
        -e 's|PROXY="http://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|PROXY="http://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        -e 's|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$ROFI_NET_CFG")"|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$PROXY_CFG")"|' \
        -e 's|export all_proxy="socks5://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|export all_proxy="socks5://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        "$HOME/.bashrc" 2>/dev/null || true
fi
