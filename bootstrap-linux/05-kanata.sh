printf "  Set up kanata keyboard remapper? [y/N] "
read -r ans
if [[ ! "$ans" =~ ^[yY] ]]; then
    echo "  Skipping kanata."
    return
fi

KANATA_VERSION="1.11.0"
KANATA_PREREQ_OK=true

# Find any installed uinput udev rule (any filename)
INSTALLED_RULE=$(grep -rl 'KERNEL=="uinput"' /etc/udev/rules.d/ /usr/lib/udev/rules.d/ 2>/dev/null | head -1) || true

# Parse group from installed rule, default "input"
KANATA_GROUP="input"
if [ -n "$INSTALLED_RULE" ]; then
    PARSED=$(sed -n 's/.*GROUP="\([^"]*\)".*/\1/p' "$INSTALLED_RULE")
    [ -n "$PARSED" ] && KANATA_GROUP="$PARSED"
fi

# ── Check 1: udev rule installed ──
if [ -z "$INSTALLED_RULE" ]; then
    KANATA_PREREQ_OK=false
    echo "  MISSING: uinput udev rule not found"
    if [ ! -f "$DOTFILES/kanata/99-uinput.rules" ]; then
        printf "  Generate 99-uinput.rules template? [y/N] "
        read -r gen_ans
        if [[ "$gen_ans" =~ ^[yY] ]]; then
            mkdir -p "$DOTFILES/kanata"
            cat > "$DOTFILES/kanata/99-uinput.rules" << 'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF
            echo "  Written to $DOTFILES/kanata/99-uinput.rules"
        fi
    fi
    if [ -f "$DOTFILES/kanata/99-uinput.rules" ]; then
        echo "    sudo cp \"$DOTFILES/kanata/99-uinput.rules\" /etc/udev/rules.d/"
    else
        echo "    echo 'KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\", OPTIONS+=\"static_node=uinput\"' | sudo tee /etc/udev/rules.d/99-uinput.rules"
    fi
    echo "    sudo udevadm control --reload-rules && sudo udevadm trigger"
    echo "    sudo modprobe uinput"
fi

# ── Check 2: group exists ──
if ! getent group "$KANATA_GROUP" >/dev/null 2>&1; then
    KANATA_PREREQ_OK=false
    echo "  MISSING: group '$KANATA_GROUP' does not exist"
    echo "    sudo groupadd \"$KANATA_GROUP\""
fi

# ── Check 3: user in group ──
if ! groups "$(whoami)" | grep -qw "$KANATA_GROUP"; then
    KANATA_PREREQ_OK=false
    echo "  MISSING: user '$(whoami)' not in group '$KANATA_GROUP'"
    echo "    sudo usermod -aG \"$KANATA_GROUP\" \"$(whoami)\""
    echo "  Then log out and back in."
fi

# ── Install / skip ──
if [ "$KANATA_PREREQ_OK" = false ]; then
    echo "  Skipping kanata."
    return
fi

KANATA_BIN=""
if has kanata; then
    KANATA_BIN="$(command -v kanata)"
elif [ -x "$HOME/.local/bin/kanata" ]; then
    KANATA_BIN="$HOME/.local/bin/kanata"
elif need curl && need unzip && true; then
    if [ "$IS_MUSL" = 1 ]; then
        echo "  Musl detected — kanata binary requires glibc"
        echo "    Install: sudo xbps-install kanata"
        echo "    Or build: cargo install kanata --root ~/.local"
    else
        printf "  Install kanata v%s? [y/N] " "$KANATA_VERSION"
        read -r ans2
        if [[ "$ans2" =~ ^[yY] ]]; then
            echo "  Downloading kanata v$KANATA_VERSION ..."
            TMP="$(mktemp -d)"
            curl -fsSL "https://github.com/jtroo/kanata/releases/download/v${KANATA_VERSION}/linux-binaries-x64.zip" -o "$TMP/kanata.zip"
            unzip -j "$TMP/kanata.zip" "kanata_linux_x64" -d "$TMP" >/dev/null
            mkdir -p "$HOME/.local/bin"
            mv "$TMP/kanata_linux_x64" "$HOME/.local/bin/kanata"
            chmod +x "$HOME/.local/bin/kanata"
            rm -rf "$TMP"
            KANATA_BIN="$HOME/.local/bin/kanata"
            echo "  Downloaded kanata v$KANATA_VERSION"
        else
            echo "  Skipped"
        fi
    fi
else
    echo "  Skipping kanata — not found and cannot download"
fi

if [ -n "$KANATA_BIN" ]; then
    echo "Linking kanata config..."
    link "$DOTFILES/kanata/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"
    if has systemctl; then
        echo "Generating kanata systemd service..."
        mkdir -p "$HOME/.config/systemd/user"
        rm -f "$HOME/.config/systemd/user/kanata.service"
        cat > "$HOME/.config/systemd/user/kanata.service" << EOF
[Unit]
Description=Kanata keyboard remapper
Documentation=https://github.com/jtroo/kanata
After=graphical-session.target

[Service]
Type=simple
ExecStart=$KANATA_BIN --cfg %h/.config/kanata/kanata.kbd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload || true
        if systemctl --user is-enabled kanata.service &>/dev/null; then
            systemctl --user restart kanata.service
            echo "  kanata service restarted"
        else
            systemctl --user enable --now kanata.service
            echo "  kanata service enabled and started"
        fi
    fi
fi
