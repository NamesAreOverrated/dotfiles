# Dotfiles bootstrap — Windows
# Run as Administrator

$DOTFILES = $PSScriptRoot

$tools = @('starship', 'nvim', 'kanata_windows_gui_winIOv2_x64.exe')
$missing = @()
foreach ($cmd in $tools) {
    if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
        $missing += $cmd
    }
}
if ($missing.Count -gt 0) {
    Write-Host "Not found: $($missing -join ', ')"
    $ans = Read-Host "Configs for missing tools will be skipped. Continue? [y/N]"
    if ($ans -notmatch '^[yY]') { exit 1 }
}

function Link-Hard {
    param($Src, $Dst)
    Remove-Item -Force $Dst -ErrorAction SilentlyContinue
    New-Item -Force -ItemType Directory -Path (Split-Path $Dst -Parent) | Out-Null
    New-Item -ItemType HardLink -Path $Dst -Target $Src
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Write-Host "Linking starship.toml..."
    Link-Hard -Src "$DOTFILES\starship.toml" -Dst "$HOME\.config\starship.toml"
}

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Write-Host "Linking nvim config..."
    Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim" -ErrorAction SilentlyContinue
    New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" -Target "$DOTFILES\nvim"
}

$kanata = Get-Command kanata_windows_gui_winIOv2_x64.exe -ErrorAction SilentlyContinue
if ($kanata) {
  Write-Host "Linking kanata config..."
  Link-Hard -Src "$DOTFILES\kanata\kanata.kbd" -Dst "$HOME\.config\kanata\kanata.kbd"

  Write-Host "Creating kanata scheduled task..."
  schtasks /create /tn "Kanata" /tr "`"$($kanata.Source)`" --cfg `"%USERPROFILE%\.config\kanata\kanata.kbd`"" /sc onlogon /delay 0000:30 /rl highest /f
}

Write-Host "Done! Open Neovim to install plugins."
