#!/usr/bin/env bash

# ── tiny-cmenush binary ──

if has tiny-cmenush; then
    echo "  tiny-cmenush already installed"
else
    printf "  Install tiny-cmenush? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        need curl || return
        mkdir -p "$HOME/.local/bin"
        if [ "$IS_MUSL" = 1 ]; then
            ASSET="tiny-cmenush-musl"
        else
            ASSET="tiny-cmenush-glibc"
        fi
        URL="https://github.com/NamesAreOverrated/dotfiles/releases/download/tiny-cmenush-latest/$ASSET"
        echo "  Downloading $ASSET ..."
        if curl -fsSL "$URL" -o "$HOME/.local/bin/tiny-cmenush"; then
            chmod +x "$HOME/.local/bin/tiny-cmenush"
            echo "  Downloaded to ~/.local/bin/tiny-cmenush"
        else
            echo "  Download failed — release not yet available"
            echo "  Build from source:"
            echo "    cd ~/Projects/tiny-cmenush && ./build"
            echo "    cp tiny-cmenush ~/.local/bin/"
        fi
    fi
fi

# ── Theme configs ──

if [ -d "$DOTFILES/tiny-cmenush" ]; then
    mkdir -p "$HOME/.config/tiny-cmenush"
    for f in default.theme wallpaper.theme launcher.theme media.theme; do
        link "$DOTFILES/tiny-cmenush/$f" "$HOME/.config/tiny-cmenush/$f"
    done
fi

# ── Wrapper scripts ──

link "$DOTFILES/local/bin/cm-launcher" "$HOME/.local/bin/cm-launcher"
link "$DOTFILES/local/bin/cm-image" "$HOME/.local/bin/cm-image"
link "$DOTFILES/local/bin/cm-preview" "$HOME/.local/bin/cm-preview"
link "$DOTFILES/local/bin/cm-media" "$HOME/.local/bin/cm-media"

# ── Launcher icons ──

link "$DOTFILES/local/share/cm-launcher/icons" "$HOME/.local/share/cm-launcher/icons"

if has pactl; then
    link "$DOTFILES/local/bin/cm-volmixer" "$HOME/.local/bin/cm-volmixer"
else
    echo "  Skipping cm-volmixer (pactl not found)"
fi

if has nmcli; then
    link "$DOTFILES/local/bin/cm-network" "$HOME/.local/bin/cm-network"
else
    echo "  Skipping cm-network (nmcli not found)"
fi

if has swaybg; then
    link "$DOTFILES/local/libexec/set-wallpaper" "$HOME/.local/libexec/set-wallpaper"
else
    echo "  Skipping set-wallpaper (swaybg not found)"
fi

if has fish; then
    echo "  Skipping cm-alias (bash-only tool)"
else
    link "$DOTFILES/local/bin/cm-alias" "$HOME/.local/bin/cm-alias"
fi

link "$DOTFILES/local/bin/config-env" "$HOME/.local/bin/config-env"

# ── Proxy config ──

CFG="$HOME/.config/cm-network"

# Migrate old rofi-network config
if [ -f "$HOME/.config/rofi-network" ]; then
    if [ ! -f "$CFG" ]; then
        mv "$HOME/.config/rofi-network" "$CFG"
        echo "  Migrated ~/.config/rofi-network → ~/.config/cm-network"
    else
        rm "$HOME/.config/rofi-network"
        echo "  Removed old ~/.config/rofi-network"
    fi
fi

# Migrate old tm-network config
if [ -f "$HOME/.config/tm-network" ] && [ ! -f "$CFG" ]; then
    mv "$HOME/.config/tm-network" "$CFG"
    echo "  Migrated ~/.config/tm-network → ~/.config/cm-network"
fi

# Create default proxy config if none exists
if [ ! -f "$CFG" ]; then
    mkdir -p "$HOME/.config"
    printf '%s\n0\n%s\n' "localhost:10808" "localhost,127.0.0.1,::1,.163.com,.music.126.net" > "$CFG"
    echo "  Created default proxy config (disabled)"
fi

# ── Shell env sourcing ──
# Ensure shell configs source the env script for proxy + tool vars

if has fish; then
    mkdir -p "$HOME/.config/fish"
    # Migrate old proxy block → env sourcing
    if grep -q "Proxy config (managed by tm-network)" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        sed -i '/^# Proxy config (managed by tm-network)$/,/^end$/c\~/.local/bin/config-env --fish | source' "$HOME/.config/fish/config.fish"
        echo "  Migrated proxy sourcing in ~/.config/fish/config.fish → ~/.local/bin/config-env --fish | source"
    fi
    if ! grep -q "config-env --fish | source" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'

~/.local/bin/config-env --fish | source
FISH_EOF
        echo "  Added config-env sourcing to ~/.config/fish/config.fish"
    fi
else
    # Migrate old proxy block → eval "$(~/.local/bin/config-env)"
    if grep -q "Proxy config (managed by tm-network)" "$HOME/.bashrc" 2>/dev/null; then
        sed -i '/^# Proxy config (managed by tm-network)$/,/^fi$/c\eval "$(~/.local/bin/config-env)"' "$HOME/.bashrc"
        echo "  Migrated proxy sourcing in ~/.bashrc → eval \"\$(~/.local/bin/config-env)\""
    fi
    if ! grep -q 'config-env' "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'

eval "$(~/.local/bin/config-env)"
EOF
        echo "  Added eval \$(~/.local/bin/config-env) to ~/.bashrc"
    fi
fi

# Migrate old rofi-network variable names in bashrc (if fish user ever had rofi)
if [ -f "$HOME/.bashrc" ]; then
    sed -i \
        -e 's|# Proxy config (managed by rofi-network)|# Proxy config (managed by cm-network)|' \
        -e 's|ROFI_NET_CFG="$HOME/.config/rofi-network"|PROXY_CFG="$HOME/.config/cm-network"|' \
        -e 's|if \[ -f "$ROFI_NET_CFG" \] && \[ "$(sed -n '\''2p'\'' "$ROFI_NET_CFG")" = "1" \];|if [ -f "$PROXY_CFG" ] \&\& [ "$(sed -n '\''2p'\'' "$PROXY_CFG")" = "1" ];|' \
        -e 's|PROXY="http://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|PROXY="http://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        -e 's|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$ROFI_NET_CFG")"|NO_PROXY_VAL="$(sed -n '\''3p'\'' "$PROXY_CFG")"|' \
        -e 's|export all_proxy="socks5://$(sed -n '\''1p'\'' "$ROFI_NET_CFG")"|export all_proxy="socks5://$(sed -n '\''1p'\'' "$PROXY_CFG")"|' \
        "$HOME/.bashrc" 2>/dev/null || true
fi
