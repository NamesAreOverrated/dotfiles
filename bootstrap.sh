#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

missing=()
for cmd in starship nvim kanata rofi foot; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

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

    echo "Installing openwith desktop entry..."
    link "$DOTFILES/local/share/applications/openwith.desktop" "$HOME/.local/share/applications/openwith.desktop"

    echo "Registering openwith as default for all MIME types..."
    count=0
    while IFS='' read -r mime; do
        current=$(xdg-mime query default "$mime" 2>/dev/null || true)
        if [[ "$current" != "openwith.desktop" ]]; then
            xdg-mime default openwith.desktop "$mime" && ((count++))
        fi
    done < <(grep "^MimeType=" "$DOTFILES/local/share/applications/openwith.desktop" | cut -d= -f2- | tr ';' '\n' | grep -v '^$')
    echo "  Registered $count MIME types (skipped already-set)"
fi

echo "Done! Open Neovim to install plugins."
