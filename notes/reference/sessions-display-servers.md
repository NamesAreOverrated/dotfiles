# Sessions & Display Servers

## What Is a Display Server?

A display server is the intermediary between applications (clients) and the
hardware (GPU, input devices). It manages windows, receives input events
(keyboard/mouse), and composites the final screen image.

```
Application (GUI client)
    ↓  protocol (X11 or Wayland)
Display Server (Xorg / Wayland compositor)
    ↓  DRM / KMS / evdev
Linux Kernel (GPU driver, input drivers)
    ↓
Hardware (GPU, monitor, keyboard, mouse)
```

## Xorg (X11)

### History

X11 (the X Window System, version 11) was designed in 1987 at MIT. It's a
**network-transparent** protocol — the client and server can be on different
machines. This is the oldest still-widely-used display protocol.

### Architecture

```
X Client (app)  ←→  X Client (app)
       ↓                    ↓
       └────── X11 Protocol ────┘
                    ↓
              X Server (Xorg)
                    ↓
         ┌──────────┼──────────┐
         ↓          ↓          ↓
     DRM/KMS    evdev      XWayland
    (GPU)    (input)    (Wayland compat)
```

Key traits:

- **Server is a separate process** — Xorg runs independently, clients connect
  via Unix socket or TCP (port 6000). You can run apps on one machine and
  display them on another: `DISPLAY=remote:0 ssh -X app`
- **Network transparency** — X11 protocol is designed for remote display.
  This adds complexity and overhead that most users don't need
- **Security model is weak** — by design, any X client can read the screen,
  inject keystrokes, or grab input of other clients. Mitigations exist
  (X Security Extension, `-auth` cookie) but are not fine-grained
- **Server does not composite** — Xorg can composite (via the Composite
  extension), but it's optional. Historically each window drew directly to
  the framebuffer, causing tearing. Compositing window managers (Compiz,
  compton, picom) were added later as external clients
- **2D acceleration is driver-dependent** — the X server includes a software
  renderer, but chipset-specific drivers (intel, amdgpu, nvidia) and the
  generic `modesetting` driver (with glamor) provide GPU-accelerated 2D

### DISPLAY Variable

```bash
echo $DISPLAY   # e.g., :0 (local display 0)
```

`DISPLAY=:0` means "connect to the local X server on display 0." Remote:
`DISPLAY=192.168.1.5:0` connects to a remote X server over TCP (usually
tunneled via SSH: `ssh -X` sets `DISPLAY=localhost:10.0`).

### XWayland

XWayland is an X server that runs **as a Wayland client**. It allows legacy
X11 applications to run inside a Wayland session without modifying the apps:

```
Legacy X11 app → X11 protocol → XWayland → Wayland protocol → Wayland compositor
```

Each XWayland instance gets its own X display number (usually `:0` or `:1`).
The compositor manages the XWayland windows like any other Wayland surface.
This is how Sway runs X11 apps: `XWayland` starts on demand and the app's
window appears as a Wayland surface.

## Wayland

### History

Wayland was designed from 2008 onward as a modern replacement for X11. It
removes the network transparency layer (unnecessary for local-only displays),
integrates compositing into the display server, and uses modern kernel APIs
(DRM, KMS, evdev, libinput) directly.

### Architecture

```
Wayland Client (app)  ←→  Wayland Client (app)
       ↓                        ↓
       └───── Wayland Protocol ──┘
                    ↓
         Wayland Compositor (Sway, KWin, Mutter)
                    ↓
         ┌──────────┼──────────┐
         ↓          ↓          ↓
     DRM/KMS     libinput    XWayland
    (GPU)       (input)    (compat)
```

Key traits:

- **Compositor is the server** — there is no separate "Wayland server" like
  Xorg. The compositor *is* the display server. Sway, KWin, and Mutter are
  both compositors and display servers
- **No network transparency** — Wayland protocol has no remote display
  capability. Clients and compositor must be on the same machine. (Remote
  access is done via VNC/RDP/pipewire, or by running a nested compositor)
- **Security by design** — clients cannot see other clients' windows, read
  input from other windows, or inject events without explicit permission
  (via protocols like `wlr-screenshot` or `xdg-desktop-portal`)
- **Compositing is inherent** — every Wayland compositor composites. There
  is no "uncomposited" mode. Tearing is opt-in via explicit protocols
- **Protocol is extensible** — the core Wayland protocol is minimal. Features
  are added via protocol extensions (wlr-layer-shell, xdg-shell, etc.).
  Each compositor implements a subset of extensions, causing fragmentation
- **Direct rendering** — clients can render directly to GPU buffers via
  `wl_drm` or `linux-dmabuf` (zero-copy). No X11-style shared memory copies

