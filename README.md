# dotfiles

sway + waybar + swaylock + rofi + kanata + nvim + foot + starship + openwith.

Catppuccin Mocha throughout.

## What's inside

| Thing | Config |
|-------|--------|
| [sway](https://swaywm.org) | `sway/config` |
| [waybar](https://github.com/Alexays/Waybar) | `waybar/config.jsonc` + `style.css` |
| [swaylock](https://github.com/swaywm/swaylock) | `swaylock/config` |
| [rofi](https://github.com/davatorium/rofi) | `rofi/config.rasi` + Catppuccin theme + wallpaper picker theme |
| [kanata](https://github.com/jtroo/kanata) | `kanata/kanata.kbd` + systemd service / scheduled task |
| [nvim](https://neovim.io) | `nvim/` |
| [foot](https://codeberg.org/dnkl/foot) | `foot/foot.ini` |
| [starship](https://starship.rs) | `starship.toml` |
| [termfilebrowser](https://github.com/NamesAreOverrated/rust-file-browser) | `local/bin/termfilebrowser` — TUI file browser with Neovim integration |
| [openwith](https://github.com/NamesAreOverrated/openwith) | `openwith/` — universal file opener |
| [volmixer](https://github.com/NamesAreOverrated/openwith) | `openwith/volmixer` — pulse audio volume mixer |
| wallpapers | `wallz` submodule — symlinked to `~/Pictures/wallpapers` |

## Quick start

### Linux

```bash
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
cd dotfiles
bash bootstrap.sh
```

The bootstrap script will:

- Check which tools you have installed and only link configs for those
- Ask whether you want Alt or Super as the sway mod key
- Offer to download and install [kanata](https://github.com/jtroo/kanata) if it's not found
- Offer to set up file management ([termfilebrowser](https://github.com/NamesAreOverrated/rust-file-browser) + [openwith](https://github.com/NamesAreOverrated/openwith)) if rofi is installed
- Generate machine-specific sway config in `~/.config/sway/local/`
- Symlink wallpapers to `~/Pictures/wallpapers`

Re-running is safe — it's idempotent.

### Windows

```powershell
# Run as Administrator
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
.\bootstrap.ps1
```

Same deal — only configures tools you have, offers to download kanata.

## Machine-specific sway config

The bootstrap creates `~/.config/sway/local/` with four files:

| File | Behavior |
|------|----------|
| `outputs` | Created once. Add your monitor layout here. |
| `wallpaper` | Updated by the wallpaper picker. Never hand-edit. |
| `utilities.g` | **Always regenerated.** Auto-generated keybinds based on what's installed (wallpaper-picker, audio, volmixer). Do not edit. |
| `custom` | Created once. Add your own binds here (e.g. brightness, media keys). |

This keeps everything machine-specific out of the repo and lets you share the same dotfiles across machines.

## Kanata

[Kanata](https://github.com/jtroo/kanata) is a keyboard remapper. The config (`kanata.kbd`) is linked and a systemd user service (Linux) or scheduled task (Windows) is set up.

If kanata isn't installed, the bootstrap will ask before downloading v1.11.0 from GitHub releases to `~/.local/bin/`. The version is pinned to avoid breakage — bump `KANATA_VERSION` in the bootstrap script when you want to update.

## File management

If rofi is installed, the bootstrap will ask if you want to set up file management tools:

- **termfilebrowser** — a TUI file browser that integrates with Neovim (`<leader>e`, `<leader>E` to browse files). The binary is committed to the repo and copied to `~/.local/bin/`.
- **openwith** — a universal file opener using rofi. Registers as the default handler for all MIME types.
- **volmixer** — quick audio volume mixer (requires pactl).

On Windows, termfilebrowser is silently installed to `~\.local\bin\` and the directory is added to your user PATH automatically.

## Mod key

The bootstrap prompts you to choose between **Alt (Mod1)** and **Super/Win (Mod4)** for the sway mod key. The choice is written into `~/.config/sway/local/mod.g` as `set $mod Mod1` or `set $mod Mod4`. The wallpaper picker reads the `MOD_LABEL` env var (set by `utilities.g`) to show the correct key in its help text.

## Wallpapers

Wallpapers are managed as a git submodule pointing to [wallz](https://github.com/fr0st-xyz/wallz). After cloning with `--recurse-submodules`, the bootstrap symlinks them to `~/Pictures/wallpapers`.

## Theme

[Catppuccin Mocha](https://github.com/catppuccin/catppuccin) — all configs use it. Rofi has a dedicated Catppuccin theme, waybar is styled to match, and swaylock follows suit.
