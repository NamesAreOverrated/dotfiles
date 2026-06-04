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
terminals=()
for t in foot alacritty kitty wezterm ghostty; do
    has "$t" && terminals+=("$t")
done

case ${#terminals[@]} in
    0)
        TERMINAL="xterm"
        echo "  No supported terminal found, using: $TERMINAL"
        ;;
    1)
        TERMINAL="${terminals[0]}"
        echo "  Terminal: $TERMINAL"
        ;;
    *)
        echo "  Terminals found:"
        for i in "${!terminals[@]}"; do
            echo "    $((i+1))) ${terminals[$i]}"
        done
        while true; do
            read -rp "  Pick [1-${#terminals[@]}]: " choice || :
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#terminals[@]} )); then
                TERMINAL="${terminals[$((choice-1))]}"
                break
            fi
            echo "  Invalid choice"
        done
        ;;
esac
export TERMINAL

# --- Persist TERMINAL to ~/.bash_profile (only if fish is not the shell) ---
if ! has fish; then
    if ! grep -q '^export TERMINAL=' "$HOME/.bash_profile" 2>/dev/null; then
        cat >> "$HOME/.bash_profile" << EOF

export TERMINAL="$TERMINAL"
EOF
        echo "  Added TERMINAL=$TERMINAL to ~/.bash_profile"
    fi
fi

# --- Persist TERMINAL to fish config ---
if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q '^set -gx TERMINAL' "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << FISH_EOF

set -gx TERMINAL "$TERMINAL"
FISH_EOF
        echo "  Added TERMINAL=$TERMINAL to fish config.fish"
    fi
fi
