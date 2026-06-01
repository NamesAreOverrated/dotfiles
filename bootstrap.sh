#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$HOME/.dotfiles"

echo "Linking starship.toml..."
mkdir -p "$HOME/.config"
ln -sf "$DOTFILES/starship.toml" "$HOME/.config/starship.toml"

echo "Linking nvim config..."
rm -rf "$HOME/.config/nvim"
ln -sf "$DOTFILES/nvim" "$HOME/.config/nvim"

if [ -d "$DOTFILES/foot" ]; then
  echo "Linking foot config..."
  mkdir -p "$HOME/.config/foot"
  ln -sf "$DOTFILES/foot/foot.ini" "$HOME/.config/foot/foot.ini"
fi

echo "Linking kanata config..."
mkdir -p "$HOME/.config/kanata"
ln -sf "$DOTFILES/kanata/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

if command -v systemctl &>/dev/null; then
  echo "Linking kanata systemd service..."
  mkdir -p "$HOME/.config/systemd/user"
  ln -sf "$DOTFILES/kanata/kanata.service" "$HOME/.config/systemd/user/kanata.service"
  systemctl --user daemon-reload
  systemctl --user enable --now kanata.service
else
  echo "systemd not detected — skipping kanata service installation"
fi

echo "Linking rofi config..."
mkdir -p "$HOME/.config/rofi/themes"
ln -sf "$DOTFILES/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
ln -sf "$DOTFILES/rofi/themes/catppuccin-mocha.rasi" "$HOME/.config/rofi/themes/catppuccin-mocha.rasi"

echo "Installing openwith script and config..."
mkdir -p "$HOME/.local/bin"
ln -sf "$DOTFILES/openwith/openwith" "$HOME/.local/bin/openwith"
mkdir -p "$HOME/.config/openwith"
ln -sf "$DOTFILES/openwith/config" "$HOME/.config/openwith/config"

echo "Installing openwith desktop entry..."
mkdir -p "$HOME/.local/share/applications"
ln -sf "$DOTFILES/local/share/applications/openwith.desktop" "$HOME/.local/share/applications/openwith.desktop"

echo "Registering openwith as default for all MIME types..."
while IFS='' read -r mime; do
    xdg-mime default openwith.desktop "$mime"
done < <(grep "^MimeType=" "$DOTFILES/local/share/applications/openwith.desktop" | cut -d= -f2- | tr ';' '\n' | grep -v '^$')

echo "Done! Open Neovim to install plugins."
