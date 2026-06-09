# --- Mod key ---
echo "Mod key:"
echo "  1) Alt (main) + Super (nested)"
echo "  2) Super/Win (main) + Alt (nested)"
while true; do
    read -rp "Pick [1/2]: " MOD_CHOICE || :
    if [[ "$MOD_CHOICE" = "1" || "$MOD_CHOICE" = "2" ]]; then
        break
    fi
    echo "  Invalid choice, pick 1 or 2"
done
export MOD_CHOICE

# --- Terminal detection ---
echo ""

# Read current persisted value
CURRENT=""
if has fish; then
    [ -f "$HOME/.config/fish/config.fish" ] && CURRENT=$(grep -m1 '^set -gx TERMINAL' "$HOME/.config/fish/config.fish" 2>/dev/null | sed 's/.*"\(.*\)"/\1/')
else
    [ -f "$HOME/.bash_profile" ] && CURRENT=$(grep -m1 '^export TERMINAL=' "$HOME/.bash_profile" 2>/dev/null | sed 's/.*=//')
fi

terminals=()
for t in foot alacritty kitty wezterm ghostty; do
    has "$t" && terminals+=("$t")
done

case ${#terminals[@]} in
    0)
        TERMINAL="${CURRENT:-xterm}"
        echo "  No supported terminal found, using: $TERMINAL"
        ;;
    *)
        echo "  Terminals found:"
        for i in "${!terminals[@]}"; do
            echo "    $((i+1))) ${terminals[$i]}"
        done
        [ -n "$CURRENT" ] && echo "    Enter) Keep $CURRENT"
        while true; do
            read -rp "  Pick [1-${#terminals[@]}]: " choice
            if [ -z "$choice" ] && [ -n "$CURRENT" ]; then
                TERMINAL="$CURRENT"; break
            elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#terminals[@]} )); then
                TERMINAL="${terminals[$((choice-1))]}"; break
            fi
            echo "  Invalid choice"
        done
        ;;
esac
export TERMINAL

# --- Persist TERMINAL ---
if has fish; then
    mkdir -p "$HOME/.config/fish"
    sed -i '/^set -gx TERMINAL/d' "$HOME/.config/fish/config.fish" 2>/dev/null || true
    printf '\nset -gx TERMINAL "%s"\n' "$TERMINAL" >> "$HOME/.config/fish/config.fish"
    echo "  TERMINAL=$TERMINAL set in fish config.fish"
else
    sed -i '/^export TERMINAL=/d' "$HOME/.bash_profile" 2>/dev/null || true
    printf '\nexport TERMINAL="%s"\n' "$TERMINAL" >> "$HOME/.bash_profile"
    echo "  TERMINAL=$TERMINAL set in ~/.bash_profile"
fi
