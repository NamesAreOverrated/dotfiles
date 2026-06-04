# VMware VM Setup

## VM Specs

- **Hypervisor**: VMware (likely Workstation/Player)
- **GPU**: VMware SVGA II Adapter (PCI 15ad:0405)
- **Display**: ultrawide (e.g. 3440x1440)
- **3D Acceleration**: Enabled — required for OpenGL/3D rendering (see below)

## What "3D Acceleration" Does

### What it is

VMware's "3D acceleration" checkbox sets `mks.enable3d = "TRUE"` in the
VMX file, telling the hypervisor to allocate a 3D command FIFO and
additional graphics memory on the virtual SVGA II device.

The guest's `vmwgfx` kernel module binds to the SVGA II PCI device
(15ad:0405) regardless of this setting — it will still provide basic
KMS modesetting as a DRM driver. But without the checkbox:
- No 3D command FIFO is available; Mesa SVGA3D cannot create
  OpenGL contexts
- Graphics memory is capped very low
- Dumb buffer content stays entirely in guest memory (no host-side
  synchronization) — confirmed by CVE-2024-46712

With the checkbox:
- The 3D FIFO allows `vmwgfx` to forward rendering commands to the
  host GPU via the hypervisor
- Mesa's SVGA3D Gallium driver provides OpenGL by translating GL
  commands to SVGA3D protocol packets submitted to the hypervisor
  for host GPU execution

### Why it's called that

The SVGA II adapter is a real 3D-capable GPU. Its virtual hardware protocol maps
to roughly DirectX 9-class features. On Windows, the VMware WDDM driver
translates guest DirectX commands directly to the SVGA3D protocol
(no Mesa GL compiler stack), so performance is better than the Linux
path — but still has two
translation layers (guest driver → SVGA3D → hypervisor → host GPU), so it's
not near-native. The checkbox name reflects what the hardware *can* do, not
what Linux does with it.

### Why 3D is still slow on Linux

The guest-side Mesa Gallium driver (`SVGA3D`) cannot access the host GPU
directly. Every GL call must be translated to an SVGA3D command, serialised
through the FIFO to the hypervisor, and executed on the host GPU — with the
result sent back. This translation round-trip is the bottleneck visible in
WineD3D games, not shader compilation (the guest does only a lightweight
TGSI→SVGA3D opcode mapping, not a JIT). The 2D scanout (framebuffer → display) is still done in hardware by the
hypervisor, which is why Sway's desktop feels smooth at 3440×1440 even
though 3D games don't.

### Rendering Paths Explained

**2D desktop compositing (Linux guest) — why it's fast:**

```
app → compositor (Sway) → DRM/KMS (vmwgfx) → hypervisor scanout → monitor
                                         ↑
                               sends pre-rendered pixel buffer
                               (framebuffer blit over SVGA FIFO)
```

The compositor (Sway, Xorg modesetting) renders desktop windows into a
framebuffer in guest memory, then hands that finished buffer to `vmwgfx`
via DRM/KMS. `vmwgfx` transfers it to the hypervisor via the SVGA device's
DMA mechanism. The hypervisor displays it directly — no translation, no
per-frame command processing. This is a bulk data transfer, similar to
video RAM → display engine on real hardware. The scanout engine in the
hypervisor handles it with near-zero per-frame overhead, which is why
high resolutions (3440×1440) are smooth for 2D.

**3D rendering (Linux guest via Mesa SVGA3D) — why it's slow:**

```
game → WineD3D → Mesa SVGA3D Gallium driver
                    ↓
            GL state translation → SVGA3D commands
            (TGSI opcode mapping + state tracking, guest CPU)
                    ↓
            vmwgfx → hypervisor (translates SVGA3D → host GPU calls)
                    ↓
            host GPU driver → host GPU (real hardware rendering)
                    ↓
            host display
```

The critical bottleneck: Mesa's `SVGA3D` Gallium driver does not have
access to a real 3D pipeline in the hypervisor. Instead, it emulates
one entirely in the guest:

1. **Protocol translation**: Every GL call (state change, draw,
   resource upload) must be translated to an SVGA3D command packet
   and serialised through the guest→hypervisor FIFO. The Mesa state
   tracker compiles GLSL to TGSI, then the svga driver maps TGSI
   opcodes to SVGA3D opcodes via a simple lookup (no JIT). The
   per-call translation overhead adds up across thousands of draw
   calls per frame.
2. **State tracking**: DirectX 8 render states (blend modes, texture
   stages, clipping) are translated to SVGA3D command sequences.
   Each state change is a CPU operation in the guest.
3. **Command submission**: The compiled SVGA3D command buffers are sent
   via vmwgfx to the hypervisor, which translates them into host GPU
   driver calls (Vulkan, DirectX, or OpenGL on the host). The host GPU
   does the actual pixel rendering. The protocol translation and state
   tracking in the guest are the bottleneck, not the host-side execution.

The result: 3D rendering is guest CPU-bound. The host GPU is capable
of hardware rendering, but it must wait for the guest to finish
protocol translation and state tracking before it receives commands.
The bottleneck is on the guest side — the CPU is doing the heavy
lifting of translating OpenGL into SVGA3D commands.