### WAYLAND_DISPLAY Variable

```bash
echo $WAYLAND_DISPLAY   # e.g., wayland-0 or wayland-1
```

Most compositors create a Unix socket at `$XDG_RUNTIME_DIR/wayland-0`.

## Display Manager (ly-dm)

A display manager (DM) is the **login screen** that starts your session.
It handles authentication and launches the chosen display server + compositor.

```
ly-dm (greeter)
    ↓ user selects session
Launch display server + compositor
    ↓
Session runs (Xorg + i3, or Sway)
    ↓ user logs out
ly-dm restarts
```

Examples: ly-dm (minimal TTY-based), SDDM (Qt-based), GDM (GNOME), LightDM.

### How ly-dm Launches Sessions

ly-dm reads session files from:

- `/usr/share/wayland-sessions/` — for Wayland compositors (Sway, KWin)
- `/usr/share/xsessions/` — for Xorg sessions (i3, Xfce, GNOME on Xorg)

Each session file is a `.desktop` file:

```ini
# /usr/share/wayland-sessions/sway.desktop
[Desktop Entry]
Name=Sway
Comment=Sway Wayland compositor
Exec=sway
Type=Application

# /usr/share/xsessions/i3.desktop
[Desktop Entry]
Name=i3
Comment=i3 window manager
Exec=i3
Type=Application
```

When you select Sway, ly-dm runs `exec sway` on the current VT. When you
select i3, ly-dm runs `exec /usr/lib/Xorg :0 vt2 -keeptty -auth ...` to
start Xorg, then Xorg launches i3 as its window manager.

### Session Lifecycle

```
ly-dm starts on VT (tty1 or tty2)
    ↓
User authenticates
    ↓
Select session type (Wayland or Xorg)
    ↓
ly-dm runs the session command in the user's context
  (via PAM, sets XDG_RUNTIME_DIR, DISPLAY, WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS)
    ↓
Display server starts, takes over the VT
    ↓
Window manager / compositor runs desktop environment
    ↓
User logs out → session process exits
    ↓
ly-dm takes back the VT, shows greeter again
```

## XDG Session Type

```bash
echo $XDG_SESSION_TYPE   # "x11" or "wayland" or "tty"
```

This is set by the display manager or by pam_systemd. Applications use it to
decide which backend to load (e.g., Qt apps choose `QT_QPA_PLATFORM=wayland`
or `xcb`, GTK apps choose `GDK_BACKEND=wayland` or `x11`).

## Key Differences Summary

| Aspect | Xorg | Wayland |
|--------|------|---------|
| Architecture | Client-server separable | Compositor is the server |
| Remote display | Native (TCP, SSH -X) | VNC/RDP/pipewire only |
| Security | Weak (any client reads screen) | Strong (sandboxed per client) |
| Compositing | Optional (add-on WM) | Inherent (compositor is the server) |
| Tearing | Common without compositor | Rare (explicit protocol) |
| 2D acceleration | Driver-dependent (glamor, etc.) | Kernel DRM only (no 2D GPU) |
| Input | evdev + XInput2 | libinput (via compositor) |
| Protocol age | 1987 (39 years) | 2008 (18 years) |
| GPU driver | Xorg driver + kernel DRM | Kernel DRM only |
| Wine compat | Full (winex11.drv mature) | Partial (winewayland.drv newer) |
| Nvidia support | Full (proprietary driver) | Improved (EGLStreams → GBM) |
| Screenshot | Any client can screenshot | Requires portal/extension |

## Why This Matters for Gaming

### Xorg + i3

- **Wine runs perfectly** — `winex11.drv` is battle-tested, WineD3D creates
  OpenGL contexts without issues
- **But 2D desktop is slow** — Xorg `modesetting` with glamor translates all
  2D drawing through OpenGL, which is slow on SVGA3D (protocol translation
  overhead)
- **Mitigation** — disable glamor, use `AccelMethod "none"` for raw
  framebuffer (faster on VMware)

### Wayland + Sway

- **Desktop is smooth** — Sway uses DRM directly, no OpenGL translation for
  2D compositing. No driver-related 2D overhead
- **Wine is broken** — The Wayland wine driver fails any standalone .exe with
  `could not load kernel32.dll` (only `winecfg` works). Xorg was chosen as a
  workaround. (On real GPUs with `winewayland.drv`, many games work well —
  this is specific to the no-3D-accel setup.)

### Two-Session Strategy

Run separate sessions for separate needs:

1. **Sway (Wayland)** — daily driving, web browsing, terminal work. Fast,
   smooth, secure
2. **i3 (Xorg)** — gaming via wine. Slower desktop but fully functional wine

Switch at the ly-dm login screen. No reboot needed — just log out and pick
the other session.
