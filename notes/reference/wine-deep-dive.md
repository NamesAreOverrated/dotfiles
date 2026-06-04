# Wine Deep Dive

## Architecture

### The Three-Layer Model

Wine is not an emulator. It's a **compatibility layer** that implements the
Windows API on top of Linux/POSIX. Three layers work together:

```
Windows .exe / .dll
    ↓
Wine DLLs (ntdll, kernel32, user32, gdi32, etc.)
    ↓
POSIX syscalls / X11 or Wayland / ALSA / PulseAudio / OpenGL
```

Each Windows system DLL (kernel32, user32, gdi32, d3d9, etc.) has a wine
equivalent written from scratch using Linux APIs. When a game calls
`CreateWindowExW()`, wine's `user32` translates that to an X11 `CreateWindow`
or Wayland `xdg_surface` call.

### wineserver

Every wine prefix runs a background **wineserver** process. It provides:

- **Named pipe / RPC** — all wine processes in the same prefix communicate
  through wineserver (not kernel pipes). It's the NT Object Manager analogue
- **Registry** — wineserver caches registry hives in memory, syncs to
  `system.reg` / `user.reg` on flush
- **NT synchronization** — implements `CreateEvent`, `CreateMutex`,
  `WaitForSingleObject` etc. via POSIX futexes + signal handling
- **Async I/O** — overlapped I/O completion ports via epoll
- **Console** — Windows console handling (CONOUT$, Ctrl-C, etc.)

Startup chain:

```
wine executable.exe
  → fork wineserver (if not running)
  → map loader (wine64-loader or wine32-loader)
  → load ntdll.dll → kernel32 → ... → entry point
```

### WoW64: PE → ELF

Windows executables are PE (Portable Executable) format. Wine has two loaders:

- **wine64** — loads 64-bit PE files, maps them into a 64-bit address space
- **wine32** (aka `wine` or `wine-preloader`) — loads 32-bit PE files, may
  need `WINEARCH=win32` prefix

On a 64-bit system with a `win64` prefix, both loaders exist. The **WoW64**
layer (Windows-on-Windows) allows running 32-bit apps in a 64-bit prefix:
`wine` launches the 32-bit loader, `wine64` launches 64-bit.

The loader is ELF binary that:
1. Reserves address space (`mmap` with `MAP_32BIT` for 32-bit)
2. Reads the PE header, maps sections at their preferred addresses
3. Resolves import tables (IAT) by loading required DLLs
4. Transfers control to the entry point

Wine's `ntdll` acts as the glue — it implements NT kernel-user boundary calls
using `syscall` instruction (on x86-64) or `int 0x80` (on x86), translating
them to wineserver RPC or POSIX syscalls.

## Prefix Anatomy

A wine prefix is a directory containing:

```
<prefix>/
├── dosdevices/
│   ├── c: → ../drive_c/      (C: drive)
│   └── z: → /                (Z: drive = Linux root)
├── drive_c/
│   ├── windows/
│   │   ├── system32/         (64-bit system DLLs)
│   │   ├── syswow64/         (32-bit system DLLs in win64 prefix)
│   │   ├── fonts/
│   │   └── regedit.exe, notepad.exe, etc.
│   ├── Program Files/
│   ├── Program Files (x86)/
│   └── users/
│       └── <user>/
│           ├── AppData/
│           ├── Documents/
│           └── Desktop/
├── system.reg
├── user.reg
└── userdef.reg
```

### Registry Files

**system.reg** — `HKEY_LOCAL_MACHINE` hive. Contains:
- Hardware detection results (CPU, GPU, display info)
- Installed Windows version and service pack
- Installed DirectX version
- Driver whitelisting (`HKEY_LOCAL_MACHINE\Software\Wine\Drivers`)
- DLL override configuration (`HKEY_CURRENT_USER\Software\Wine\DllOverrides`
  in user.reg, but some overrides land in system.reg)

**user.reg** — `HKEY_CURRENT_USER` and `HKEY_CLASSES_ROOT`. Contains:
- Wine configuration (DLL overrides, graphics settings)
- Application-specific settings
- Window manager integration preferences

**userdef.reg** — template applied to new users when they first launch an app

These files are **not read directly** — wineserver caches them. They're
flushed to disk periodically and on clean shutdown. If wineserver crashes
(e.g. power loss), registry changes may be lost.

### Key Registry Paths

