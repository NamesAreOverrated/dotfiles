#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
KANATA_VERSION="1.11.0"

has() { command -v "$1" &>/dev/null; }

missing=()
for cmd in starship nvim rofi foot pactl curl sway swaylock waybar swayidle; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if ! command -v unzip &>/dev/null; then
    missing+=("unzip")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Not found: ${missing[*]}"
    echo "Configs for missing tools will be skipped."
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[yY] ]] || exit 1
fi

echo ""


link() {
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { echo "  Skipping (src missing): $src"; return; }
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        echo "  OK"
        return
    fi
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    echo "  Linked: $dst → $src"
}

if has starship; then
    echo "Linking starship.toml..."
    link "$DOTFILES/starship.toml" "$HOME/.config/starship.toml"
fi

if has nvim; then
    echo "Linking nvim config..."
    link "$DOTFILES/nvim" "$HOME/.config/nvim"
fi

if has foot && [ -d "$DOTFILES/foot" ]; then
    echo "Linking foot config..."
    link "$DOTFILES/foot/foot.ini" "$HOME/.config/foot/foot.ini"
fi

if [ -f "$DOTFILES/fonts/afio.zip" ]; then
    echo "Installing afio font..."
    FONT_DIR="$HOME/.local/share/fonts/afio"
    mkdir -p "$FONT_DIR"
    unzip -jo "$DOTFILES/fonts/afio.zip" -d "$FONT_DIR"
    cp "$DOTFILES/fonts/LICENSE-MIT" "$DOTFILES/fonts/LICENSE-APACHE" "$FONT_DIR/"
    fc-cache -fv "$FONT_DIR" &>/dev/null
    echo "  Font installed"
fi

KANATA_BIN=""
if has kanata; then
    KANATA_BIN="$(command -v kanata)"
elif [ -x "$HOME/.local/bin/kanata" ]; then
    KANATA_BIN="$HOME/.local/bin/kanata"
elif has curl && has unzip; then
    printf "  Install kanata v%s? [y/N] " "$KANATA_VERSION"
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
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
else
    echo "  Skipping kanata — not found and cannot download"
fi

if [ -n "$KANATA_BIN" ]; then
    echo "Linking kanata config..."
    link "$DOTFILES/kanata/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

    if has systemctl; then
        echo "Generating kanata systemd service..."
        mkdir -p "$HOME/.config/systemd/user"
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
        if ! systemctl --user is-enabled kanata.service &>/dev/null; then
            systemctl --user enable --now kanata.service
            echo "  kanata service enabled and started"
        else
            echo "  kanata service already enabled"
        fi
    fi
fi

if has rofi; then
    echo "Linking rofi config..."
    link "$DOTFILES/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
    link "$DOTFILES/rofi/themes/catppuccin-mocha.rasi" "$HOME/.config/rofi/themes/catppuccin-mocha.rasi"
fi

# --- wallpapers symlink (before sway so wallpaper file gets correct path) ---
if [ -d "$DOTFILES/wallpapers" ]; then
    if [ -L "$HOME/Pictures/wallpapers" ]; then
        echo "  ~/Pictures/wallpapers already a symlink — skipping"
    elif [ -d "$HOME/Pictures/wallpapers" ]; then
        echo "  Copying existing wallpapers into submodule..."
        cp -r "$HOME/Pictures/wallpapers/"* "$DOTFILES/wallpapers/"
        rm -rf "$HOME/Pictures/wallpapers"
        ln -sf "$DOTFILES/wallpapers" "$HOME/Pictures/wallpapers"
        echo "  Copied and symlinked"
    else
        mkdir -p "$HOME/Pictures"
        ln -sf "$DOTFILES/wallpapers" "$HOME/Pictures/wallpapers"
        echo "  Linked: ~/Pictures/wallpapers → dotfiles/wallpapers"
    fi
fi

