# Dotfiles bootstrap — Windows
# Run as Administrator

$DOTFILES = "$HOME\.dotfiles"

Write-Host "Linking starship.toml..."
New-Item -Force -ItemType Directory -Path "$HOME\.config"
Remove-Item -Force "$HOME\.config\starship.toml" -ErrorAction SilentlyContinue
New-Item -ItemType HardLink -Path "$HOME\.config\starship.toml" -Target "$DOTFILES\starship.toml"

Write-Host "Linking nvim config..."
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim" -ErrorAction SilentlyContinue
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" -Target "$DOTFILES\nvim"

Write-Host "Done! Open Neovim to install plugins."
