# Steam Setup

Target: Steam on VoidLinux-musl host (bare metal) via Distrobox (Arch container), sway/niri.

---

## Step 1: Host preparation

Disable IPv6 via sysctl. Add to `/etc/sysctl.d/`

```conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
```

This persists across reboots and NetworkManager won't reset it. You can confirm IPv6 is gone with

```bash
nmcli -f IP6.ADDRESS dev show enp132s0
```

An empty output means IPv6 is off.

Steam's internal NetworkManager client talks to the host over D-Bus, so make sure the host's NetworkManager and the system D-Bus bus are running (they are by default).

### File descriptor limits

The kernel defaults to 4096 open file descriptors per process. Games under Proton can chew through that on sync primitives, inter-process communication and asset reads — Steam prints `Low file descriptor limit: 4096` when it's the bottleneck, and DX9-era games crash at low pointer addresses (`eip=0x158`-style) once a failed file open returns a bad handle.

Wine raises its own soft limit up to the *hard* ceiling at runtime, so only the hard limit matters. Keep the soft low — a high soft limit breaks `select()`-based games and slows Steam launch. `pam_limits.so` is already active in `/etc/pam.d/system-auth`, so just drop a file in:

```bash
printf '%s soft nofile 1024\n%s hard nofile 524288\n' "$USER" "$USER" \
  | sudo tee /etc/security/limits.d/99-nofile.conf
```

This applies to **new login sessions** — log out and back in (or restart the session), then verify:

```bash
ulimit -Hn   # → 524288
```

> Rootless podman clamps container limits to the invoking user's hard limit, and rlimits are frozen into the container's OCI spec at `distrobox create` time — so the hard limit must exist on the host *before* you create the box (Step 2 passes it in via `--ulimit`).

### zram (compressed RAM swap)

Void's `zramen` runit service (`/etc/sv/zramen/run` → `zramen make`) creates a compressed swap in RAM. Effective size = `ZRAM_SIZE`% of total RAM, capped at `ZRAM_MAX_SIZE` MiB (defaults 25 / 4096). Tune it in `/etc/sv/zramen/conf`:

```conf
ZRAM_SIZE=25
ZRAM_MAX_SIZE=4096
```

Note: `zramen make -m 6144` does **not** resize it — `-m` is only a cap; the `%`-of-RAM (`ZRAM_SIZE`) is what sets size. zram gets the highest kernel swap priority (32767), so it's used before any disk swap.

### Swapfile (btrfs host)

The host root is btrfs, which refuses swapfiles that have CoW enabled (`swapon: Invalid argument`). Mark the file NoCOW **before** any data is written to it:

```bash
truncate -s 0 /swapfile
chattr +C /swapfile
fallocate -l 16G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

Persist it in `/etc/fstab` — keep its priority below zram, so it's a backstop rather than primary:

```
/swapfile none swap defaults,pri=-2 0 0
```

Verify after reboot with `swapon --show` (expect `zram0` at 32767 and `/swapfile` at -2).

### Memory tuning

Low `max_map_count` causes Vulkan games to fail with "device lost" or outright crashes. `vm.swappiness` biases how eagerly the kernel uses swap. Apply both:

```bash
echo "vm.swappiness=10"         | sudo tee -a /etc/sysctl.conf
echo "vm.max_map_count=1048576" | sudo tee -a /etc/sysctl.conf
sudo sysctl --system
```

Confirm with `cat /proc/sys/vm/max_map_count /proc/sys/vm/swappiness`.

> `vm.max_map_count` caps how many memory mappings (VMAs) one process may hold. Each map is a region of mapped memory — a shared library, a `malloc`/heap allocation, a thread stack, shared memory, or an `mmap`ed file (see `cat /proc/<pid>/maps`). Games under Proton/DXVK allocate many small maps (shader blobs, file mmaps), and exhausting the default 65530 makes the kernel fail new `mmap()` calls — Vulkan "device lost" or outright crashes. 1048576 is just headroom.
>
> Both knobs are **host-wide kernel sysctls, not per-process rlimits**. The box shares the host kernel, so it inherits them automatically — that's why neither gets a `--ulimit`/`--sysctl` flag at create time. Only rlimits like `nofile` get one, because they're frozen into the container's OCI spec (see the *Why the ulimit* note in Step 2).

## Step 2: Create the Steam box

Determine where you want to put your distrobox and its name.

example path is `~/boxes`
example name is `steambox`

```bash
mkdir -p ~/boxes/steambox
```

Make the box. The `--volume` here is the critical part, don't leave it out.

```bash
distrobox create --name steambox \
                 --image archlinux:latest \
                 --home ~/boxes/steambox \
                 --volume /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
                 --additional-flags "--ulimit nofile=1024:524288" \
                 --unshare-process
