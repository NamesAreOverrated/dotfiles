if ! has nmcli || ! has rofi; then
    echo "  Skipping (nmcli or rofi not found)"
    return
fi

if [ ! -f "$DOTFILES/local/bin/rofi-network" ]; then
    echo "  Skipping (rofi-network script not found)"
    return
fi

echo "Linking rofi-network..."
link "$DOTFILES/local/bin/rofi-network" "$HOME/.local/bin/rofi-network"

# ── Proxy migration + sourcing ──

# Extract old hardcoded proxy from .bashrc (if any)
OLD_PROXY=$(grep -m1 '^export http_proxy=' "$HOME/.bashrc" 2>/dev/null | sed 's|^export http_proxy=http://||') || true
OLD_HOST=""
OLD_PORT=""
if [ -n "$OLD_PROXY" ]; then
    OLD_HOST="${OLD_PROXY%:*}"
    OLD_PORT="${OLD_PROXY#*:}"
    [[ "$OLD_PORT" == "$OLD_HOST" ]] && OLD_PORT="10808"
fi

OLD_NO_PROXY=$(grep -m1 '^export no_proxy=' "$HOME/.bashrc" 2>/dev/null | sed 's/^export no_proxy=//') || true

# Remove old hardcoded proxy block from .bashrc
sed -i \
  -e '/^export http_proxy=http:\/\//d' \
  -e '/^export https_proxy=http:\/\//d' \
  -e '/^export HTTP_PROXY=/d' \
  -e '/^export HTTPS_PROXY=/d' \
  -e '/^export all_proxy=/d' \
  -e '/^export ALL_PROXY=/d' \
  -e '/^export no_proxy=/d' \
  -e '/^export NO_PROXY=/d' \
  "$HOME/.bashrc" 2>/dev/null || true

# Clean up old split-file proxy config
if [ -f "$HOME/.config/proxy/config" ] || [ -f "$HOME/.config/proxy/state" ]; then
    rm -rf "$HOME/.config/proxy"
    echo "  Removed old ~/.config/proxy/ (migrated to single ~/.config/rofi-network)"
fi

# ── Pre-populate ~/.config/rofi-network ──
mkdir -p "$HOME/.config"
needs_generation=false
if [ ! -f "$HOME/.config/rofi-network" ]; then
    needs_generation=true
else
    STATE=$(sed -n '2p' "$HOME/.config/rofi-network")
    if [ "$(wc -l < "$HOME/.config/rofi-network")" -lt 3 ] || { [ "$STATE" != "0" ] && [ "$STATE" != "1" ]; }; then
        echo "  rofi-network config corrupted, regenerating..."
        needs_generation=true
    fi
fi

if [ "$needs_generation" = true ]; then
    if [ -n "$OLD_HOST" ]; then
        printf '%s:%s\n1\n%s\n' "$OLD_HOST" "$OLD_PORT" "${OLD_NO_PROXY:-localhost,127.0.0.1,::1}" > "$HOME/.config/rofi-network"
        echo "  Migrated proxy: $OLD_HOST:$OLD_PORT (enabled)"
    else
        printf '%s\n0\n%s\n' "localhost:10808" "localhost,127.0.0.1,::1" > "$HOME/.config/rofi-network"
        echo "  Created default proxy config (disabled)"
    fi
fi

# ── Proxy sourcing (gated by shell) ──
if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q "Proxy config (managed by rofi-network)" "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'

# Proxy config (managed by rofi-network)
set -l proxy_file "$HOME/.config/rofi-network"
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
else
    if ! grep -q "Proxy config (managed by rofi-network)" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" << 'EOF'

# Proxy config (managed by rofi-network)
ROFI_NET_CFG="$HOME/.config/rofi-network"
if [ -f "$ROFI_NET_CFG" ] && [ "$(sed -n '2p' "$ROFI_NET_CFG")" = "1" ]; then
    PROXY="http://$(sed -n '1p' "$ROFI_NET_CFG")"
    NO_PROXY_VAL="$(sed -n '3p' "$ROFI_NET_CFG")"
    export http_proxy="$PROXY"
    export https_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"
    export HTTPS_PROXY="$PROXY"
    export all_proxy="socks5://$(sed -n '1p' "$ROFI_NET_CFG")"
    export ALL_PROXY="$all_proxy"
    export no_proxy="${NO_PROXY_VAL:-localhost,127.0.0.1,::1}"
    export NO_PROXY="$no_proxy"
fi
EOF
        echo "  Added proxy sourcing to ~/.bashrc"
    fi
fi