```
# DLL overrides (per-user)
HKEY_CURRENT_USER\Software\Wine\DllOverrides

# Windows version per app
HKEY_CURRENT_USER\Software\Wine\AppDefaults\<app.exe>\*

# Graphics driver selection
HKEY_CURRENT_USER\Software\Wine\Drivers
  "Graphics" = "x11" (or "wayland", "x11,wayland")

# Direct3D settings
HKEY_CURRENT_USER\Software\Wine\Direct3D
  "DirectDrawRenderer" = "opengl" | "gdi"
  "MaxVersionGL" = 0x00030002  (max OpenGL version, e.g. 3.2)
  "OffscreenRenderingMode" = "fbo" | "backbuffer"
  "UseGLSL" = "enabled" | "disabled"

# Staging-specific
HKEY_CURRENT_USER\Software\Wine\Staging
  "CSMT" = "enabled" | "disabled"
```

## WineD3D: DirectX → OpenGL Translation

### How It Works

WineD3D (`d3d8.dll`, `d3d9.dll`, `d3d10.dll`, `d3d11.dll`) translates
DirectX calls to OpenGL. The pipeline:

```
Game calls:  DrawIndexedPrimitive(D3DPT_TRIANGLELIST, ...)
    ↓
d3d9.dll receives call
    ↓
wined3d translates state block → GL state
    ↓
Generates GLSL shader from DX9 vertex/pixel shader bytecode
    ↓
Calls: glDrawElements(GL_TRIANGLES, ...)
    ↓
Mesa/Gallium SVGA3D driver processes GL → GPU (or LLVMpipe)
```

### State Block Tracking

DX9 uses a massive state machine (render states, texture stages, transforms,
lights, materials). WineD3D tracks every dirty state and applies it lazily:

```c
// Simplified: before each draw call, apply dirty states
if (dirty & DIRTY_VIEWPORT)
    glViewport(viewport.x, viewport.y, viewport.w, viewport.h);
if (dirty & DIRTY_SCISSOR)
    glScissor(scissor.rect);
if (dirty & DIRTY_RENDERSTATE_ALPHABLEND)
    glEnable(GL_BLEND) / glDisable(GL_BLEND);
// ... dozens more
```

This is where `WINED3D_RS_ZVISIBLE not implemented` and similar fixmes come
from — wine doesn't handle every single render state, and on less common
states it just logs a fixme and skips.

### Shader Conversion

DX9 shaders (bytecode) are converted to GLSL at runtime. WineD3D includes
a bytecode-to-GLSL compiler:

```
DX9 VS (Vertex Shader):
  dcl_position v0
  dcl_normal v3
  m4x4 oPos, v0, c0     // transform by world-view-projection
  m4x4 oT0, v3, c4      // transform normal by world matrix

→ GLSL (Vertex Shader):
  void main() {
      gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
      gl_TexCoord[0] = gl_ModelViewMatrix * gl_Normal;
  }
```

When WineD3D encounters a **texture format it can't map to OpenGL**, it logs:
```
fixme:d3d:debug_d3dformat Unrecognized WINED3DFORMAT!
fixme:d3d:wined3d_get_format Can't find format in the format lookup table.
```

This happens when the game uses a proprietary or uncommon D3D format (like
DXT5 swizzled for console ports). Wine falls back to a default format, which
may look wrong or cause an extra copy. These are harmless but spam the log.

### Why WineD3D Is Slow

1. **State translation overhead** — every DX draw call requires validating and
   applying the D3D state machine → GL state. Native D3D on Windows has the
   same work in-kernel, but wine does it in userspace with GL calls
2. **GLSL compilation** — DX shaders must be converted to GLSL and compiled
   (via `glCompileShader`). The LLVM-based GLSL compiler in Mesa adds
   significant per-shader overhead
3. **No direct state access (DSA)** — wine must call `glBindBuffer`,
   `glBufferSubData`, etc., while native D3D uses DMA from user-mode driver
4. **Buffer copying** — on WoW64, `wow64_map_buffer` copies mapped buffer
   contents between 32-bit and 64-bit address spaces (the fixme:
   `Doing a copy of a mapped buffer (expect performance issues)`)

### DXVK vs WineD3D

DXVK translates DX10/11 directly to **Vulkan**, bypassing OpenGL entirely.
It's much faster (Vulkan has lower driver overhead, pre-compiled SPIR-V shaders,
no state translation layer). However, **VMware SVGA II doesn't support Vulkan**,
so DXVK can't be used here — all DX goes through WineD3D.

