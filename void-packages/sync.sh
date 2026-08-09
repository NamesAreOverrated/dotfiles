#!/usr/bin/env bash
# Sync local xbps-src templates into a void-packages checkout and build Swirl.
set -euo pipefail

VP="${1:-$HOME/void-packages}"
SRC="$(cd "$(dirname "$0")" && pwd)/srcpkgs"

if [ ! -f "$VP/xbps-src" ]; then
    if [ -d "$VP" ]; then
        echo "error: $VP exists but is not a void-packages checkout" >&2
        exit 1
    fi
    echo "==> cloning void-packages to $VP"
    git clone --depth 1 https://github.com/void-linux/void-packages "$VP"
fi

if ! ls "$VP"/masterdir*/.xbps_chroot_init >/dev/null 2>&1; then
    echo "==> bootstrapping chroot (one-time)"
    "$VP/xbps-src" binary-bootstrap
fi

echo "==> syncing templates to $VP/srcpkgs"
for pkg in wlroots-vfx swirl; do
    mkdir -p "$VP/srcpkgs/$pkg"
    cp -r "$SRC/$pkg/template" "$VP/srcpkgs/$pkg/template"
done

echo "==> ensure common/shlibs has the wlroots-vfx soname"
grep -q '^libwlroots-0.21-vfx.so ' "$VP/common/shlibs" 2>/dev/null || {
    echo "    adding: libwlroots-0.21-vfx.so wlroots-vfx-0.21.0_1"
    echo 'libwlroots-0.21-vfx.so wlroots-vfx-0.21.0_1' >> "$VP/common/shlibs"
}

echo "==> building (order matters)"
"$VP/xbps-src" pkg -E wlroots-vfx
"$VP/xbps-src" pkg -E swirl

echo "==> install (as root, from local repo)"
echo "    sudo xbps-install -R \"$VP/hostdir/binpkgs\" wlroots-vfx swirl"

