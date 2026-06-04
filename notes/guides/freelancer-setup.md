# Freelancer Setup

Target: Freelancer (MagiPacks repack) via wine on Arch Linux, VMware VM.

---

## The Problem: Sway + Wayland Only

The machine was installed with **Sway** as the only display session. Sway is a
Wayland compositor — it uses the kernel DRM interface directly, has no X11
server, and doesn't load any Xorg driver.

```bash
$ echo $XDG_SESSION_TYPE
wayland
$ ps aux | grep Xorg
# nothing — no X server running
```

This works well for daily driving (terminal, browser, coding), but fails for
windows gaming via wine due to two issues:

### Issue 1: XWayland Font Breakage

wine's default display driver is `winex11.drv` — it speaks the X11 protocol.
Under Wayland, the X11 server is **XWayland** (an X server that runs as a
Wayland client). When wine tries to create its first window, XWayland tries
to load the ISO8859-1 `cursor.pcf` font:

```
X connection to :0 broken (explicit kill or server shutdown)
```

This happens because `xorg-fonts-misc` (which provides this font) is not
installed by default on Wayland-only systems. XWayland crashes before any
window appears.

### Issue 2: Wayland Wine Driver Can't Run Games

`winex11.drv=d` forces wine to skip the X11 driver and use its native
Wayland driver (`winewayland.drv`). This bypasses XWayland entirely:

```bash
WINEDLLOVERRIDES="winex11.drv=d" wine winecfg    # works — config window appears
```

But trying to run the Freelancer installer (or any standalone .exe) fails:

```
could not load kernel32.dll (error c0000135)
```

⚠️ **Honest guess at why:** `c0000135` is STATUS_DLL_NOT_FOUND — Windows
reports this when a required DLL can't be located. `kernel32.dll` is the
fundamental Windows API DLL, always loaded first. It exists in the prefix
(`system32/kernel32.dll`), so the file is there. The failure might be in
how the Wayland driver's PE loader resolves the WoW64 path (the 32-bit
`kernel32` in `syswow64/` vs the 64-bit one in `system32/`), or in the
loader's initialization order when no X11 display is available. But the
real cause wasn't investigated further — the true cause remains unknown as of this writing.

**What matters:** `winecfg` works (it's a GUI tool that creates its own
window, yet runs successfully) — the failure pattern isn't simply
"GUI vs non-GUI." The `c0000135` error on standalone executables was
not investigated beyond finding that the Xorg workaround bypasses it.

### The Fix: Add an X11 Session

The solution is to install **i3** on **Xorg** alongside Sway, and switch
to it when gaming. Both sessions share the same user, filesystem, and
installed packages. Only the display server changes.

---

## Part 1: Set Up X11 + i3 Session

### Step 1.1: Install Xorg and i3

```bash
sudo pacman -S xorg-server i3-wm alacritty xorg-xrandr
```

| Package | What It Does | Why Needed |
|---------|-------------|-------------|
| `xorg-server` | The X11 display server. Listens on Unix socket `/tmp/.X11-unix/X0`, manages windows, handles input, talks to the GPU via DRM | Provides an X11 display that wine's `winex11.drv` can connect to |
| `i3-wm` | Tiling window manager for Xorg. Manages windows in a grid with keyboard shortcuts | Gives us a usable X11 desktop. Without a WM, Xorg shows only a blank screen with an X cursor |
| `alacritty` | GPU-accelerated terminal for X11 | Terminal emulator that works under Xorg. The Sway config used `foot`, which is Wayland-only |
| `xorg-xrandr` | Command-line display configuration tool | Sets resolution (`xrandr -s 1920x1080`). Also useful for verifying the X server is alive |

### Step 1.2: Register i3 as a Login Session

The display manager (**ly-dm**) reads session files from two directories:

```
/usr/share/wayland-sessions/   → Wayland compositors (sway.desktop)
/usr/share/xsessions/          → Xorg Window Managers (i3.desktop)
```

