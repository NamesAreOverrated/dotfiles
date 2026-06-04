#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

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

for f in "$DOTFILES/bootstrap-linux/"*.sh; do
    echo "==> ${f##*/}"
    source "$f"
    echo ""
done