**Windows guests** use VMware's WDDM driver which translates DirectX to the
SVGA3D protocol directly (bypassing Mesa's GL compiler stack). Performance
is better than the Linux path for games, but the hypervisor still adds
translation latency vs native hardware.

Sources:
- Mesa SVGA3D docs — classified as a "layered driver" for Linux guests
  accessing the host GPU (https://docs.mesa3d.org/drivers/svga3d.html)
- OpenGL 4.3 on Linux, DirectX 11 on Windows — VMware Workstation 17 spec
  (same docs page)
- SVGA3D renderer string "LLVM" refers to Gallium draw module fallback,
  confirmed from svga_tgsi_insn.c (TGSI→SVGA3D opcode table, not JIT)

## Graphics Stack

### Kernel Driver

`vmwgfx` — loaded automatically, provides DRM render node:

```bash
ls /dev/dri/        # card0 + renderD128
lsmod | grep vmw    # vmwgfx, vmw_balloon, vmw_vmci
```

### Mesa/Gallium

- Vendor: VMware, Inc.
- Renderer: SVGA3D; build: RELEASE; LLVM;
- OpenGL: 4.3 (Compatibility Profile)
- Mesa version: 26.x.x-arch (rolling, updated regularly)

⚠️ The "LLVM" in the renderer string refers to the Gallium draw module
(software vertex-processing fallback for edge cases where the SVGA3D
hardware path can't handle a shader), not to shader JIT compilation.
The main rendering path is TGSI→SVGA3D opcode mapping (a simple lookup)
on the guest, with actual shader execution on the host GPU.

### Xorg Driver

**DO NOT USE `xf86-video-vmware`** — it fails on modern kernels (>=5.x).

**Why it fails:** The vmware driver calls `xf86EnableIO()` to access legacy ISA
I/O ports (0x0000–0x03ff) for VGA register control. Modern kernels restrict
this via `ioperm()` — only root or processes with `CAP_SYS_RAWIO` can call it.
Xorg runs as a user process (via systemd-logind), so the call fails with
`Operation not permitted`.

**Why it's worse than falling back:** After the I/O port failure, the driver
can't initialize its native 2D acceleration (Gallium3D Xa). It disables all
render acceleration:

```
Failed to initialize Gallium3D Xa. No render acceleration available.
Render acceleration is disabled.
Direct rendering (DRI2 3D) is disabled.
AIGLX: Screen 0 is not DRI2 capable
GLX: Initialized DRISWRAST GL provider for screen 0
```

Both 2D desktop drawing **and** 3D OpenGL fall to pure software (LLVMpipe).
This is even slower than `modesetting` with glamor (which at least has GPU
OpenGL), and *much* slower than `modesetting` with glamor disabled (the
recommended config — see `freelancer-setup.md`). In short: the vmware driver makes
everything worse.

### `modesetting` — what it is

`modesetting` is Xorg's **generic** display driver that works with any GPU
that supports kernel modesetting (KMS). Instead of talking to the GPU hardware
directly (like proprietary drivers or chipset-specific Xorg drivers), it
communicates through the kernel's DRM (Direct Rendering Manager) interface —
the same interface Wayland compositors like Sway use.

For 2D acceleration, `modesetting` has two paths:
- **glamor** (default) — translates 2D drawing into OpenGL calls via the
  Mesa/Gallium driver (e.g., SVGA3D on VMware). This works everywhere but can
  be slow on GPUs with high OpenGL overhead.
- **framebuffer only** (`AccelMethod "none"`) — disables glamor, draws 2D via
  simple CPU framebuffer operations (`memcpy`, fill rects, etc.). Faster on
  VMware because it avoids the SVGA3D protocol translation overhead.

**Use `modesetting` driver instead** — it works with the vmwgfx kernel driver
via DRM/KMS. Disable glamor for better 2D performance (see `freelancer-setup.md`).

### Wayland (Sway)

- Sway works well via vmwgfx DRM directly (no Xorg involved)
- Smooth at high resolutions (e.g. 3440x1440)
- XWayland is available but **broken** — missing ISO8859 bitmap fonts kill any window-creating X11 client
- Fix: `pacman -S xorg-fonts-misc` may help (untested)

## Limitations

- **No Vulkan** — VMware SVGA II doesn't support Vulkan
- **No DXVK** — DirectX 10/11 games must use WineD3D (OpenGL translation)
- **No hardware video decode** — all video is CPU-decoded
- **SVGA3D OpenGL is slow for 3D rendering (games)** — every GL call must traverse guest→hypervisor→host GPU and back. Acceptable for desktop compositing on X11+glamor at the cost of CPU overhead

## VMware Tools

Optional but recommended for better integration:

```bash
sudo pacman -S open-vm-tools
sudo systemctl enable --now vmtoolsd
```

Clipboard sharing, better mouse integration, drag-and-drop, etc.

## Performance Tips

- Use `modesetting` with `AccelMethod "none"` for Xorg — faster 2D than glamor on SVGA3D
- Use Sway/Wayland for daily driving (lighter 2D path)
- Use Xorg + i3 only for wine gaming
- Set a lower resolution in gaming sessions for better performance: `xrandr -s <width>x<height>`
- Avoid compositors (picom, etc.) on Xorg — they're slow on SVGA3D
