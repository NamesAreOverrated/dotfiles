# dotfiles

Sway desktop with a Catppuccin Mocha theme across all tools.

## The experience

### One key per tool

Press one key to open each tool:

- Press `$mod+d` to open the application launcher (`cm-launcher`).
- Press `$mod+m` to open the media controller (`cm-media`).
- Press `$mod+BackSpace` to open the volume mixer (`cm-volmixer`).
- Press `$mod+n` to open the network controller (`cm-network`).

### The media controller

The media controller (`cm-media`) controls players that support MPRIS.
It also controls the NetEase Cloud Music daemon (`ncm-daemon`).

You can do these actions from one menu:

- Scan a QR code to log in.
- Search for music.
- Open playlists.
- Play local files.
- Use FM radio.
- Change the play mode (normal, loop, shuffle, repeat).
- Like or dislike a song.
- Remove a song from FM.
- Log out.

### Window management

Press these keys to manage windows:

- Press `$mod+s` to pull a window into view.
- Press `$mod+r` to swap the positions of two windows.
- Press `$mod+g` to focus a window.

The tool (`cm-swirl`) groups the windows by type, for example browser,
terminal, editor, and media. Press Enter to select a window.

### The CapsLock key

The CapsLock key has two functions:

- Tap CapsLock to press Escape.
- Hold CapsLock to open the navigation layer (arrow keys, Home, End, Page Up, Page Down).

The physical Escape key has two functions:

- Tap Escape to type a backtick.
- Hold Escape to open the media layer.

### The wallpaper picker

Press `$mod+Ctrl+w` to open the wallpaper picker (`cm-image`).

You can preview a wallpaper before you set it. Use the P and N keys to move
through the images. Press Enter to set the wallpaper.

### The network and proxy tools

The network controller (`cm-network`) manages WiFi connections and proxy
settings. The sing-box manager (`cm-singbox`) loads subscriptions, tests
nodes, and switches the active node.

## Keybindings

| Key | Action |
|-----|--------|
| `$mod+Return` | Open the terminal |
| `$mod+d` | Open the application launcher |
| `$mod+Ctrl+w` | Open the wallpaper picker |
| `$mod+BackSpace` | Open the volume mixer |
| `$mod+a` | Open the alias manager |
| `$mod+m` | Open the media controller |
| `$mod+n` | Open the network controller |
| `$mod+s` / `$mod+r` / `$mod+g` | Pull / swap / focus a window |
| Media keys | Volume, playback, brightness |
| `$mod+Shift+e` | Exit sway |

## Quick start

```
git clone --recurse-submodules https://github.com/NamesAreOverrated/dotfiles.git
cd dotfiles
bash bootstrap.sh
```

Re-running is safe. Everything is idempotent.

---

## Under the hood

### What's inside

