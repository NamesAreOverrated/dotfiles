# Plan: Waybar overhaul — add tray, network, disk, enhanced clock, CSS refresh

## Summary

Port the VM's richer waybar setup into the repo, with customizations:
- No `sway/mode` module
- Keep existing `custom/lock`/`reboot`/`shutdown` (powerctl)
- Keep existing `pulseaudio#input`/`pulseaudio#output`
- Add `tray`, `network`, `disk` modules
- Replace `clock` with VM's calendar version
- Replace `cpu`/`memory` with VM's richer format
- Replace `style.css` with VM's version (14px, tooltips, workspace highlight)
- Add `local/bin/rofi-network` script from VM

---

## Step 1 — Add `local/bin/rofi-network`

Copy from VM at `~/.local/bin/rofi-network`. It uses `nmcli` (NetworkManager)
for WiFi scanning/connecting and `rofi` for the UI. Depends on:
- `nmcli` (from NetworkManager.networkmanager, not systemd)
- `rofi`
- `notify-send` (from libnotify)
- `ip` (from iproute2)
- `iw` (for wifi device detection)

No init system dependency.

## Step 2 — Replace `waybar/config.jsonc`

Full rewrite. Modules order:

**modules-left:** `["sway/workspaces", "custom/lock", "custom/reboot", "custom/shutdown"]`
(same as current)

**modules-right:** `["tray", "pulseaudio#input", "pulseaudio#output", "network", "disk", "memory", "cpu", "clock"]`

### Detailed module sources

| Module | Source | Notes |
|--------|--------|-------|
| `sway/workspaces` | Keep repo version | Same as VM, no change |
| `custom/lock` | Keep repo | `powerctl lock` |
| `custom/reboot` | Keep repo | `powerctl reboot` |
| `custom/shutdown` | Keep repo | `powerctl poweroff` |
| `tray` | VM version | `icon-size: 16, spacing: 8, show-passive-items: true` |
| `pulseaudio#input` | Keep repo | ``/`` icons, `pactl` toggle |
| `pulseaudio#output` | Keep repo | ``/``/`` icons, `pactl` toggle + scroll |
| `network` | VM version | `nmcli`-based, calls `~/.local/bin/rofi-network` on click |
| `disk` | VM version | `󰋊 {percentage_used}%`, path `/`, 30s interval |
| `memory` | VM version | `󰍛 {percentage}%`, tooltip with GiB values |
| `cpu` | VM version | `󰻠 {usage}%`, 5s interval |
| `clock` | VM version | Calendar, format-alt, Catppuccin-colored days |

### Icons to port (all Nerd Font)

| Context | Icon | Codepoint |
|---------|------|-----------|
| tray | (no icon, standard tray icons) | — |
| pulseaudio#input | / | Keep current |
| pulseaudio#output | // | Keep current |
| network format-wifi | `  {essid}` | (text-based) |
| network format-ethernet | `󰖩  {ifname}` | U+F5E9 |
| network format-disconnected | `󰖪  offline` | U+F5EA |
| disk | `󰋊  {percentage_used}%` | U+F2CA |
| cpu | `󰻠  {usage}%` | U+FEE0 |
| memory | `󰍛  {percentage}%` | U+F35B |
| clock format | `󰥔  {:%H:%M}` | U+F954 |
| clock format-alt | `󰃭  {:%a %d %b}` | U+F0ED |
| lock |  | Keep current |
| reboot |  | Keep current |
| shutdown |  | Keep current |

## Step 3 — Replace `waybar/style.css`

Replace with VM version, modifications:

### Changes from current repo:
- `font-size: 12px` → `14px`
- Add `min-height: 24px` to module elements
- Workspace buttons: remove `all: initial` (use `font-family/font-size/font-weight: inherit` instead)
- Workspace buttons: add `.visible` state (`color: #cdd6f4`)
- Workspace buttons `.active`: change from purple background (`bg: #cba6f7`, `color: #1e1e2e`) to red text (`color: #f38ba8`, `background: transparent`, `min-width: 16px`)
- Add CSS selectors: `#tray`, `#network`, `#disk`
- Add colors for new modules:
  - `#network` → `#89b4fa`
  - `#network.disconnected` → `#585b70`
  - `#disk` → `#f5c2e7`
- Add tooltip styling

### Compared to VM's style.css (excluded):
- No `#mode` selector (user doesn't want sway/mode module)

## Step 4 — Update `bootstrap.sh`

Add rofi-network linking after the `powerctl` block (~line 237):

```bash
# --- rofi-network (NetworkManager WiFi picker) ---
if has nmcli && [ -f "$DOTFILES/local/bin/rofi-network" ]; then
    echo "Linking rofi-network..."
    link "$DOTFILES/local/bin/rofi-network" "$HOME/.local/bin/rofi-network"
fi
```

## Step 5 — Commit

`git add -A && git commit`

Message:
```
waybar: add tray/network/disk modules, enhanced clock, 14px CSS

- Add tray, network (rofi-network), disk modules from VM config
- Replace clock with calendar version (Catppuccin-colored)
- Replace cpu/memory with richer VM formats
- Replace style.css with 14px font, tooltips, workspace highlight
- Add local/bin/rofi-network (nmcli-based WiFi manager)
- bootstrap: link rofi-network if nmcli is available
```

## Files changed

| File | Action |
|------|--------|
| `local/bin/rofi-network` | ADD (~140 lines) |
| `waybar/config.jsonc` | REPLACE (76→~110 lines) |
| `waybar/style.css` | REPLACE (95→~130 lines) |
| `bootstrap.sh` | EDIT — add rofi-network linking |

No changes to: lock/reboot/shutdown behavior, pulseaudio modules.
