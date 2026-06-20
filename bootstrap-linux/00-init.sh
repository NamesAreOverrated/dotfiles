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

# Read current persisted value from canonical source
CURRENT=""
[ -f "$HOME/.config/env" ] && CURRENT=$(grep -m1 '^TERMINAL=' "$HOME/.config/env" 2>/dev/null | sed 's/.*=//;s/"//g') || true

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
mkdir -p "$HOME/.config"
if [ -f "$HOME/.config/env" ]; then
    # Update existing
    sed -i '/^TERMINAL=/d' "$HOME/.config/env"
fi
echo "TERMINAL=$TERMINAL" >> "$HOME/.config/env"
echo "  TERMINAL=$TERMINAL set in ~/.config/env"
