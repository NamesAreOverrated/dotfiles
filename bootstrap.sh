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

echo "Done! Open Neovim to install plugins."