## DLL Override System

### Resolution Order

When wine needs a DLL (e.g., `d3d9.dll`), it searches in this order:

1. **Override table** — `HKEY_CURRENT_USER\Software\Wine\DllOverrides` or
   `WINEDLLOVERRIDES` env var. If the DLL is listed, apply the flags
2. **Application directory** — the same directory as the .exe
3. **System directories** — `C:\windows\system32` (64-bit) / `syswow64` (32-bit)
4. **Builtin** — wine's own implementation

### WINEDLLOVERRIDES Format

```bash
WINEDLLOVERRIDES="d3d9=n;d3d8=b,n;dinput.dll=b,n;winex11.drv=d"
```

| Flag | Meaning | Behavior |
|------|---------|----------|
| `b` | builtin | Use wine's implementation |
| `n` | native | Use the DLL from disk (game dir or system) |
| `d` | disable | Don't load this DLL at all |
| `b,n` | builtin first | Try builtin, fall back to native |
| `n,b` | native first | Try native, fall back to builtin |

### Common Overrides Explained

**`winex11.drv=d`** — Disables the X11 display driver. Without it, wine
can't create windows on X11. If a Wayland driver is available, wine attempts
to use that instead. Used to bypass broken XWayland.

**`ddraw=b`** — DirectDraw. GOG games often bundle `ddraw.dll` that wraps
DDraw in OpenGL (dgVoodoo or similar). On wine, this conflicts with WineD3D's
own DDraw→OpenGL path. `ddraw=b` uses wine's builtin DDraw which works
correctly.

**`dinput.dll=b,n`** — DirectInput. The game may ship its own `dinput.dll`
with modifications. `b,n` tells wine to prefer the builtin, which has better
compatibility with modern X11/Wayland input handling. Falls back to the game's
native DLL if the builtin fails to load.

**What the `d` flag actually does**: The DLL is removed from the module
list entirely. Any import table reference to it becomes a stub. If the game
has a hard dependency (it will crash without the DLL), `d` will break it.

## Winetricks Internals

### What `winetricks -q directplay` does

```bash
# Quiet mode (-q), run these in order:
regsvr32 dplayx.dll     # DirectPlay 4 / Legacy DirectPlay
regsvr32 dpnet.dll      # DirectPlay 8 (used by Freelancer)
regsvr32 dpnhpast.dll   # DirectPlay NAT Helper PAST
regsvr32 dpnhupnp.dll   # DirectPlay NAT Helper UPnP
```

`regsvr32` loads the DLL and calls its `DllRegisterServer` export, which
writes COM class IDs, interface IDs, and AppID entries to the registry:

```
HKCR\CLSID\{...}  →  DllSurrogate, AppID, etc.
HKCR\AppID\{...}  →  DllSurrogate, RunAs
HKLM\Software\Microsoft\DirectPlay\...
```

Without this registration, CoCreateInstance for DirectPlay objects fails.
Freelancer calls `CoCreateInstance(CLSID_DirectPlay8Client)` on startup — if
this fails, the game either hangs or shows "DirectPlay not installed."

## Debug Channels

### WINEDEBUG Syntax

```bash
WINEDEBUG="+d3d"              # Enable d3d channel
WINEDEBUG="+d3d,+dsound"      # Multiple channels
WINEDEBUG="-all"              # Disable everything (quiet)
WINEDEBUG="fixme-all"         # Only FIXME messages
WINEDEBUG="warn+all"          # All warnings
WINEDEBUG="+loaddll"          # DLL load/unload tracing
WINEDEBUG="+relay"            # API call trace (extremely verbose)
```

### Channel Levels

Each channel has four message classes:

| Class | Prefix | Meaning |
|-------|--------|---------|
| FIXME | `fixme:module:function` | Unimplemented functionality |
| WARN  | `warn:module:function`  | Potential problem, handled |
| ERR   | `err:module:function`   | Recoverable error |
| TRACE | `trace:module:function` | Detailed flow information |

**`fixme:d3d:wined3d_get_format`** means "this code path isn't fully
implemented yet, but we'll try to continue anyway."

### The `+relay` Channel

`WINEDEBUG=+relay` prints every API call and return value — effectively a
complete execution trace. Useful for finding where a crash happens, but
produces gigabytes of output for any real application.

## Console vs GUI — Why wineboot Hangs

### Windows Subsystem Types

PE executables declare their subsystem in the header:

| Subsystem | Value | Example |
|-----------|-------|---------|
| CONSOLE   | 3     | `cmd.exe`, `wineboot` |
| WINDOWS   | 2     | `notepad.exe`, game `.exe` |
| NATIVE    | 1     | Kernel drivers (not in wine) |

### What Happens at Startup

**CONSOLE** apps (like `wineboot`):
1. wineserver creates a console endpoint (`CONOUT$`)
2. The process is attached to the console via `AttachConsole()`
3. Console I/O goes through wineserver's console handler
4. **On this system**: the console's signal handling (SIGTERM, SIGCHLD from
   child processes) or pseudo-tty allocation deadlocks — likely a race
   between wineserver's signal handler and the kernel's TTY layer

**WINDOWS** apps (like `wine winecfg`):
1. wine creates a message queue and window via the display driver (X11/Wayland)
2. No console I/O, no pseudo-tty needed
3. The GUI path avoids the console initialization entirely

**Why winecfg works as a workaround**: `wine winecfg` runs the Wine
Configuration tool, which is a WINDOWS subsystem executable. It triggers the
same wineserver initialization and prefix creation as `wineboot`, but skips
the console setup. After it completes, the prefix is fully initialized and
subsequent runs (even CONSOLE apps) work because wineserver is already
running and the `drive_c` directory structure exists.

## Display Drivers

### winex11.drv

The X11 driver is the most mature wine display backend. It:

1. Creates an X11 window for each Windows window
2. Maps GDI coordinates to X11 coordinates
3. Handles input events (X11 → Windows message translation)
4. Manages OpenGL contexts (via `glXMakeCurrent`)
5. Handles clipboard, drag-and-drop via X11 protocols
6. Supports Vulkan via `VK_KHR_xlib_surface` or `VK_KHR_xcb_surface`

On Xorg, this works perfectly. On Wayland via XWayland, the X11 driver still
works — but it's talking to XWayland (a translation layer), not the native
Wayland compositor. XWayland has limitations:
- No GLX acceleration in some configurations
- Font path issues (as seen here)
- Input coordinate mapping differences
- Performance overhead (X11 → XWayland → Wayland double translation)

### winewayland.drv

The Wayland driver is newer (added in Wine 9.x, matured in 10.x). It:

1. Creates `wl_surface` / `xdg_surface` objects (no XWayland involved)
2. Maps GDI coordinates to Wayland logical coordinates (scaled by
   `wl_output` scale factor)
3. Uses `libdecor` or `xdg-decoration` for window decorations
4. Handles input via `wl_pointer`, `wl_keyboard`, `wl_touch`
5. Manages OpenGL contexts via `EGL_KHR_platform_wayland`
6. **Does not support Vulkan** — no `VK_KHR_wayland_surface` is used yet

**Note:** On this specific system, any standalone Windows executable run
through the Wayland driver fails immediately with `could not load kernel32.dll
(error c0000135)`. The cause wasn't investigated — once the i3/Xorg
workaround was found, there was no reason to dig deeper. Only `winecfg`
works (launched through wine's internal mechanism, not as a standalone PE).

## Graphics Pipeline End-to-End (Freelancer Example)

```
Freelancer.exe (DX8)
    ↓
d3d8.dll (WineD3D)
    ↓ calls wined3d
        → Create device (D3D8 → OpenGL context)
        → Create vertex buffers (glGenBuffers, glBufferData)
        → Create textures (glGenTextures, glTexImage2D)
            → DXT1/3/5 decompression for unrecognized formats
            → "fixme: Unrecognized WINED3DFORMAT" for DAOP/DAA8
        → Load shaders
            → DX8 fixed function → GLSL generation
            → glCompileShader (LLVM compilation in Mesa)
        → Render loop:
            → Apply state block (dozens of glEnable/glDisable/gl* calls)
            → glDrawElements (draw call)
            → wglSwapBuffers (present → VSync wait)
    ↓
Mesa SVGA3D Gallium driver
    ↓
vmwgfx kernel DRM driver
    ↓
VMware SVGA II (virtual GPU)
    ↓
Hypervisor presents frame
```

The `fixme:d3d:wined3d_device_apply_stateblock` messages mean wine doesn't
implement every single D3D render state — the game requests features like
`ZVISIBLE` or `PATCHSEGMENTS` that wine's state tracker doesn't handle.
Wine logs the fixme and skips them. The game continues, but may miss some
rendering features.
