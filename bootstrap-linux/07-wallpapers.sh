if [ ! -d "$DOTFILES/wallpapers" ]; then
    echo "  Skipping (wallpapers dir not found)"
    return
fi

if [ -L "$HOME/Pictures/wallpapers" ]; then
    echo "  ~/Pictures/wallpapers already a symlink — skipping"
elif [ -d "$HOME/Pictures/wallpapers" ]; then
    echo "  Copying existing wallpapers into submodule..."
    cp -r "$HOME/Pictures/wallpapers/"* "$DOTFILES/wallpapers/"
    rm -rf "$HOME/Pictures/wallpapers"
    ln -sf "$DOTFILES/wallpapers" "$HOME/Pictures/wallpapers"
    echo "  Copied and symlinked"
else
    mkdir -p "$HOME/Pictures"
    ln -sf "$DOTFILES/wallpapers" "$HOME/Pictures/wallpapers"
    echo "  Linked: ~/Pictures/wallpapers → dotfiles/wallpapers"
fi

# Init shared wallpaper path if not exists
if ! [ -f "$HOME/.config/wallpaper" ]; then
    WALL="$HOME/Pictures/wallpapers/Catppuccin Mocha/01. Catppuccin Mocha.png"
    if [ -f "$WALL" ]; then
        echo "$WALL" > "$HOME/.config/wallpaper"
        echo "  Created ~/.config/wallpaper"
    fi
fi