| Thing | Config |
|-------|--------|
| [sway](https://swaywm.org) | `sway/config` — Mod key prompted at bootstrap (Alt-main or Super-main) |
| [waybar](https://github.com/Alexays/Waybar) | `waybar/config.jsonc` + `style.css` |
| [gtklock](https://github.com/jovanlanik/gtklock) | `gtklock/config.ini` + `style.css` + `layout.xml` |
| tiny-cmenush | Overlay menu (rofi replacement). Companion scripts: `cm-launcher`, `cm-media`, `cm-network`, `cm-volmixer`, `cm-alias`, `cm-singbox`, `cm-image`, `cm-preview`, `cm-swirl`, `config-env`, `set-wallpaper`, `powerctl` |
| [kanata](https://github.com/jtroo/kanata) | `kanata/kanata.kbd` — CapsLock layer-tap keyboard remapper |
| [nvim](https://neovim.io) | `nvim/` — Catppuccin Mocha base with custom semantic token colors |
| [foot](https://codeberg.org/dnkl/foot) | `foot/foot.ini` |
| [starship](https://starship.rs) | `starship.toml` |
| ncm-daemon | NetEase Cloud Music daemon, auto-installed via bootstrap + systemd user service |
| sing-box | `sing-box/config.json` — base config, node list managed by `cm-singbox` |
| termfilebrowser | TUI file browser, auto-installed via bootstrap |
| trsh | Safe-by-default `rm` → trash. Auto-installed via bootstrap; aliases: `rm`, `rm-list`, `rm-restore`, `rm-empty`, `rm-purge` |

| wallpapers | `wallpapers` submodule — symlinked to `~/Pictures/wallpapers` |
| fonts | `fonts/afio.zip` — afio font, installed via bootstrap |

Old rofi scripts and configs remain in the repo but are no longer linked.

### Bootstrap

The bootstrap script sources every `.sh` in `bootstrap-linux/` in order:

1. **Init** — prompts for mod key (Alt-main + Super-nested, or Super-main + Alt-nested)
2. **Path** — adds `~/.local/bin` to PATH in `~/.bash_profile` (login shells)
3. **Config linking** — links configs for the tools that are installed: starship, nvim, foot, gtklock, waybar, sway
4. **Kanata** — checks uinput udev rule + group membership, offers to install the binary, links config, generates a systemd user service
5. **ncm-daemon** — offers to download the binary, enables it as a systemd user service
6. **tiny-cmenush** — offers to download the binary, links theme configs + companion scripts, creates the default proxy config (dep-gated: cm-volmixer needs pactl, cm-network needs nmcli, cm-singbox needs sing-box + jq, set-wallpaper needs swaybg; cm-alias bash-only skips on fish systems)
7. **Assets** — installs the afio font from `fonts/afio.zip`
8. **Wallpapers** — copies existing wallpapers into the `wallpapers` submodule, symlinks it to `~/Pictures/wallpapers`
9. **Scripts** — links `powerctl`
10. **File management** — offers to install termfilebrowser from GitHub
11. **trsh** — offers to auto-download the glibc/musl binary from GitHub releases; installs the 5 `rm` aliases into `~/.bashrc`
12. **WM configs** — links `cm-swirl`, generates machine-specific sway configs (mod, outputs, wallpaper, keybinds, idle)

Each script checks which tools are actually installed and skips configs for missing ones.

### Machine-specific config

In sway, `~/.config/sway/local/` holds anything machine-specific:

| File | Behavior |
|------|----------|
| `mod.g` | **Always regenerated.** Contains `set $mod Mod1` or `set $mod Mod4`. |
| `outputs.g` | Created once. Add your monitor layout here. |
| `wallpaper.g` | Written by set-wallpaper. Never hand-edit. |
| `utilities.g` | **Always regenerated.** Auto-generated keybinds based on installed tools. |
| `custom.g` | Created once. Add your own binds here (brightness, media keys, etc.). |

### tiny-cmenush

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
| `config-env` | — | Emits shell env vars (PATH guard, TERMINAL/EDITOR, proxy from `cm-network`) for bash and fish |
| `powerctl` | gtklock | Lock / reboot / poweroff helper, used by swayidle and keybinds |

### Sway

Mod key is chosen at bootstrap time: Alt as main (with Super nested) or
Super/Win as main (with Alt nested). The choice is written to
`~/.config/sway/local/mod.g`.

Keybinds generated at bootstrap time in `utilities.g`:
- `$mod+Return` — Terminal
- `$mod+d` — Application launcher (cm-launcher)
- `$mod+Ctrl+w` — Wallpaper picker (cm-image | set-wallpaper)
- `$mod+BackSpace` — Volume mixer (cm-volmixer)
- `$mod+a` — Alias manager (cm-alias)
- `$mod+m` — Media controller (cm-media)
- `$mod+n` — Network controller (cm-network)
- `$mod+Shift+w` — Toggle waybar
- `$mod+s` / `$mod+r` / `$mod+g` — Window swirl: pull / swap / focus (cm-swirl)
- Media keys — Volume, playback, brightness (gated by pactl/playerctl/brightnessctl)
- `$mod+Shift+e` — Exit sway (with confirmation)

The base `sway/config` also defines window/column management: `$mod+Shift+s/r/g`
overview (pull/swap/focus all), `$mod+Shift+p` pop, `$mod+Ctrl+h/l` pull
left/right, `$mod+Shift+comma` take, `$mod+Shift+period` release, and
`$mod+Ctrl+minus` / `$mod+Ctrl+equal` to even out column widths (evenv/evenh).

### Neovim

Based on [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) with
`vim.pack` as the plugin manager.

**Colorscheme:** Catppuccin Mocha with heavily customized semantic tokens,
applied to all languages (not C#-specific).

General token overrides:
- Functions/methods/constructors — `#a6e3a1` (mint), calls/macros italic
- Strings — `#f5c2e7` (pink)
- Constants/numbers/booleans — `#dd7878` (red)
- Properties — `#c7d79b` (green, italic)
- Parameters — `#eba0ac` (maroon)
- Variables — `#cdd6f4` (light gray)

Additional LSP semantic token colors:

| Token | Color |
|-------|-------|
| Classes | `#89b4fa` (blue) |
| Structs | `#89dceb` (sky) |
| Delegates | `#7ecb8e` (medium green) |
| Interfaces | `#8edbaa` (green-teal) |
| Events | `#9ece6a` (yellow-green) |
| Fields | `#fab387` (peach, italic) |
| Constants | `#dd7878` (red) |
| Parameters | `#eba0ac` (maroon) |
| Namespaces | `#a9b1d6` (light gray-blue) |
| Enums | `#f5e0dc` (pale rose) |
| Type params | `#f5c2e7` (pink) |

Methods/constructors follow the general `@function` color (`#a6e3a1`).

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

### Kanata

[Kanata](https://github.com/jtroo/kanata) is a keyboard remapper. The config
uses CapsLock as a layer-tap: tap for Escape, hold for navigation layer
(arrow keys, home/end, pgup/pgdn). Physical Escape doubles as backtick on
tap and a media layer on hold.

If kanata isn't installed, bootstrap offers to download it from GitHub
releases to `~/.local/bin/`. A systemd user service is generated at
bootstrap time using the detected binary path.

### File management

Bootstrap offers to install termfilebrowser, a TUI file browser with Neovim
integration (`<leader>e`, `<leader>E`). The binary is downloaded from the
dotfiles GitHub releases, same pattern as tiny-cmenush and kanata.

### Notes

`notes/` contains technical reference documents:

| Directory | Contents |
|-----------|----------|
| `guides/` | Actual processes I've done end-to-end |
| `reference/` | Random nonsense |

### Theme

[Catppuccin Mocha](https://github.com/catppuccin/catppuccin) — all configs
use it. Waybar and gtklock are styled to match.
