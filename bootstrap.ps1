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

Write-Host "Linking kanata config..."
New-Item -Force -ItemType Directory -Path "$HOME\.config\kanata"
Remove-Item -Force "$HOME\.config\kanata\kanata.kbd" -ErrorAction SilentlyContinue
New-Item -ItemType HardLink -Path "$HOME\.config\kanata\kanata.kbd" -Target "$DOTFILES\kanata\kanata.kbd"

Write-Host "Creating kanata scheduled task..."
schtasks /create /tn "Kanata" /tr "kanata_windows_gui_winIOv2_x64.exe --cfg `"%USERPROFILE%\.config\kanata\kanata.kbd`"" /sc onlogon /delay 0000:30 /rl highest /f

Write-Host "Done! Open Neovim to install plugins."
