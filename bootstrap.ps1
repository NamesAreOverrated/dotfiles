# Dotfiles bootstrap — Windows
# Run as Administrator

$DOTFILES = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$KANATA_VERSION = "1.11.0"

$tools = @('starship', 'nvim')
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
    if (!(Test-Path $Src)) { Write-Host "  Skipping (src missing): $Src"; return }
    if ((Test-Path $Dst) -and ((Get-Item $Dst).LinkType -eq 'HardLink') -and ((Get-Item $Dst).Target -eq $Src)) {
        Write-Host "  OK"
        return
    }
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
    $nvimDst = "$env:LOCALAPPDATA\nvim"
    if ((Test-Path $nvimDst) -and ((Get-Item $nvimDst).LinkType -eq 'Junction') -and ((Get-Item $nvimDst).Target -eq "$DOTFILES\nvim")) {
        Write-Host "  OK"
    } else {
        Remove-Item -Recurse -Force $nvimDst -ErrorAction SilentlyContinue
        New-Item -ItemType Junction -Path $nvimDst -Target "$DOTFILES\nvim"
    }
}

$kanataExe = "kanata_windows_gui_winIOv2_x64.exe"
$kanataBin = Get-Command $kanataExe -ErrorAction SilentlyContinue

if (-not $kanataBin) {
    $localBin = "$HOME\.local\bin"
    $localKanata = "$localBin\$kanataExe"
    if (Test-Path $localKanata) {
        $kanataBin = Get-Command $localKanata
    } else {
        $url = "https://github.com/jtroo/kanata/releases/download/v$KANATA_VERSION/windows-binaries-x64.zip"
        $zipPath = "$env:TEMP\kanata.zip"
        $extractPath = "$env:TEMP\kanata_extract"
        Write-Host "  Downloading kanata v$KANATA_VERSION ..."
        Invoke-WebRequest -Uri $url -OutFile $zipPath
        Remove-Item -Recurse -Force $extractPath -ErrorAction SilentlyContinue
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $null = New-Item -Force -ItemType Directory -Path $localBin
        Copy-Item "$extractPath\$kanataExe" $localKanata -Force
        Remove-Item -Recurse -Force $extractPath
        Remove-Item $zipPath -Force
        $kanataBin = Get-Command $localKanata
        Write-Host "  Downloaded kanata v$KANATA_VERSION"
    }
}

if ($kanataBin) {
    Write-Host "Linking kanata config..."
    Link-Hard -Src "$DOTFILES\kanata\kanata.kbd" -Dst "$HOME\.config\kanata\kanata.kbd"

    Write-Host "Creating kanata scheduled task..."
    schtasks /create /tn "Kanata" /tr "`"$($kanataBin.Source)`" --cfg `"%USERPROFILE%\.config\kanata\kanata.kbd`"" /sc onlogon /delay 0000:30 /rl highest /f
}

$fontZip = "$DOTFILES\fonts\IosevkaCustom.zip"
if (Test-Path $fontZip) {
    Write-Host "Installing Iosevka Custom font..."
    $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    $null = New-Item -Force -ItemType Directory -Path $fontDir
    Expand-Archive -Path $fontZip -DestinationPath $fontDir -Force
    Copy-Item "$DOTFILES\fonts\LICENSE.md" "$fontDir\" -Force

    # Flatten: move TTFs up from any subdirectories
    Get-ChildItem "$fontDir" -Recurse -Filter "*.ttf" | Move-Item -Destination $fontDir -Force
    Get-ChildItem "$fontDir" -Directory | Remove-Item -Recurse -Force

    # Register each TTF in registry for per-user install
    Get-ChildItem "$fontDir\IosevkaCustom-*.ttf" | ForEach-Object {
        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
        $name = "{0} (TrueType)" -f $_.BaseName
        $null = New-ItemProperty -Path $regKey -Name $name -Value $_.Name -PropertyType String -Force
    }
    Write-Host "  Font installed ($( (Get-ChildItem "$fontDir\IosevkaCustom-*.ttf").Count ) variants)"
}

Write-Host "Done! Open Neovim to install plugins."
