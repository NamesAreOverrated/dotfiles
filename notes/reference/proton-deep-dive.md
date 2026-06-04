# Proton Deep Dive

## What Proton Is

Proton is a **fork of wine** maintained by Valve/CodeWeavers for Steam Play.
It is not a separate project — it's wine with additional patches, DLLs, and
tooling bundled together to run Windows games on Linux.

```
Proton = wine (forked) + DXVK + VKD3D-Proton + FAudio + Steam integration
```

## How It Differs From Stock Wine

### 1. DXVK (DirectX 10/11 → Vulkan)

Stock wine translates DX10/11 through **WineD3D** (OpenGL). Proton ships
**DXVK**, which translates DX10/11 directly to **Vulkan**:

```
Game → D3D10/11 API → DXVK → Vulkan → GPU
```

Vulkan has lower driver overhead than OpenGL:
- Pre-compiled SPIR-V shaders (no runtime GLSL compilation)
- Explicit command buffers (no state tracking layer)
- Multi-threaded command recording
- Direct GPU memory management

**Result**: DXVK is significantly faster than WineD3D for most DX10/11 games
(actual gains vary by game, GPU, and driver).
On systems without Vulkan (like VMware SVGA II), DXVK can't be used.

### 2. VKD3D-Proton (DirectX 12 → Vulkan)

VKD3D-Proton translates **DirectX 12** to Vulkan. This is required for modern
games (2015+) that are DX12-only. Stock wine doesn't support DX12 at all via
WineD3D. Even with VKD3D-Proton, DX12 support is still maturing and many
games don't work perfectly.

### 3. DXVK for DX9 (dxvk-nvapi)

Proton also uses DXVK for **DirectX 9** (D3D9 → Vulkan), bypassing WineD3D.
This gives major performance improvements for DX9 games too (including many
that stock wine renders via OpenGL).

### 4. FAudio

Proton replaces wine's builtin XAudio2 implementation with **FAudio** — a
re-implementation of the DirectX audio API that's more complete and performant
than wine's. Fixes audio crackling, missing sound effects, and surround sound.

### 5. Wine-Staging Patches

Proton includes all **wine-staging** patches (experimental features that
haven't been merged into upstream wine, or were merged recently):
- ⚠️ CSMT (Command Stream Multi-Threading) — runs D3D commands on a separate
  thread, reducing stutter. Merged into upstream wine in 1.7.50 (2015); listed
  here for historical context as staging carried refinements after the merge
- VAAPI/VDPAU hardware video decoding
- Various game-specific fixes

### 6. Steam-Specific Integration

- **Steam overlay** — hooks the game process to inject the in-game overlay
- **Steam API** — implements `steam_api.dll` / `steam_api64.dll` so games
  that require Steamworks work without Steam
- **Protonfixes** — per-game configuration scripts (registry tweaks, DLL
  overrides, environment variables) applied automatically for thousands of
  games via the `protonfixes` system
- **Cloud saves** — maps Windows save paths to Steam Cloud
- **Proton logs** — built-in logging (`~/steam-<id>/proton.log`)

### 7. Wine Version

Proton is based on a specific wine version (e.g., Proton 9.0 = wine 9.x).
Valve backports game-specific fixes and ships point releases (9.0-1, 9.0-2)
as they fix more games. The upstream wine version is always a few months
behind latest wine — stability prioritized over bleeding edge.

## How GE-Proton Differs

**GE-Proton** (GloriousEggroll) is a community fork of Proton with additional
patches not yet in official Proton:

- Latest wine-staging patches merged earlier
- Additional game-specific hotfixes
- Media Foundation patches (fixes video cutscenes in many games)
- Fsync support (faster synchronization than esync)
- Various DXVK/VKD3D build tweaks

GE-Proton is what you have in `~/Games/GE-Proton*/`.

## Running Proton Outside Steam

Proton can run games without Steam:

```bash
# Find proton binary
# Find the GE-Proton directory
ls ~/Games/GE-Proton*/files/bin/
# → wine, winecfg, etc.

# Use it like stock wine
PATH="$(echo ~/Games/GE-Proton*/files/bin):$PATH" \
  WINEPREFIX=~/Games/wine-prefixes/<game> \
  wine game.exe
```

Proton's `wine` binary is the same wine as stock — you can use `winecfg`,
`wineboot`, all standard tools. The difference is in the bundled DLLs.

## The Proton Experience

When Steam launches a game through Proton, the flow is:

```
Steam → proton → steam-run (sets up environment)
    ↓
Creates prefix at ~/.steam/steam/steamapps/compatdata/<gameid>/
    ↓
Applies protonfixes for this gameid
    ↓
Sets WINEDLLOVERRIDES (e.g., dxvk → n)

Installs DXVK DLLs into system32:
    d3d10.dll, d3d10_1.dll, d3d10core.dll
    d3d11.dll, d3d9.dll
    dxgi.dll

Launches game.exe
```

On first launch, Proton:
1. Initializes a wine prefix (same `wine winecfg` mechanism)
2. Copies DXVK DLLs to `system32/`
3. Runs any install scripts from protonfixes
4. Records the game's registry settings
5. Launches the executable

## When to Use Proton vs Stock Wine

| Use Case | Stock Wine | Proton / GE-Proton |
|----------|-----------|-------------------|
| DX9 game with WineD3D | ✓ Works, may be slow | ✓ Faster via DXVK |
| DX10/11 game | ✓ Works, WineD3D slow | ✓ Much faster via DXVK |
| DX12 game | ✗ Not supported | ✓ Via VKD3D-Proton (may have issues) |
| No Vulkan GPU | ✓ WineD3D works | ✗ DXVK/VKD3D requires Vulkan |
| Old game (Diablo, Freelancer) | ✓ Works with caveats | ✓ Overkill, same result |
| Non-Steam game | ✓ wine command | ✓ PATH override or `proton run` |
| Media Foundation (cutscenes) | ⚠ Partial | ✓ Better via MF patches (GE) |
| Nvidia Reflex / DLSS | ✗ | ⚠ dxvk-nvapi (experimental) |

## Why Stock Wine Is Used Here

Despite having GE-Proton downloaded, the system wine-staging is used because:

1. **No Vulkan** — DXVK's main advantage is Vulkan, which VMware SVGA II
   doesn't support. Without DXVK, Proton degrades to WineD3D (same as stock).
2. **Proton's extras don't help** — FAudio, Media Foundation, Steam overlay
   are irrelevant for games like Freelancer (2003, no Steam, no cutscene video
   issues).
3. **Simpler debugging** — stock wine has fewer layers between you and the
   game. No auto-applied protonfixes, no DXVK injection.

If 3D acceleration were available (real GPU with Vulkan) and you were playing
modern DX10/11 games, switching to Proton or GE-Proton would be the first
step.