Installing `i3-wm` should automatically create `/usr/share/xsessions/i3.desktop`:

```ini
[Desktop Entry]
Name=i3
Comment=i3 window manager
Exec=i3
Type=Application
```

When ly-dm launches i3, it runs `exec /usr/lib/Xorg :0 vt2 -keeptty ...`.
Xorg starts, takes over the VT, and launches i3 as its window manager.

### Step 1.3: Configure i3

The i3 config is at `~/.config/i3/config`. It was **converted from the Sway
config** at `~/.config/sway/config` with these changes:

| Aspect | Sway config | i3 config (converted) |
|--------|-------------|----------------------|
| Modifier | `set $mod Mod4` (Super) | `set $mod Mod1` (Alt) — Super conflicts with VMware host key |
| Terminal | `set $term foot` | `set $term alacritty` — foot is Wayland-only |
| Bar | `exec waybar` | Removed — waybar needs `GDK_BACKEND=x11` and isn't installed for X11 |
| Gaps | `gaps inner 4` | Same syntax (i3 supports gaps natively since 4.22) |
| Colors | Catppuccin Mocha (client.focused, etc.) | Same palette, using i3's `client.focused` and `client.background` directives |

The resulting layout:

```
Mod1+h/j/k/l         Focus left/down/up/right
Mod1+Shift+h/j/k/l   Move window left/down/up/right
Mod1+Return          Launch terminal (alacritty)
Mod1+Space           Toggle floating
Mod1+Shift+Space     Toggle tiling/floating
Mod1+minus           Send to scratchpad
Mod1+Shift+minus     Show scratchpad
Mod1+1..0            Switch to workspace 1..10
Mod1+Shift+1..0      Move window to workspace 1..10
```

### Step 1.4: The Xorg Driver Problem

Xorg needs a display driver to talk to the GPU. The VM has a **VMware SVGA II**
adapter (PCI 15ad:0405). Two driver options exist:

#### Option A: `xf86-video-vmware` (chipset-specific — BROKEN)

```
sudo pacman -S xf86-video-vmware
```

This driver tries to access legacy ISA I/O ports (0x0000–0x03ff) via
`xf86EnableIO()` for VGA register control. Modern kernels restrict this
via the `ioperm()` syscall — only root or processes with `CAP_SYS_RAWIO`
can call it. Xorg runs as a user process (via systemd-logind), so the call
fails:

```
xf86EnableIO: failed to enable I/O ports 0000-03ff (Operation not permitted)
```

After this failure, the driver cannot initialize its native 2D acceleration
(Gallium3D Xa). It disables all rendering:

```
Failed to initialize Gallium3D Xa. No render acceleration available.
Render acceleration is disabled.
Direct rendering (DRI2 3D) is disabled.
AIGLX: Screen 0 is not DRI2 capable
GLX: Initialized DRISWRAST GL provider for screen 0
```

Both 2D and 3D fall to pure software (LLVMpipe) — slower than any other
option. **This driver should not be used.**

#### Option B: `modesetting` (generic — WORKS)

This is Xorg's **generic** display driver. Instead of talking to the GPU
hardware directly, it communicates through the kernel's DRM/DRI interface —
the **same interface Wayland compositors use**. Since `vmwgfx` (the kernel
DRM driver) handles the actual GPU communication, modesetting works
correctly:

```bash
# No package to install — modesetting is built into xorg-server
sudo tee /etc/X11/xorg.conf.d/10-modesetting.conf << 'EOF'
Section "Device"
    Identifier "VMware SVGA II"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection
EOF
```

**Why `AccelMethod "none"`:**

`modesetting` has two 2D rendering paths:

| Path | Configuration | What It Does | Performance on VMware |
|------|--------------|-------------|----------------------|
| **glamor** | Default | Translates 2D drawing into OpenGL calls via Mesa/SVGA3D | **Slow** — every GL call must traverse guest→hypervisor→host GPU via SVGA3D protocol translation |
| **framebuffer** | `AccelMethod "none"` | Draws 2D via simple CPU framebuffer operations (`memcpy`, fill rects) | **Faster** — avoids SVGA3D entirely |

