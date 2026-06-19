#!/usr/bin/env bash
set -euo pipefail

IS_MUSL=0
if ldd --version 2>&1 | grep -qi musl; then
    IS_MUSL=1
elif readelf -l /bin/sh 2>/dev/null | grep -qi musl; then
    IS_MUSL=1
elif [ -f /lib/ld-musl-x86_64.so.1 ] || [ -f /lib/ld-musl-aarch64.so.1 ]; then
    IS_MUSL=1
fi
if [ "$IS_MUSL" = 1 ]; then
    SUFFIX="musl"
else
    SUFFIX="glibc"
fi

declare -a names=()
declare -a paths=()

add_target() {
    local name="$1" path="$2"
    if [ -f "$path" ]; then
        names+=("$name")
        paths+=("$path")
    fi
}

add_target "wmenush"        ~/.local/bin/wmenush
add_target "termfilebrowser" ~/.local/bin/termfilebrowser
add_target "niri"           /usr/bin/niri

if [ ${#names[@]} -eq 0 ]; then
    echo "No binaries found."
    exit 1
fi

echo "Available:"
for i in "${!names[@]}"; do
    echo "  $((i+1))) ${names[$i]}"
done

read -rp "Pick (number) or 'a' for all: " choice

selected=()
if [ "$choice" = "a" ]; then
    selected=( "${!names[@]}" )
elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )); then
    selected=( $((choice-1)) )
else
    echo "Invalid"; exit 1
fi

for i in "${selected[@]}"; do
    dst="/tmp/${names[$i]}-$SUFFIX"
    cp "${paths[$i]}" "$dst"
    echo "  $dst"
    gh release create "${names[$i]}-latest" --title "${names[$i]} latest" --notes "" \
        --repo NamesAreOverrated/dotfiles 2>/dev/null || true
    gh release upload "${names[$i]}-latest" "$dst" \
        --clobber --repo NamesAreOverrated/dotfiles
done
