#!/usr/bin/env bash
# Sync local xbps-src templates into a void-packages checkout and build Swirl.
set -euo pipefail

VP="${1:-$HOME/void-packages}"
SRC="$(cd "$(dirname "$0")" && pwd)/srcpkgs"

if [ ! -f "$VP/xbps-src" ]; then
    echo "error: no xbps-src found in $VP (clone void-packages first)" >&2
    exit 1
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

echo "==> build (order matters)"
echo "    cd $VP"
echo "    ./xbps-src pkg wlroots-vfx"
echo "    ./xbps-src pkg swirl"
echo "    xbps-install wlroots-vfx swirl   # from hostdir/binpkgs"