glamor is useful for 2D-heavy desktop environments (GNOME, KDE) with
real GPUs. On VMware SVGA3D, the protocol translation overhead makes it
slower than raw framebuffer access. Disabling glamor makes i3 feel snappy.

#### Verification

After creating the config, log out of Sway and log into the i3 session.
Check the Xorg log:

```bash
cat ~/.local/share/xorg/Xorg.0.log | grep -E "modesetting|glamor|Accel"
```

Expected output:

```
(II) modeset(0): using drv /dev/dri/card0
(II) modeset(0): glamor X acceleration disabled by "none" option
```

---

## Part 2: Install Freelancer

### Step 2.1: Create Wine Prefix

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

### Step 2.2: Set Windows Version to 7

In the winecfg window:

1. Go to the **Applications** tab
2. Under **Windows Version**, select **Windows 7**
3. Click **OK**

Freelancer was originally installed with Windows XP set in winecfg (the
game ran fine). For Freelancer HD Edition, the installer required a newer
Windows version (Win10 was used; Win7 may also work). After HD install,
Win7 was set in winecfg and both the HD-modded and original (post-patch)
versions ran fine with it.

### Step 2.3: Install DirectPlay ⚠️

Freelancer uses **DirectPlay** (a deprecated DirectX networking API) for
both multiplayer and single-player session management. Even in single-player,
the engine initializes DirectPlay on startup — it creates a local session
listener. Without DirectPlay registered, the game hangs or crashes at launch.
⚠️ This step was taken based on advice from the WineHQ AppDB — it has not been
confirmed whether DirectPlay is actually required on this setup. The game was
never tested without it.

```bash
winetricks -q directplay
```

| Argument | Meaning |
|----------|---------|
| `-q` | Quiet mode — skip prompts, run unattended |
| `directplay` | Component name: registers four DirectPlay DLLs via `regsvr32` |

This runs `regsvr32` on each DLL, which calls `DllRegisterServer` to write
COM class IDs and AppID entries to the registry:

| DLL | Provides | Registered COM Class |
|-----|----------|---------------------|
| `dplayx.dll` | DirectPlay 4 (legacy) | `CLSID_DirectPlay` |
| `dpnet.dll` | DirectPlay 8 (used by Freelancer) | `CLSID_DirectPlay8Client`, `CLSID_DirectPlay8Server` |
| `dpnhpast.dll` | NAT Helper PAST | DirectPlay NAT traversal |
| `dpnhupnp.dll` | NAT Helper UPnP | DirectPlay NAT traversal (UPnP) |

After registration, the game's `CoCreateInstance(CLSID_DirectPlay8Client)`
succeeds instead of returning "Class not registered."

### Step 2.4: Run the Game Installer

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

### Step 2.5: Verify Installation

```bash
ls "$WINEPREFIX/drive_c/MagiPacks/Freelancer/EXE/"
# Should see: freelancer.exe, FLServer.exe, jflp.dll, rendcomp.dll, etc.
ls "$WINEPREFIX/drive_c/MagiPacks/Freelancer/DATA/" | head -5
# Should see: AI, AUDIO, BASES, CHARACTERS, COCKPITS, etc.
```

The game executable: `C:\MagiPacks\Freelancer\EXE\freelancer.exe`

### Step 2.6: Install Freelancer HD Edition

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

## Part 3: Run the Game

### Before Running

**You must be in the i3/Xorg session.** Confirm:

```bash
$ echo $XDG_SESSION_TYPE
x11
```

If it says `wayland`, log out of Sway, select **i3** at the ly-dm prompt,
and log back in.

**Why Xorg is required:** wine's Wayland driver can't run any real Windows
executable — they all fail with `could not load kernel32.dll` for unknown
reasons. Only `winecfg` works. The X11 driver (`winex11.drv`) on Xorg works
normally. So Xorg is mandatory for wine gaming on this system.

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
winex11.drv → X11 → Xorg → modesetting
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

