#!/usr/bin/env bash
if ! has nmcli; then
    echo "  Skipping (nmcli not found)"
    return
fi

# ── Proxy config initialization ──
CFG="$HOME/.config/wm-network"

if [ -f "$HOME/.config/rofi-network" ] && [ ! -f "$CFG" ]; then
    mv "$HOME/.config/rofi-network" "$CFG"
    echo "  Migrated ~/.config/rofi-network → ~/.config/wm-network"
elif [ -f "$HOME/.config/rofi-network" ] && [ -f "$CFG" ]; then
    rm "$HOME/.config/rofi-network"
    echo "  Removed old ~/.config/rofi-network"
fi

if [ ! -f "$CFG" ]; then
    mkdir -p "$HOME/.config"
    printf '%s\n0\n%s\n' "localhost:10808" "localhost,127.0.0.1,::1" > "$CFG"
    echo "  Created default proxy config (disabled)"
fi

# ── Fish proxy sourcing ──
if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q "Proxy config (managed by wm-network)" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'

# Proxy config (managed by wm-network)
set -l proxy_file "$HOME/.config/wm-network"
if test -f "$proxy_file"
    and test (sed -n '2p' "$proxy_file") = "1"
    set -l proxy_addr (sed -n '1p' "$proxy_file")
    set -l no_proxy_val (sed -n '3p' "$proxy_file")
    if test -n "$proxy_addr"
        set -gx http_proxy "http://$proxy_addr"
        set -gx https_proxy "http://$proxy_addr"
        set -gx HTTP_PROXY "http://$proxy_addr"
        set -gx HTTPS_PROXY "http://$proxy_addr"
        set -gx all_proxy "socks5://$proxy_addr"
        set -gx ALL_PROXY "socks5://$proxy_addr"
        if test -n "$no_proxy_val"
            set -gx no_proxy "$no_proxy_val"
        else
            set -gx no_proxy "localhost,127.0.0.1,::1"
        end
        set -gx NO_PROXY "$no_proxy"
    end
end
FISH_EOF
        echo "  Added proxy sourcing to ~/.config/fish/config.fish"
    fi
fi
