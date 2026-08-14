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
link "$DOTFILES/local/libexec/cm-common.sh" "$HOME/.local/libexec/cm-common.sh"

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

if has sing-box && has jq; then
    link "$DOTFILES/local/bin/cm-singbox" "$HOME/.local/bin/cm-singbox"
    echo ""
    echo "  ── cm-singbox ──"
    echo "  Start/stop will prompt for sudo interactively"
else
    echo "  Skipping cm-singbox (sing-box or jq not found)"
fi

if has swaybg; then
    link "$DOTFILES/local/libexec/set-wallpaper" "$HOME/.local/libexec/set-wallpaper"
else
    echo "  Skipping set-wallpaper (swaybg not found)"
fi

link "$DOTFILES/local/bin/cm-alias" "$HOME/.local/bin/cm-alias"

link "$DOTFILES/local/bin/config-env" "$HOME/.local/bin/config-env"

echo "Linking xdg-desktop-portal-wlr selector config..."
link "$DOTFILES/xdg-desktop-portal-wlr" "$HOME/.config/"

# ── Proxy config ──

CFG="$HOME/.config/cm-network"

# Create default proxy config if none exists
if [ ! -f "$CFG" ]; then
    mkdir -p "$HOME/.config"
    printf '%s\n0\n%s\n' "localhost:10808" "localhost,127.0.0.1,::1,.163.com,.music.126.net" > "$CFG"
    echo "  Created default proxy config (disabled)"
fi

# ── Shell env sourcing ──
# Ensure shell configs source the env script for proxy + tool vars

if ! grep -q 'config-env' "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'

eval "$(~/.local/bin/config-env)"
EOF
        echo "  Added eval \$(~/.local/bin/config-env) to ~/.bashrc"
fi