The cursor cannot reach the right ~5–10% of the screen (or sometimes the
bottom edge, depending on resolution). This is a known Freelancer engine
bug reproduced on real Windows hardware, not a wine issue.

⚠️ **Root cause (best understanding):**

Freelancer creates a DirectInput mouse device and calls `GetDeviceState`
to read relative motion. To keep the cursor inside the window, it also
calls `ClipCursor` — a Win32 API that restricts cursor movement to a
rectangle. On widescreen displays (or when the desktop/window dimensions
differ from what the game expects at startup), `ClipCursor` is called
with a rectangle that is narrower than the actual screen:

- The game reads the display mode at launch but may cache only the
  4:3-safe area or miscalculate after applying aspect-ratio correction
- X11 window decorations offset the client area — if `ClipCursor` uses
  window frame coordinates instead of client coordinates, the clamping
  is shifted left, cutting off the right edge (or shifted up, cutting
  off the bottom)
- JFLP v1.25 (pre-applied in the MagiPacks repack) patches widescreen
  resolution support and may partially address this, but does not
  fully fix it

**Why `dinput.dll=b,n` doesn't help:**

`WINEDLLOVERRIDES="dinput.dll=b,n"` controls which DirectInput DLL is
loaded (wine's builtin vs the game's shipped native copy). The bug is
not in how DirectInput is implemented — it's in how the game's engine
uses the API (wrong `ClipCursor` rectangle). Swapping the DLL doesn't
change the game's `ClipCursor` call.

**Fix: Freelancer HD Edition (confirmed):**

Installing Freelancer HD Edition (Step 2.6) fixes this bug. HD Edition
includes engine-level patches that correct the `ClipCursor` rectangle
for modern resolutions. Tested and confirmed working on this system.
If you haven't installed it yet, go back to Step 2.6.

**Alternative: windowed mode:**

If HD Edition is not desired, running in a window bypasses `ClipCursor`
entirely — the OS naturally confines the cursor to the window borders:

```bash
WINEDLLOVERRIDES="dinput.dll=b,n" WINEDEBUG=-all \
  wine "$WINEPREFIX/drive_c/MagiPacks/Freelancer/EXE/freelancer.exe" -window
```

Or set the registry key before launching:

```
HKEY_CURRENT_USER\Software\Microsoft\Direct3D\FullScreen = 0 (DWORD)
```

### xrandr Resolution

Set before launching if the game resolution is wrong:

```bash
xrandr -s <width>x<height>
```

`xrandr -s` tells Xorg to switch CRTC timing to match the requested
resolution. The game sees the new mode via XRandR.

### Sound Issues

- Disable **3D sound** in Freelancer's audio options
- `WINEDLLOVERRIDES="dsound=b,n"` for builtin DirectSound
- `winetricks -q faudio` for FAudio replacement

### Game Window Doesn't Appear

```bash
echo $XDG_SESSION_TYPE
```

Must be `x11`. If `wayland`, switch to i3 session or try:
```bash
WINEDLLOVERRIDES="winex11.drv=d" wine game.exe
```
(Unlikely to work — see "Why Xorg is required" above.)

### Black Screen on Launch

Some repacks (especially GOG releases) ship wrapper DLLs that replace
DirectDraw or Direct3D with OpenGL. These can conflict with WineD3D.
Override them to use wine's builtin implementations:

```bash
WINEDLLOVERRIDES="ddraw=b;d3d8=b" wine game.exe
```

`ddraw=b` tells wine to use its own builtin DirectDraw instead of the game's
bundled `ddraw.dll`. Add `d3d8=b` for DirectX 8 games like Freelancer.

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
Available at `~/Games/GE-Proton-<version>/`.

Not in use here — system wine-staging works for DX8/9 games via WineD3D, and
the VMware SVGA II adapter has no Vulkan support, so DXVK (GE-Proton's main
advantage) is unusable on this system.
