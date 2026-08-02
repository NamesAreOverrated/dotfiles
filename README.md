# dotfiles

sway + waybar + gtklock + tiny-cmenush + kanata + nvim + foot + starship.
Catppuccin Mocha throughout.

## What's inside

| Thing | Config |
|-------|--------|
| [sway](https://swaywm.org) | `sway/config` — Mod key auto-detected (Alt/Super) |
| [waybar](https://github.com/Alexays/Waybar) | `waybar/config.jsonc` + `style.css` |
| [gtklock](https://github.com/jovanlanik/gtklock) | `gtklock/config.ini` + `style.css` + `layout.xml` |
| tiny-cmenush | Overlay menu (rofi replacement). Companion scripts: `cm-launcher`, `cm-media`, `cm-network`, `cm-volmixer`, `cm-alias`, `cm-singbox`, `cm-image`, `cm-preview`, `cm-swirl`, `set-wallpaper`, `powerctl` |
| [kanata](https://github.com/jtroo/kanata) | `kanata/kanata.kbd` — CapsLock layer-tap keyboard remapper |
| [nvim](https://neovim.io) | `nvim/` — Catppuccin Mocha base with custom C# semantic token colors |
| [foot](https://codeberg.org/dnkl/foot) | `foot/foot.ini` |
| [starship](https://starship.rs) | `starship.toml` |
| termfilebrowser | TUI file browser, auto-installed via bootstrap |

| wallpapers | `wallz` submodule — symlinked to `~/Pictures/wallpapers` |

Old rofi scripts and configs remain in the repo but are no longer linked.

## Quick start

```bash
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
cd dotfiles
bash bootstrap.sh
```

Re-running is safe — everything is idempotent.

## Bootstrap

The bootstrap script sources every `.sh` in `bootstrap-linux/` in order:

1. **Init** — prompts for mod key (Alt/Super) and terminal emulator
2. **Paths** — ensures `~/.local/bin` is in PATH for login shells
3. **Config linking** — symlinks starship, nvim, foot, sway, gtklock, waybar
4. **Kanata** — offers to download from GitHub if missing, generates systemd service
5. **Tiny-cmenush** — offers to download from GitHub if missing, links theme configs + companion scripts (dep-gated: cm-volmixer needs pactl, cm-network needs nmcli, cm-singbox needs sing-box + jq, set-wallpaper needs swaybg; cm-alias bash-only skips on fish systems)
6. **Wallpapers** — symlinks wallz submodule to `~/Pictures/wallpapers`
7. **WM configs** — generates machine-specific sway configs (outputs, wallpaper, keybinds)
8. **File management** — offers to install termfilebrowser from GitHub
9. **Proxy** — migrates old `~/.config/rofi-network` → `~/.config/cm-network`, sets up shell sourcing

Each script checks which tools are actually installed and skips configs for missing ones. `cm-swirl` and `powerctl` are linked by the sway step.

## Machine-specific config

In sway, `~/.config/sway/local/` holds anything machine-specific:

| File | Behavior |
|------|----------|
| `mod.g` | **Always regenerated.** Contains `set $mod Mod1` or `set $mod Mod4`. |
| `outputs` | Created once. Add your monitor layout here. |
| `wallpaper` | Updated by set-wallpaper. Never hand-edit. |
| `utilities.g` | **Always regenerated.** Auto-generated keybinds based on installed tools. |
| `custom` | Created once. Add your own binds here (brightness, media keys, etc.). |

## tiny-cmenush

tiny-cmenush is a Wayland-native overlay menu that reads items from stdin and
outputs the selection to stdout. It replaces `rofi -dmenu` across all scripts.

The bootstrap installs these companion scripts:

| Script | Depends on | Description |
|--------|-----------|-------------|
| `cm-launcher` | — | Desktop launcher — parses `.desktop` files with icon resolution |
| `cm-media` | tiny-cmenush, gdbus, socat, jq | Media controller — MPRIS transport controls + NetEase Cloud Music frontend (QR login, search, playlists, local files, FM, queue, like/trash) over the `ncm-daemon` socket |
| `cm-volmixer` | pactl | Audio sink/source/app volume and mute control |
| `cm-network` | nmcli | Network manager — WiFi scan/connect, proxy config |
| `cm-singbox` | sing-box, jq, curl | sing-box manager — parse subscriptions into node configs, latency test, switch nodes via the local API |
| `cm-image` | cm-preview, cm-common | Wallpaper picker — thumbnail file browser with live preview |
| `cm-preview` | tiny-cmenush | Preview helper for cm-image (also usable as an image viewer) |
| `cm-swirl` | swaymsg, jq | Categorized window switcher for sway — pull/swap/focus windows grouped by type |
| `set-wallpaper` | swaybg | Set wallpaper from selected image |
| `cm-alias` | bash | Alias manager — add/edit/delete aliases via tiny-cmenush, bash only |
| `powerctl` | gtklock | Lock / reboot / poweroff helper, used by swayidle and keybinds |

## Sway

Mod key is `Mod1` (Alt) by default, overridden by `~/.config/sway/local/mod.g`
if you choose Super during bootstrap.

Keybinds generated at bootstrap time in `utilities.g`:
- `$mod+Return` — Terminal
- `$mod+d` — Application launcher (cm-launcher)
- `$mod+Ctrl+w` — Wallpaper picker (cm-image | set-wallpaper)
- `$mod+BackSpace` — Volume mixer (cm-volmixer)
- `$mod+a` — Alias manager (cm-alias)
- `$mod+m` — Media controller (cm-media)
- `$mod+n` — Network controller (cm-network)
- `$mod+s` / `$mod+r` / `$mod+g` — Window swirl: pull / swap / focus (cm-swirl)
- Media keys — Volume, playback, brightness (gated by pactl/playerctl/brightnessctl)
- `$mod+Shift+e` — Exit sway (with confirmation)

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

## Kanata

[Kanata](https://github.com/jtroo/kanata) is a keyboard remapper. The config
uses CapsLock as a layer-tap: tap for Escape, hold for navigation layer
(arrow keys, home/end, pgup/pgdn). Physical Escape doubles as backtick on
tap and a media layer on hold.

If kanata isn't installed, bootstrap offers to download it from GitHub
releases to `~/.local/bin/`. A systemd user service is generated at
bootstrap time using the detected binary path.

## File management

Bootstrap offers to install termfilebrowser, a TUI file browser with Neovim
integration (`<leader>e`, `<leader>E`). The binary is downloaded from the
dotfiles GitHub releases, same pattern as tiny-cmenush and kanata.

## Notes

`notes/` contains technical reference documents:

| Directory | Contents |
|-----------|----------|
| `guides/` | Actual processes I've done end-to-end |
| `reference/` | Random nonsense |

## Theme

[Catppuccin Mocha](https://github.com/catppuccin/catppuccin) — all configs
use it. Waybar and gtklock are styled to match.
