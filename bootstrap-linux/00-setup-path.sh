# --- Add ~/.local/bin to PATH ---
if has fish; then
    mkdir -p "$HOME/.config/fish"
    if ! grep -q '.local/bin' "$HOME/.config/fish/config.fish" 2>/dev/null; then
        cat >> "$HOME/.config/fish/config.fish" << 'FISH_EOF'

# Add ~/.local/bin to PATH
if not contains "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end
FISH_EOF
        echo "  Added ~/.local/bin to fish config.fish PATH"
    fi
fi

# --- Add ~/.local/bin to PATH in .bash_profile (for ly-dm / login shell) ---
if ! grep -q '.local/bin' "$HOME/.bash_profile" 2>/dev/null; then
    if grep -q '^\[\[ -f ~\/\.bashrc \]\] && \. ~\/\.bashrc$' "$HOME/.bash_profile" 2>/dev/null; then
        sed -i '/^\[\[ -f ~\/\.bashrc \]\] && \. ~\/\.bashrc$/i export PATH="$HOME\/.local\/bin:$PATH"' "$HOME/.bash_profile"
    else
        cat >> "$HOME/.bash_profile" << 'EOF'

export PATH="$HOME/.local/bin:$PATH"
EOF
    fi
    echo "  Added ~/.local/bin to ~/.bash_profile PATH"
fi