```

**Why the ulimit:** rlimits are baked into the container's OCI spec at create time and can't be raised later from inside. The host hard limit from Step 1 must already be 524288, otherwise podman quietly clamps the container back to 4096. To change it you must recreate the box with the flag — editing `config.json` afterwards doesn't work (podman regenerates it from its own database on every start).

**Why the volume:** Steam will hang on "Waiting for network" forever if it can't reach the host's D-Bus system bus. Its internal NetworkManager client connects to the host over D-Bus; without this socket you get

- `client_networkmanager.txt` → `Init: failed to create a NetworkManager client`
- `webhelper-linux.txt` → `Failed to connect to socket /run/dbus/system_bus_socket`

while `connection_log.txt` still says `Connected` — hence the confusing split where the client is up but Steam thinks it has no network.

**Note:** don't try to add mounts afterward by editing podman's `overlay-containers/<id>/userdata/config.json`. Podman regenerates that file from its own database on every start and will wipe your manual edits. The `--volume` flag at create time is the only reliable way.

## Step 3: Prepare the box

Enter the box

```bash
distrobox enter steambox
```

Enable `multilib` on Arch. Add or uncomment.

```toml
#/etc/pacman.conf
[multilib]
Include=/etc/pacman.d/mirrorlist
```

Update `pacman`

```bash
sudo pacman -Syu
```

Install `pactl` for audio control

```bash
sudo pacman -S libpulse
```

Install Vulkan drivers (Intel in my case)

```bash
sudo pacman -S vulkan-intel lib32-vulkan-intel mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader
```

Install Steam and gamescope

```bash
sudo pacman -S steam gamescope
```

## Step 4: gamescope

On sway/niri, Steam — and every game it launches — really should run through `gamescope`. Steam's UI is built around a fixed-size surface, and without gamescope to map it into the compositor it comes up wrong: the UI scatters around the screen and mouse clicks land everywhere except where they should. Gamescope snaps it into a single proper window where input actually tracks the cursor.

An alternative to gamescope: float Steam's windows instead, so the UI comes up as one normal window. On sway:

```
# sway config
for_window [class="Steam"] floating enable
```

(niri has no floating concept, so there gamescope — or a fixed-size rule — is the only option.)

There is one ownership gotcha. The host's `/tmp` is a tmpfs, and the box's `/tmp` is just a bind mount of it, so both see the same X sockets. Gamescope needs `/tmp/.X11-unix` to be owned by your user:

```bash
chown $USER /tmp/.X11-unix/X0
```

After that a dry-run of gamescope produces no errors.

**Caveat:** the host `/tmp` is wiped on reboot, so this chown does **not** persist. Either re-run it after every boot or hook it into your session startup.

## Step 4.5: Performance (optional)

### GE-Proton

Valve's stock Proton is conservative: it lags behind the latest Wine and can't ship media codecs (licensing). GE-Proton (GloriousEggroll) is the community build — newer Wine + DXVK, extra codecs for cutscene-heavy games, and per-game patches. Install a tarball into the box's `compatibilitytools.d` (inside the box home; `~/.steam/root` is a symlink to `~/.steam/steam`):

```bash
mkdir -p ~/.steam/steam/compatibilitytools.d
tar -xzf ~/Downloads/GE-Proton11-3.tar.gz -C ~/.steam/steam/compatibilitytools.d/
```

Restart Steam, then per game: right-click → Properties → Compatibility → "Force the use of a specific Steam Play compatibility tool" → pick GE-Proton. Default to stock Proton for games that already work; switch to GE-Proton when a game has black cutscenes, crashes, or ProtonDB reports suggest it.

### Shader pre-caching

First-launch stutter is almost always shader compilation. Let Steam pre-bake it: Settings → Downloads → enable **Shader Pre-Caching** (and "Allow background processing of Vulkan shaders"). This is the modern form of the old `RADV_PERFTEST=aco` trick — ACO is the default RADV compiler on Mesa ≥ 20, so nothing to set there anymore.

Pre-compilation may only use one core by default; give it more threads via `~/.steam/steam/steam_dev.cfg`:

```
unShaderBackgroundProcessingThreads 8
```

### Feral GameMode

GameMode (`gamemode` + `lib32-gamemode`) re-nices the game, bumps I/O priority and tries to set the CPU governor to `performance` while a game runs:

```bash
sudo pacman -S gamemode lib32-gamemode
```

Prefix a game's launch options with `gamemoderun`:

```
gamemoderun %command%
```

Verify it's active while the game runs with `gamemoded -s`. **Caveat:** inside a rootless distrobox the daemon can't write `/sys/devices/system/cpu/` (governor changes need host root), so on this setup GameMode mostly buys the renice/I/O boost. If you want the CPU-governor kick too, run `gamemoded` on the host instead.

### MangoHud

MangoHud is the FPS/frametime/temp overlay — the way to actually see whether you're CPU-, GPU- or RAM-bound:

```bash
sudo pacman -S mangohud lib32-mangohud
```

Activate it per game with `mangohud %command%`. When running through gamescope (as this setup does), don't inject MangoHud into the game — traditional injection isn't supported under gamescope; use its `--mangoapp` flag instead (see the gamescope flags table). Configure the overlay layout in `~/.config/MangoHud/MangoHud.conf` (defaults are fine to start).

## Step 5: Launch and verify

Launch Steam through gamescope inside the box

```bash
distrobox enter steambox -- gamescope -w 1920 -h 1080 -- steam
```

Then check `~/boxes/steambox/.local/share/Steam/logs/`:

- `client_networkmanager.txt` → `Init: create NetworkManager client: success`
- `webhelper-linux.txt` → no `bus.cc(407) Failed to connect to the bus` errors

If both look right, login works.

## Step 6: Flags

### Proton environment variables

Set these on the game's Steam launch-options line, **before** `%command%`. Rows tagged *GE-Proton only* need GE-Proton from Step 4.5; the untagged ones work on stock Proton too. The full list of GE-Proton options (and the `Compat config string` equivalents) lives in the [upstream options table](https://github.com/GloriousEggroll/proton-ge-custom#options):

| Variable | What it does |
|---|---|
| `PROTON_USE_WINED3D=1` | Use OpenGL-based wined3d instead of Vulkan-based DXVK (d3d9/d3d10/d3d11). Smoother for old DX9 titles that compile shaders at runtime (e.g. Mars War Logs) at the cost of some ShaderModel 3 / Cg effects. iGPU-friendly. |
| `PROTON_NO_D3D12=1` | Disable d3d12.dll (DX12). Pair with `PROTON_NO_D3D11=1` to force DX9/DX11 paths. |
| `PROTON_NO_D3D11=1` | Disable d3d11.dll, for d3d11 games that can fall back to and run better on d3d9. Use `PROTON_NO_D3D10=1` / `PROTON_NO_D3D9=1` similarly. |
| `PROTON_ENABLE_WAYLAND=1` | Run the game as a native Wayland client (Wine-Wayland driver) instead of XWayland. Better frame pacing and the only path to HDR. Experimental — breaks the Steam overlay and some launchers. Pair with `PROTON_ENABLE_HDR=1` for HDR. |
| `PROTON_FSR4_UPGRADE=1` | Auto-download AMD's FSR4 DLL and upgrade games that ship FSR 3.1. **RDNA GPUs only — a no-op on Intel iGPU, don't use.** |
| `PROTON_USE_OPTISCALER=1` | **GE-Proton only (11-1+).** Auto-downloads OptiScaler and injects its upscaler/frame-gen stack (DLSS-input FSR4, XeSS, frame generation without needing a DLSS-capable NVIDIA card). **Skips games that already ship a native upscaler.** Opt-in — can cause artifacts; use per-game. |
| `PROTON_XESS_UPGRADE=1` | **GE-Proton only.** Auto-download the latest Intel XeSS DLL for games shipping an older one. The Intel counterpart to FSR4/DLSS upgrades — relevant on Intel iGPU (gamescope's FSR is often the better bet). |
| `WINE_FULLSCREEN_FSR=1` | **GE-Proton only.** FSR upscaling via the fullscreen hack (`WINE_FULLSCREEN_FSR_STRENGTH` 0–5, higher = softer). Mostly redundant with gamescope `-F fsr`; useful if you run a game without gamescope. |
| `PROTON_USE_NTSYNC=1` | Use the kernel's ntsync (Windows NT sync primitives) instead of esync/fsync emulation. Needs kernel ≥ 6.14 with `CONFIG_NTSYNC` (GE-Proton's stated requirement; ntsync hit mainline in 6.15). On non-systemd hosts (Void/runit) also needs `ulimit -Hn` ≥ 524288 — already covered by Step 1's nofile limit. No-op if unsupported, so safe to set proactively. |
| `PROTON_NO_NTSYNC=1` | Turn ntsync off (e.g. if it misbehaves for a specific game). |
| `PROTON_NO_ESYNC=1` / `PROTON_NO_FSYNC=1` | Turn off eventfd/futex sync primitives. Try if a game crash is accompanied by fd exhaustion. |
| `WAYLANDDRV_PRIMARY_MONITOR=<output>` | Choose the monitor the Wayland driver uses (e.g. `DP-3`). Requires `PROTON_ENABLE_WAYLAND=1`; handy on multi-monitor setups. |
| `PROTON_LOG=1` | Write a debug log (default `$HOME/steam-<appid>.log`; set `PROTON_LOG_DIR` to redirect). |

### gamescope flags

| Flag | What it does |
|---|---|
| `-W`/`-H` / `-w`/`-h` | Output (display) resolution vs internal (game) resolution. Lower `-w/-h` = the FPS lever; gamescope upscales to `-W/-H`. |
| `-r` | Refresh rate (fps limit) for the game. |
| `-f` | Fullscreen. `-b` is borderless. |
| `--immediate-flips` | Immediate page flips — **enables tearing**. Slashes the input lag caused by two vsync-locked compositors (gamescope → sway). Requires `output <name> allow_tearing yes` (and optionally `max_render_time off`) in the sway config. |
| `-F fsr` + `--fsr-sharpness N` | FSR1 upscaling of the internal res to the output. `0` is max sharpness, `20` is softest. Needed for lower `-w/-h` to not look blurry. |
| `--adaptive-sync` | Enable VRR (FreeSync/GSync) if the monitor supports it. |
| `--force-grab-cursor` | Keep the mouse in relative mode; fixes unlimited camera panning inside gamescope. Use together with `-f`. |
| `--mangoapp` | Launch with MangoHud overlay; use this instead of `MANGOHUD=1` on the game. |
| `--backend drm` | Embedded mode (direct to the display from a TTY, no compositor). Best input latency but leaves your DE. Default is nested-under-Wayland. |

Toggle FSR/NIS sharpness and filter at runtime: `Super+U` (FSR), `Super+N` (nearest), `Super+I`/`Super+O` (sharpness).

### Example: Cyberpunk 2077

Cyberpunk ships its own FSR 2.1 upscaler, so you don't want it stacked with gamescope's FSR1 — gamescope runs at native res as a pure presenter, and the game's FSR quality preset does the upscaling internally. `--intro-skip` / `-skipStartScreen` / `--launcher-skip` are Cyberpunk's own args, passed after `%command%`:

```bash
PROTON_ENABLE_WAYLAND=1 gamescope -W 3440 -H 1440 -r 165 -w 3440 -h 1440 --immediate-flips -f -- %command% --intro-skip -skipStartScreen --launcher-skip
```

### OTHER THINGS

1. The gamescope `/tmp/.X11-unix` chown doesn't survive a reboot (host `/tmp` is tmpfs).
2. The D-Bus socket volume is persistent — podman stores it in its database at create time, so it survives box restarts.
3. `pactl` comes from the `libpulse` package on Arch.
