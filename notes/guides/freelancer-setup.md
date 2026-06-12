# Freelancer Setup

Target: Freelancer (MagiPacks repack) via wine on Arch Linux, VMware VM.

---

## Prerequisite: XWayland

Sway is Wayland-only. Wine's `winex11.drv` needs an X11 display — provided by XWayland:

```bash
sudo pacman -S xorg-xwayland
```

After restarting Sway, verify:

```bash
echo $DISPLAY
```

If it prints `:0`, XWayland is running and wine should work via `winex11.drv`.

If XWayland doesn't work in your setup, try one of these:

- **Distrobox approach** — wine in an Arch container via podman (see `freelancer-setup-voidlinux-musl.md`)
- **X11 + i3 session** — native Xorg session (see below)

---

### Plan B: X11 + i3 Session

If wine still has issues under XWayland, switch to a native X11 session.

#### 1. Install Packages

```bash
sudo pacman -S xorg-server i3-wm alacritty xorg-xrandr
```

| Package | Why |
|---------|-----|
| `xorg-server` | X11 display server — wine's `winex11.drv` connects here |
| `i3-wm` | Tiling WM — without it Xorg shows a blank screen |
| `alacritty` | Terminal for X11 (foot is Wayland-only) |
| `xorg-xrandr` | Set resolution, verify X server is alive |

#### 2. Register i3 as Login Session

`i3-wm` creates `/usr/share/xsessions/i3.desktop` automatically.
The ly-dm display manager reads sessions from:

```
/usr/share/wayland-sessions/   → Wayland compositors (sway)
/usr/share/xsessions/          → Xorg WMs (i3)
```

Restart ly-dm, select **i3** instead of Sway at login.

#### 3. Configure the Xorg Driver

**Don't install `xf86-video-vmware`** — broken on modern kernels
(I/O port access blocked). Use `modesetting` (built into xorg-server):

```bash
sudo tee /etc/X11/xorg.conf.d/10-modesetting.conf << 'EOF'
Section "Device"
    Identifier "VMware SVGA II"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection
EOF
```

`AccelMethod "none"` disables glamor (OpenGL 2D), which is slower
on SVGA3D than simple CPU framebuffer ops.

#### 4. i3 Keybinds (minimal)

```
Mod1+Return          Terminal (alacritty)
Mod1+h/j/k/l         Focus
Mod1+Shift+h/j/k/l   Move window
Mod1+1..0            Switch workspace
Mod1+Shift+1..0      Move window to workspace
```

#### 5. Verify

```bash
cat ~/.local/share/xorg/Xorg.0.log | grep -E "modesetting|Accel"
```

Expected:
```
(II) modeset(0): using drv /dev/dri/card0
(II) modeset(0): glamor X acceleration disabled by "none" option
```

Now run wine normally — no `WINEDLLOVERRIDES` needed.

---

## Install Freelancer

### Step 1: Create Wine Prefix

A **wine prefix** is a directory that mimics a Windows system drive. It
contains `drive_c/` (C: drive), registry files (`system.reg`, `user.reg`),
and installed Windows components. Each game should get its own prefix to
avoid DLL/registry conflicts.

```bash
export WINEPREFIX=$HOME/Games/wine-prefixes/freelancer
export WINEARCH=win64
```

| Variable | Value | Explanation |
|----------|-------|-------------|
| `WINEPREFIX` | `$HOME/Games/wine-prefixes/freelancer` | Tells wine to use this directory as the prefix instead of the default `~/.wine` |
| `WINEARCH` | `win64` | Creates a 64-bit prefix. Can run both 32-bit and 64-bit Windows apps via the WoW64 layer. A `win32` prefix runs only 32-bit apps |

Initialize the prefix with `wine winecfg` (not `wineboot`):

```bash
wine winecfg
```

**Why not `wineboot`:** wineboot is a **console** (terminal) subsystem
executable — it initializes the prefix through a console window, which
involves pseudo-tty allocation and wineserver signal handling. On this
system, that path deadlocks. `winecfg` is a **GUI** subsystem executable
— it drives the same prefix initialization through the graphics window
path, which avoids the console hang entirely.

A config window appears. Leave it open for the next step.

### Step 2: Set Windows Version to 7

In the winecfg window:

1. Go to the **Applications** tab
2. Under **Windows Version**, select **Windows 7**
3. Click **OK**

Freelancer was originally installed with Windows XP set in winecfg (the
game ran fine). For Freelancer HD Edition, the installer required a newer
Windows version (Win10 was used; Win7 may also work). After HD install,
Win7 was set in winecfg and both the HD-modded and original (post-patch)
versions ran fine with it.

### Step 3: Run the Game Installer

The MagiPacks repack consists of two files in `~/Games/`:

```
Freelancer_Repack_Setup.exe    — Inno Setup installer (951K)
Freelancer_Repack_Setup-1.bin  — Compressed game data (501M)
```

Both must be in the same directory (the `.exe` reads the `.bin` at runtime).

```bash
export WINEPREFIX=$HOME/Games/wine-prefixes/freelancer
export WINEARCH=win64
wine ~/Games/Freelancer_Repack_Setup.exe
```