# --- sway ---
if has sway; then
    echo "Linking sway config..."
    link "$DOTFILES/sway/config" "$HOME/.config/sway/config"

    mkdir -p "$HOME/.config/sway/local"

    echo "Sway \$mod key:"
    echo "  1) Alt (Mod1)"
    echo "  2) Win/Super (Mod4)"
    read -rp "Pick [1/2]: " mod_choice
    if [ "$mod_choice" = "2" ]; then
        echo "set \$mod Mod4" > "$HOME/.config/sway/local/mod.g"
    else
        echo "set \$mod Mod1" > "$HOME/.config/sway/local/mod.g"
    fi

    if ! [ -f "$HOME/.config/sway/local/outputs" ]; then
        {
            echo "# Machine-specific output configuration"
            echo "# e.g. output eDP-1 resolution 1920x1080@60Hz position 0,0"
        } > "$HOME/.config/sway/local/outputs"
        echo "  Created ~/.config/sway/local/outputs"
    fi

    if ! [ -f "$HOME/.config/sway/local/wallpaper" ]; then
        WALL="$HOME/Pictures/wallpapers/Catppuccin Mocha/01. Catppuccin Mocha.png"
        if [ -f "$WALL" ]; then
            echo "output * bg \"$WALL\" fill" > "$HOME/.config/sway/local/wallpaper"
            echo "  Created ~/.config/sway/local/wallpaper"
        else
            {
                echo "# Edit this path to set your wallpaper"
                echo "# e.g. output * bg \"$HOME/Pictures/wallpapers/...\" fill"
            } > "$HOME/.config/sway/local/wallpaper"
            echo "  Created ~/.config/sway/local/wallpaper"
        fi
    fi

    {
        echo "# Auto-generated by bootstrap — reflects currently installed packages"
        echo "# Do not edit manually; use local/custom instead"
        echo ""

        if has rofi; then
            if [ "$mod_choice" = "2" ]; then
                echo "bindsym \$mod+Shift+w exec env MOD_LABEL=Super ~/.local/bin/wallpaper-picker"
            else
                echo "bindsym \$mod+Shift+w exec ~/.local/bin/wallpaper-picker"
            fi
        fi

        if has pactl; then
            echo "bindsym --locked XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle"
            echo "bindsym --locked XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%"
            echo "bindsym --locked XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%"
            echo "bindsym --locked XF86AudioMicMute exec pactl set-source-mute @DEFAULT_SOURCE@ toggle"
            echo "bindsym \$mod+m exec pactl set-source-mute @DEFAULT_SOURCE@ toggle"

            echo "bindsym \$mod+Shift+m exec ~/.local/bin/volmixer"
        fi
    } > "$HOME/.config/sway/local/utilities.g"
    echo "  Generated ~/.config/sway/local/utilities.g"

    if ! [ -f "$HOME/.config/sway/local/custom" ]; then
        {
            echo "# Machine-specific custom keybinds -- add your own below"
            echo "# e.g. bindsym --locked XF86MonBrightnessUp exec brightnessctl set +10%"
            echo ""
            echo "seat seat0 xcursor_theme Adwaita 24"
        } > "$HOME/.config/sway/local/custom"
        echo "  Created ~/.config/sway/local/custom"
    fi
fi

if has swaylock; then
    echo "Linking swaylock config..."
    link "$DOTFILES/swaylock/config" "$HOME/.config/swaylock/config"
fi

if has waybar; then
    echo "Linking waybar config..."
    link "$DOTFILES/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc"
    link "$DOTFILES/waybar/style.css" "$HOME/.config/waybar/style.css"
fi

# --- utility scripts ---
if [ -f "$DOTFILES/local/bin/powerctl" ]; then
    echo "Linking powerctl..."
    link "$DOTFILES/local/bin/powerctl" "$HOME/.local/bin/powerctl"
fi

# --- wallpaper-picker (needs both sway and rofi) ---
if has sway && has rofi; then
    if [ -f "$DOTFILES/local/bin/wallpaper-picker" ]; then
        echo "Linking wallpaper-picker..."
        link "$DOTFILES/local/bin/wallpaper-picker" "$HOME/.local/bin/wallpaper-picker"
    fi
    link "$DOTFILES/rofi/themes/wallpaper.rasi" "$HOME/.config/rofi/themes/wallpaper.rasi"
fi

# --- file management (termfilebrowser + openwith) ---
if has rofi; then
    printf "  Set up file management (termfilebrowser + openwith)? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY] ]]; then
        if [ -f "$DOTFILES/local/bin/termfilebrowser" ]; then
            echo "Linking termfilebrowser..."
            link "$DOTFILES/local/bin/termfilebrowser" "$HOME/.local/bin/termfilebrowser"
        fi

        echo "Installing openwith script and config..."
        link "$DOTFILES/openwith/openwith" "$HOME/.local/bin/openwith"
        link "$DOTFILES/openwith/config" "$HOME/.config/openwith/config"

        if has pactl; then
            link "$DOTFILES/openwith/volmixer" "$HOME/.local/bin/volmixer"
        fi

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
    fi
fi

echo "Done! Open Neovim to install plugins."
