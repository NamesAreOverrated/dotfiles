#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

missing=()
for cmd in starship nvim kanata rofi foot pactl wpctl; do
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

has() { command -v "$1" &>/dev/null; }

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

if [ -f "$DOTFILES/fonts/IosevkaCustom.zip" ]; then
    echo "Installing Iosevka Custom font..."
    FONT_DIR="$HOME/.local/share/fonts/iosevka-custom"
    mkdir -p "$FONT_DIR"
    unzip -jo "$DOTFILES/fonts/IosevkaCustom.zip" -d "$FONT_DIR"
    cp "$DOTFILES/fonts/LICENSE.md" "$FONT_DIR/"
    fc-cache -fv "$FONT_DIR" &>/dev/null
    echo "  Font installed"
fi

if has kanata; then
    echo "Linking kanata config..."
    link "$DOTFILES/kanata/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

    if has systemctl; then
        echo "Linking kanata systemd service..."
        link "$DOTFILES/kanata/kanata.service" "$HOME/.config/systemd/user/kanata.service"
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

if has rofi; then
    echo "Installing openwith script and config..."
    link "$DOTFILES/openwith/openwith" "$HOME/.local/bin/openwith"
    link "$DOTFILES/openwith/config" "$HOME/.config/openwith/config"

    if has pactl && has wpctl; then
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

echo "Done! Open Neovim to install plugins."