An installer window appears. The default install path is
`C:\MagiPacks\Freelancer\`. Let it complete.

The repack already includes:
- **Patch v1.1** — official Microsoft patch
- **Jason's Freelancer Patch v1.25** (JFLP) — bug fixes, widescreen prep

### Step 4: Verify Installation

```bash
ls "$WINEPREFIX/drive_c/MagiPacks/Freelancer/EXE/"
# Should see: freelancer.exe, FLServer.exe, jflp.dll, rendcomp.dll, etc.
ls "$WINEPREFIX/drive_c/MagiPacks/Freelancer/DATA/" | head -5
# Should see: AI, AUDIO, BASES, CHARACTERS, COCKPITS, etc.
```

The game executable: `C:\MagiPacks\Freelancer\EXE\freelancer.exe`

### Step 5: Install Freelancer HD Edition

Freelancer HD Edition is a mod that improves textures, models, audio,
and includes engine patches that fix the mouse cursor bug (see Known
Issues). It is compatible with vanilla save files and multiplayer.

Windows version must be set to Win7+ for the installer:

```bash
export WINEPREFIX=$HOME/Games/wine-prefixes/freelancer
export WINEARCH=win64
wine ~/Games/FreelancerHDESetup_v0_7_1.exe
```

The installer detects the existing Freelancer install and patches it
in-place. No separate download or config needed.

---

## Run the Game

### Command

```bash
export WINEPREFIX=$HOME/Games/wine-prefixes/freelancer
export WINEARCH=win64

WINEDLLOVERRIDES="dinput.dll=b,n" WINEDEBUG=-all \
  wine "$WINEPREFIX/drive_c/MagiPacks/Freelancer/EXE/freelancer.exe"
```

| Flag | Explanation |
|------|-------------|
| `WINEDLLOVERRIDES="dinput.dll=b,n"` | `dinput.dll` is DirectInput (mouse/keyboard). `b,n` tells wine to try its **b**uiltin implementation first; if that fails, use the **n**ative DLL from the game directory. The builtin handles X11 mouse events more reliably than the game's bundled DLL. **With HD Edition installed, try omitting this override** — the engine patches may work better with the native DLL |
| `WINEDEBUG=-all` | Disables all wine debug output. Without this, stderr is flooded with `fixme:d3d:debug_d3dformat Unrecognized WINED3DFORMAT!` — thousands of lines per second. These are harmless: WineD3D encounters DXT5 texture variants with no direct OpenGL equivalent, logs a fixme, falls back to a default format, and continues |

### Understanding the Render Path

When Freelancer runs, the graphics pipeline is:

```
freelancer.exe → d3d8.dll → wined3d.dll
    ↓
DirectX 8 → OpenGL translation:
  - State block tracking (DX render states → GL state)
  - Shader conversion (DX bytecode → GLSL)
  - Texture format mapping (DXT5 → GL_COMPRESSED_RGBA)
    ↓
winex11.drv → X11 → XWayland → vmwgfx
    ↓
OpenGL context via GLX → Mesa SVGA3D Gallium driver
    ↓
vmwgfx kernel DRM driver
    ↓
VMware SVGA II (virtual GPU)
```

All the `fixme:d3d:wined3d_get_format` messages come from the texture format
mapping step — WineD3D doesn't have a direct OpenGL equivalent for every
D3D format, so it approximates. The game continues rendering with the
fallback format.

### Performance

WineD3D → OpenGL → SVGA3D is not fast. Freelancer will run but may
have reduced framerates. This is a limitation
of the VMware virtual GPU — with a real GPU (or Vulkan support), DXVK would
bypass OpenGL entirely and run much faster.

With HD Edition installed, the higher-resolution textures increase the
rendering load significantly — expect noticeably worse framerates on the
WineD3D path. If performance is unplayable, consider running
the original (unmodded) game instead.

---

## Known Issues

### Mouse Cursor Boundary Bug

Cursor movement is limited to a randomly-sized region of the screen — the
cursor cannot reach parts of the display, and the unreachable area varies.

**Root cause (not fully determined):**

The bug appears to be an intermittent VMware display/mouse capture
synchronization issue — the guest's mouse region occasionally doesn't
align with the actual screen. It is not specific to fullscreen mode:
resizing the VMware display window or toggling fullscreen a few times
can force a re-sync that fixes it.

**Why HD Edition fixes it (unknown):**
HD Edition resolves the issue, but the mechanism is not confirmed — it
may force a capture re-sync via resolution/aspect ratio change, or patch
something directly.

**Reliable workarounds:**
1. **Freelancer HD Edition** — confirmed to fix it, mechanism unclear
2. **Resize/reseat the display** — toggle fullscreen or resize the VMware
   window until the cursor region re-syncs (hit-or-miss)

## Reference

### Wine DLL Override Syntax

```
Syntax: WINEDLLOVERRIDES="dllname1=flag1,flag2;dllname2=flag1"
```

Flags:
- `b` — builtin (wine's own implementation)
- `n` — native (the DLL from the game/windows)
- `d` — disable (don't load the DLL at all)
- Order matters: `b,n` = try builtin first, then native

### GE-Proton

Alternative wine runner containing DXVK, VKD3D, FAudio, etc.

Not in use here — system wine-staging works for DX8/9 games via WineD3D, and
the VMware SVGA II adapter has no Vulkan support, so DXVK (GE-Proton's main
advantage) is unusable on this system.
