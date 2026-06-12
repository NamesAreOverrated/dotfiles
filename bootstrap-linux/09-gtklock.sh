if ! has gtklock; then
    echo "  Skipping (gtklock not found)"
    return
fi

echo "Generating gtklock config..."

config="$HOME/.config/gtklock/config.ini"
mkdir -p "$(dirname "$config")"

# Copy template if no config exists yet
[ -f "$config" ] || cp "$DOTFILES/gtklock/config.ini" "$config"

# Ensure [main] section header exists
grep -qFx '[main]' "$config" || sed -i '1i\[main]' "$config"

for entry in \
    "style = $DOTFILES/gtklock/style.css" \
    "layout = $DOTFILES/gtklock/layout.xml"; do
    key="${entry%% = *}"
    if grep -q "^$key = " "$config"; then
        sed -i "s|^$key = .*|$entry|" "$config"
    else
        sed -i "/^\[main\]/a\\$entry" "$config"
    fi
done
