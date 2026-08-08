#!/usr/bin/env bash
# Dotfiles bootstrap — Linux
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

has() { command -v "$1" &>/dev/null; }

IS_MUSL=0
if ldd --version 2>&1 | grep -qi musl; then
    IS_MUSL=1
elif readelf -l /bin/sh 2>/dev/null | grep -qi musl; then
    IS_MUSL=1
elif [ -f /lib/ld-musl-x86_64.so.1 ] || [ -f /lib/ld-musl-aarch64.so.1 ]; then
    IS_MUSL=1
fi

need() {
    local cmd=$1 pkg=${2:-$1}
    if ! has "$cmd"; then
        echo "  MISSING: $cmd"
        if has pacman; then
            echo "    Install: sudo pacman -S $pkg"
        elif has xbps-install; then
            echo "    Install: sudo xbps-install $pkg"
        elif has apt; then
            echo "    Install: sudo apt install $pkg"
        elif has dnf; then
            echo "    Install: sudo dnf install $pkg"
        fi
        return 1
    fi
}

link() {
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { echo "  Skipping (src missing): $src"; return; }
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        echo "  OK  $(basename "$dst")"
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

cat << EOF

── Post-install notes ──

1. Start a new shell or source ~/.bashrc to pick up TERMINAL,
   SUDO_EDITOR, starship, proxy config, and PATH changes.

2. Non-systemd systems (runit, openrc, etc.):
   Add to /etc/sudoers for waybar power controls:
     $(whoami) ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot

3. If using cm-network proxy:
   Add to /etc/sudoers to preserve proxy env vars:
     Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
                           no_proxy NO_PROXY all_proxy ALL_PROXY"

4. For ncm-daemon on non-systemd system:
   Add to ~/.config/sway/local/custom.g:
     env PIPEWIRE_LATENCY 2048/48000
     exec pipewire
     exec pipewire-pulse
     exec wireplumber
     exec ncm-daemon daemon
     exec fcitx5
     exec mako

   (Or run them before sway via your init/session manager.)

EOF
