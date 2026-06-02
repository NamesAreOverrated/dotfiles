# dotfiles

sway + waybar + gtklock + rofi + kanata + nvim + foot + starship + openwith.

Catppuccin Mocha throughout.

## What's inside

| Thing | Config |
|-------|--------|
| [sway](https://swaywm.org) | `sway/config` |
| [waybar](https://github.com/Alexays/Waybar) | `waybar/config.jsonc` + `style.css` |
| [gtklock](https://github.com/jovanlanik/gtklock) | `gtklock/config.ini` + `gtklock/style.css` |
| [rofi](https://github.com/davatorium/rofi) | `rofi/config.rasi` + Catppuccin theme + rofi-wallpaper theme |
| [kanata](https://github.com/jtroo/kanata) | `kanata/kanata.kbd` — keyboard remapper |
| [nvim](https://neovim.io) | `nvim/` — Catppuccin Mocha base with custom C# semantic token colors |
| [foot](https://codeberg.org/dnkl/foot) | `foot/foot.ini` |
| [starship](https://starship.rs) | `starship.toml` |
| [termfilebrowser](https://github.com/NamesAreOverrated/rust-file-browser) | `local/bin/termfilebrowser` — TUI file browser with Neovim integration |
| [openwith](https://github.com/NamesAreOverrated/openwith) | `openwith/` — universal file opener |
| rofi-volmixer | `local/bin/rofi-volmixer` — pactl-based audio volume mixer |
| wallpapers | `wallz` submodule — symlinked to `~/Pictures/wallpapers` |

## Quick start

### Linux

```bash
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
cd dotfiles
bash bootstrap.sh
```

### Windows

```powershell
# Run as Administrator
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
.\bootstrap.ps1
```

Re-running is safe — everything is idempotent.

## Bootstrap

The Linux bootstrap script (`bootstrap.sh`) does the following:

- Checks which tools are installed and skips configs for missing ones
- Prompts for Alt/Super mod key and writes to `~/.config/sway/local/mod.g`
- Symlinks all config files (starship, nvim, foot, rofi, sway, gtklock, waybar)
- Installs the afio font from `fonts/`
- Offers to download kanata v1.11.0 from GitHub releases if missing
- Generates a systemd user service for kanata using the detected binary path
- Creates machine-specific sway config in `~/.config/sway/local/`
- Symlinks wallpapers to `~/Pictures/wallpapers`
- If rofi is installed, offers to set up file management (termfilebrowser, openwith)

The Windows bootstrap (`bootstrap.ps1`) mirrors this — links configs,
installs kanata, sets up a scheduled task, installs the font, and adds
`~\.local\bin\` to the user PATH.

## Machine-specific config

Sway includes `~/.config/sway/local/` which holds anything machine-specific:

| File | Behavior |
|------|----------|
| `mod.g` | **Always regenerated.** Contains `set $mod Mod1` or `set $mod Mod4`. |
| `outputs` | Created once. Add your monitor layout here. |
| `wallpaper` | Updated by rofi-wallpaper. Never hand-edit. |
| `utilities.g` | **Always regenerated.** Auto-generated keybinds based on installed tools. |
| `custom` | Created once. Add your own binds here (brightness, media keys, etc.). |

Files marked `.g` are auto-generated and should not be hand-edited — use `custom`
instead.

## Neovim

Based on [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) with
`vim.pack` as the plugin manager.

**Colorscheme:** Catppuccin Mocha with heavily customized semantic tokens.
General token overrides cover functions (`#98c379`), strings (`#f9e2af`),
constants (`#fab387`), and parameters (`#b4befe`).

C# files get additional per-construct semantic token colors via LspAttach:

| Construct | Color |
|-----------|-------|
| Classes | `#6aa0d0` (steel blue) |
| Structs | `#89dceb` (sky) |
| Delegates | `#7ecb8e` (medium green) |
| Interfaces | `#8edbaa` (green-teal) |
| Methods | `#a6e3a1` (mint) |
| Events | `#9ece6a` (yellow-green) |
| Fields | `#eba0ac` (maroon) |
| Constants | `#fab387` (peach) |
| Namespaces | `#a9b1d6` (light gray-blue) |
| Enums | `#f5e0dc` (pale rose) |
| Type params | `#f9e2af` (yellow) |

**LSP:** C# uses `roslyn_ls` (official Microsoft Roslyn language server,
installed via Mason as `roslyn-language-server`). Other LSPs: `rust_analyzer`,
`lua_ls`, `stylua`.

**Keybinds:**
- `<C-s>` — save file
- `<leader>w` — save all buffers
- `<leader>wq` — save all and quit
- `<leader>e` / `<leader>E` — open TermFileBrowser
- `<leader>f` / `<leader>sf` — Telescope find files
- `<leader>sg` — Telescope live grep

## Sway

Mod key is `Mod1` (Alt) by default, overridden by `~/.config/sway/local/mod.g`
if you choose Super during bootstrap.

Includes a resize mode (`$mod+r`) that temporarily highlights focused windows
in red (`#f38ba8`). Exit with Enter or Escape.

Machine-specific includes at the bottom of `config`:
```
include ~/.config/sway/local/outputs
include ~/.config/sway/local/wallpaper
include ~/.config/sway/local/utilities.g
include ~/.config/sway/local/custom
```

## Kanata

[Kanata](https://github.com/jtroo/kanata) is a keyboard remapper. The config
uses CapsLock as a layer-tap: tap for Escape, hold for navigation layer
(arrow keys, home/end, pgup/pgdn). Physical Escape doubles as backtick on
tap and a media layer on hold.

If kanata isn't installed, bootstrap offers to download v1.11.0 from GitHub
releases to `~/.local/bin/`. The version is pinned — bump `KANATA_VERSION`
in the bootstrap script to update.

A systemd user service (Linux) or scheduled task (Windows) is generated
at bootstrap time using the detected binary path.

## File management

If rofi is installed, bootstrap offers to set up:

- **termfilebrowser** — TUI file browser with Neovim integration (`<leader>e`,
  `<leader>E`). Binary committed to the repo.
- **openwith** — universal file opener via rofi. Registers as the default
  handler for all MIME types.
- **rofi-volmixer** — pactl-based audio volume mixer (rofi-driven).

On Windows, termfilebrowser is silently copied to `~\.local\bin\` and the
directory is added to the user PATH.

## Theme

[Catppuccin Mocha](https://github.com/catppuccin/catppuccin) — all configs
use it. Rofi has a dedicated Catppuccin theme with an additional grid-based
theme for rofi-wallpaper. Waybar and gtklock are styled to match.
