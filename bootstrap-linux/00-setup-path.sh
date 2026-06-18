# --- Add ~/.local/bin to PATH in .bash_profile (for ly-dm / login shell) ---
# Interactive shells get this from env script sourced in .bashrc
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
