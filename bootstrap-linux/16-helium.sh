#!/usr/bin/env bash
# 16-helium.sh — Helium browser installation

if has helium; then
    echo "  Helium already found"
    return
fi

printf "  Install Helium browser? [y/N] "
read -r ans
[[ ! "$ans" =~ ^[yY] ]] && { echo "  Skipping"; return; }

if ! has curl || ! has tar; then
    echo "  Skipping (curl or tar not found)"
    return
fi

echo "  Fetching latest release info..."
LATEST=$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest \
    | grep '"tag_name":' | sed 's/.*"v\?\(.*\)".*/\1/') || true
LATEST="${LATEST:-0.12.5.1}"

echo "  Downloading Helium v$LATEST ..."
TMP="$(mktemp -d)"
URL="https://github.com/imputnet/helium-linux/releases/download/$LATEST"
curl -fsSL "$URL/helium-${LATEST}-x86_64_linux.tar.xz" -o "$TMP/helium.tar.xz"

mkdir -p "$HOME/.local/share/helium"
tar -xaf "$TMP/helium.tar.xz" -C "$HOME/.local/share/helium" --strip-components=1

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/helium" << 'WRAPPER'
#!/bin/sh
nohup "$HOME/.local/share/helium/helium-wrapper" "$@" >/dev/null 2>&1 &
WRAPPER
chmod +x "$HOME/.local/bin/helium"

cp "$HOME/.local/share/helium/helium.desktop" "$HOME/.local/share/applications/helium.desktop"

if [ -f "$HOME/.local/share/helium/product_logo_256.png" ]; then
    mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
    cp "$HOME/.local/share/helium/product_logo_256.png" \
       "$HOME/.local/share/icons/hicolor/256x256/apps/helium.png"
fi

if has update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

rm -rf "$TMP"
echo "  Helium v$LATEST installed"
