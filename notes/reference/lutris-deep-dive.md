# Lutris Deep Dive

## What Lutris Is

Lutris is a **game launch orchestration layer** — a Python/PyGObject (GTK3) desktop
application that manages, installs, and launches games through external programs
called *runners*. It is not an emulator or compatibility layer itself. It wraps
Wine, Proton, RetroArch, DOSBox, ScummVM, native Linux binaries, and emulators
under a single library with automated install scripts. See
[wine-deep-dive.md](wine-deep-dive.md) for the full architecture of the
underlying Wine layer that Lutris manages.

```
Lutris = runner manager + game library (SQLite) + install script engine
         + per-game config overlay + cross-distro runtime (LD_LIBRARY_PATH shim)
```

---

## 1. Architecture Overview

### High-Level Flow

```
User clicks "Play"
    ↓
Read cooked game config from ~/.config/lutris/games/<game>.yml
    ↓
Apply cascading overrides: system → runner → game
    ↓
Resolve runner binary (wine, proton, linux, retroarch, etc.)
    ↓
Run prelaunch hooks (DXVK injection, prefix setup, env vars)
    ↓
Wrap with optional tools (GameMode, Gamescope, MangoHud)
    ↓
Set LD_LIBRARY_PATH via Lutris Runtime
    ↓
Spawn runner binary with lutris-wrapper for process tracking
```

### Runner System

Each "runner" is a Python class (inheriting from `lutris/runners/runner.py`)
that knows how to find its binary, build the CLI invocation, report install
state, and handle version management. Runners live in `lutris/runners/*.py`
(e.g., `wine.py`, `steam.py`, `libretro.py`).

| Runner | Purpose | Managed by Lutris? |
|--------|---------|-------------------|
| `wine` | Windows games via Wine | ✅ Downloads custom builds |
| `proton` | Windows via Proton/umu | ✅ Default is Proton-GE via umu |
| `linux` | Native Linux binaries | No — system-provided |
| `steam` | Steam games (Linux + Proton) | No — delegates to Steam |
| `libretro` | RetroArch cores | ✅ Downloads cores |
| `dosbox` | MS-DOS games | ✅ Downloads Dosbox |
| `scummvm` | ScummVM point-and-click | ✅ Downloads ScummVM |
| `mame` | Arcade MAME | ✅ |
| `dolphin` | GameCube/Wii | ✅ |
| `rpcs3` | PS3 | ✅ |
| `pcsx2` | PS2 | ✅ |
| `ryujinx` | Switch | ✅ |
| `ruffle` | Flash | ✅ |
| `tic80` | TIC-80 fantasy console | ✅ |
| `easyrpg` | RPG Maker 2000/2003 | ✅ |
| web (webkit) | Web games | System |
| `winesteam` | Steam Windows through Proton | ✅ |

Runners are downloaded from lutris.net's CDN/buildbot and stored at:

```
~/.local/share/lutris/runners/<runner_name>/
```

Wine runners specifically:

```
~/.local/share/lutris/runners/wine/<version-name>/
```

Runners are built from **Ubuntu 14.04** ⚠️ for maximum glibc backward compatibility.
(This refers to the build environment used on Lutris's buildbot — stated in
official docs, but may have been updated since this note was written.)

### The Three-Layer Config Cascade

| Layer | File | Scope |
|-------|------|-------|
| **System** | `~/.config/lutris/system.yml` | All games, all runners |
| **Runner** | `~/.config/lutris/runners/<runner>.yml` | All games using this runner |
| **Game** | `~/.config/lutris/games/<game>.yml` | This specific game |

Each layer can set `game` options, runner options, and `system` options.
Game overrides runner, runner overrides system.

### Storage Layout

#### Configurations (`~/.config/lutris`)

| File | Purpose |
|------|---------|
| `lutris.conf` | UI preferences (window size, sidebar, theme) |
| `system.yml` | Global default config for all games |
| `runners/<slug>.yml` | Runner-specific default configs |
| `games/<slug>-<timestamp>.yml` | Per-game config (post-install "cooked" config) |

#### Data (`~/.local/share/lutris`)

| Path | Purpose |
|------|---------|
| `pga.db` | SQLite game library database |
| `runners/<name>/` | Downloaded runner binaries |
| `runtime/` | Lutris Runtime (lib32, lib64, steam subdirs) |
| `banners/*.jpg` | Game banner images |
| `games/<slug>-<timestamp>.yml` | Cached installer scripts |

#### Cache (`~/.cache/lutris`)

| File | Purpose |
|------|---------|
| `auth-token` | Session token for lutris.net (NOT credentials) |

---

## 2. Wine Management

### Wine Versions

Wine builds are self-contained directories under
`~/.local/share/lutris/runners/wine/`. Each contains a full Wine build
(binaries, libs, DLLs). Lutris supports **four categories**:

| Source | Location | Notes |
|--------|----------|-------|
| **Lutris builds** | `~/.local/share/lutris/runners/wine/` | Downloaded from lutris.net; managed via Runner Install dialog |
| **System Wine** | `/usr/bin/wine`, `/opt/wine-*`, `winehq-*` | Whatever `wine` is on `$PATH` |
| **Proton (Steam)** | Steam `compatibilitytools.d/` directories | Detected via Steam library folders |
| **GE-Proton (umu)** | Managed by UMU runtime | As of v0.5.20, default for the wine runner; uses `umu-run` wrapper |

**Selection logic**: reads game-level config → runner-level → falls back to
default. The `GE_PROTON_LATEST` sentinel means "latest GE-Proton."
A validation warning is raised for Proton versions with < 32-bit prefixes.
A "Custom" option allows pointing to an arbitrary `wine` binary.

### Prefix Management

Lutris creates a **separate Wine prefix per game** by default, stored at the
game's install directory (user-chosen). The prefix path is set in:

```
Configure → Game Options → Wine prefix
```

If left blank, it defaults to `$GAMEDIR`. Architecture (`win64` vs `win32`)
is set per-game.

### DLL Overrides

DLL overrides are how wine decides whether to use its own implementation
("builtin") or the game's shipped DLL ("native"). The full mechanism,
including the resolution order, is documented in
[wine-deep-dive.md](wine-deep-dive.md#dll-override-system).

Set in the **Runner Options** tab or via the `wine` section of an install script:

```yaml
wine:
  overrides:
    ddraw.dll: n          # native
    d3d9: disabled
    winegstreamer: builtin
```

Values: `n` (native), `b` (builtin), `n,b` (native first), `b,n` (builtin
first), `disabled`.

Lutris applies these two ways:
1. Sets `WINEDLLOVERRIDES` environment variable at launch
2. Writes to registry at `HKEY_CURRENT_USER\Software\Wine\DllOverrides`
   during `prelaunch()`

It also applies a set of built-in default overrides (e.g., disabling
`winemenubuilder`).

### DXVK / VKD3D Per-Game

Each component has a **manager class** derived from `DLLManager`. For the
full technical background on how DXVK translates DirectX to Vulkan and why
it's faster than WineD3D, see [proton-deep-dive.md](proton-deep-dive.md#1-dxvk-directx-1011--vulkan).

| Component | Manager Class | What It Does |
|-----------|---------------|-------------|
| DXVK | `DXVKManager` | Copies `d3d9.dll`, `d3d10.dll`, `d3d10core.dll`, `d3d11.dll`, `dxgi.dll` into prefix `system32/` and `syswow64/` |
| VKD3D-Proton | `VKD3DManager` | Copies `d3d12.dll`, `d3d12core.dll` |
| D3D Extras | `D3DExtrasManager` | Replaces `d3dx9_*.dll`, `d3dcompiler_*.dll` with native versions |
| DXVK-NVAPI | `DXVKNVAPIManager` | Copies `nvapi.dll`, `nvapi64.dll` for NVAPI/DLSS emulation |
| dgVoodoo2 | `dgvoodoo2Manager` | Glide/DirectX 1–7 → D3D11 translation |

**Per-game flow** during `prelaunch()`:
1. Read `dxvk`, `vkd3d`, `d3d_extras`, `dxvk_nvapi`, `dgvoodoo2` booleans + version strings from runner config
2. Check Vulkan support via `vkquery` for DXVK/VKD3D
3. If using Proton, mark `proton_compatible=False` managers as disabled (Proton bundles its own)
4. Call `manager.setup(enabled)` which copies or removes DLLs from the prefix

⚠️ **Lutris does NOT manage `dxvk.conf`.** DXVK reads `dxvk.conf` from the
game's working directory or from `$DXVK_CONFIG_FILE`. You create these
manually if needed.

### Environment Variables

Set per-game in **System Options → Environment Variables** or via install
scripts:

```yaml
system:
  env:
    __GL_SHADER_DISK_CACHE: 1
    __GL_THREADED_OPTIMIZATIONS: '1'
    mesa_glthread: 'true'
    DXVK_HUD: 'fps'
```

### Winetricks / Regedit

Available as GUI tasks via right-click → Wine:
- Winetricks
- Open Wine Console
- Open Registry Editor
- Wine Configuration (winecfg)

---

## 3. Install Scripts

### 3.1 Purpose & Flow

A Lutris install script is a single YAML (or JSON) document that describes
how to acquire game files, set up the game, and store a base configuration.
After installation, the `files` and `installer` sections are stripped,
variables are substituted with resolved values, and the result is saved as
the "cooked" config at:

```
~/.local/share/lutris/games/<game>-<timestamp>.yml
```

Scripts come from two sources:
- **Published on lutris.net** — embedded in a larger document with site
  metadata (`name`, `game_slug`, `version`, `slug`, `runner`)
- **Local standalone files** — loaded via `lutris -i /path/to/file.yaml`
  with metadata at the root level, everything else under a `script:` key

### 3.2 Script Structure (Standalone File)

```yaml
name: "Game Name"           # Display name, quote if special chars
game_slug: game-name        # Lutris.net identifier
version: Installer          # Installer variant name
slug: game-name-installer   # Unique installer ID
runner: wine                # Runner slug

script:                     # Everything below is the installer
  game:                     # Game configuration
    exe: $GAMEDIR/game.exe  # Main executable
    args: --windowed        # Optional arguments
    prefix: $GAMEDIR        # Wine prefix path
    arch: win64             # Prefix architecture
    working_dir: $GAMEDIR   # Working directory

  wine:                     # Runner-specific config
    version: lutris-7.2-x86_64
    dxvk: true
    esync: true
    overrides:
      ddraw.dll: n

  system:                   # System-level overrides
    env:
      mesa_glthread: 'true'
    pulse_latency: true

  files:                    # Required files
    - installer: "N/A:Select the game's setup file"
    - patch: https://example.com/patch.zip

  installer:                # Ordered installation steps
    - task:
        name: create_prefix
        arch: win64
    - task:
        name: wineexec
        executable: installer
        args: /SILENT
```

### 3.3 Metadata Fields (Root Level for Standalone Scripts)

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name of the game |
| `game_slug` | Yes | Lutris.net game identifier |
| `version` | Yes | Installer variant name |
| `slug` | Yes | Unique installer ID |
| `runner` | Yes | Runner slug (`wine`, `linux`, `steam`, `libretro`, etc.) |

For published scripts, these come from the website API and only the `script:`
section is editable.

### 3.4 Core Script Sections

#### `game` Section

Runner-specific configuration for the game entry. This is what Lutris uses
at launch time to know what to run.

| Directive | Applies To | Description |
|-----------|-----------|-------------|
| `exe` | linux, wine | Main game executable |
| `main_file` | emulators, web | ROM/disk file, or URL for web games |
| `args` | linux, wine, dosbox, scummvm, pico8, zdoom | Additional command-line arguments |
| `working_dir` | linux, wine, dosbox | Game working directory |
| `prefix` | wine | Wine prefix path (typically `$GAMEDIR`) |
| `arch` | wine | Prefix architecture: `win64` (default) or `win32` |
| `appid` | steam | Steam AppID (numerical ID from store URL) |
| `gogid` | gog | GOG game ID (lookup at gogdb.org) |
| `humbleid` | humble | Humble Bundle ID |
| `game_id` | scummvm | ScummVM game ID (from scummvm.org/compatibility/) |
| `launch_configs` | any | List of alternate launch configs with `exe`, `args`, `working_dir`, `name` |
| `run_without_steam` | steam | DRM-free Steam mode (boolean) |
| `steamless_binary` | steam | Path to game exe for DRM-free Steam launch |
| `path` | scummvm | Location of game files (set to `$GAMEDIR` in installers) |

Example of `launch_configs`:

```yaml
game:
  exe: main.exe
  launch_configs:
    - exe: map_editor.exe
      name: Map Editor
    - exe: main.exe
      args: -missionpack
      name: Mission Pack
```

#### `wine` Section (Runner-Specific)

| Directive | Description |
|-----------|-------------|
| `version` | Pin a specific Wine build (avoid when possible) |
| `dxvk` | Boolean, enable/disable DXVK |
| `dxvk_version` | Specific DXVK version string |
| `esync` | Boolean, enable/disable esync |
| `overrides` | Mapping of DLL name → `n`, `b`, `n,b`, `b,n`, `disabled` |

#### `system` Section

| Directive | Description |
|-----------|-------------|
| `env` | Mapping of env vars to set during both install and launch |
| `single_cpu` | Boolean, restrict to one CPU core (old games) |
| `pulse_latency` | Boolean, set PulseAudio latency to 60ms |
| `use_us_layout` | Boolean, force US keyboard layout while running |

#### `files` Section

References every file needed for installation. Keys are unique identifiers
used later in the `installer` section. Values can be strings or dictionaries.

| Syntax | Behavior |
|--------|----------|
| `https://example.com/file.zip` | Auto-download from URL |
| `N/A:Select the setup file` | Prompt user to locate a local file |
| `$STEAM:238960:path/to/data` | Acquire from Steam app (installs if missing) |
| ModDB download page URL | Special handling for moddb.com link rotation |
| `{url: ..., filename: ..., referer: ...}` | Advanced: custom filename and HTTP Referer |
| `$SCRIPTDIR/setup.exe` | Local file relative to the YAML script |

Examples:

```yaml
files:
  - file1: https://example.com/gamesetup.exe
  - file2: "N/A:Select the game's setup file"
  - file3:
      url: https://example.com/weird-url
      filename: actual_name.zip
      referer: www.example.com
```

#### `variables` Section

Custom variables for reuse in `files` URLs:

```yaml
variables:
  VERSION: 1.3
files:
  stk: https://github.com/supertuxkart/stk-code/releases/download/$VERSION/SuperTuxKart-$VERSION-linux-64bit.tar.xz
```

### 3.5 Variable Substitution

| Variable | Value |
|----------|-------|
| `$GAMEDIR` | Absolute game install path |
| `$SCRIPTDIR` | Directory containing the YAML script (local installs only; empty otherwise) |
| `$CACHE` | Temp cache directory (deleted after install) |
| `$RESOLUTION` | Full resolution of main display (e.g., `1920x1080`) |
| `$RESOLUTION_WIDTH` | Resolution width (e.g., `1920`) |
| `$RESOLUTION_HEIGHT` | Resolution height (e.g., `1080`) |
| `$WINEBIN` | Absolute path to Lutris-provided Wine binary used for installation |
| `$INPUT` | Value from the last `input_menu` selection |
| `$INPUT_<id>` | Value from a specific `input_menu` by ID |
| `$DISC` | Optical drive path from `insert-disc` |
| File IDs | Reference files from `files:` section → resolves to absolute path |

### 3.6 Complete Installer Directives Reference

Each entry in the `installer` list is a directive. Directives run in order,
top to bottom.

---

#### `task` — Runner-Specific Named Tasks

The most powerful directive. Tasks are defined per-runner. You can call tasks
from other runners by prefixing the name (e.g., `wine.wineexec` from a dosbox
installer).

**Wine tasks:**

**`create_prefix`** — Create an empty Wine prefix:

```yaml
- task:
    name: create_prefix
    arch: win64
    prefix: $GAMEDIR        # optional
    overrides:              # optional DLL overrides
      ddraw.dll: n
    install_gecko: false    # optional
    install_mono: false     # optional
```

**`wineexec`** — Run a Windows executable:

```yaml
- task:
    name: wineexec
    executable: installer   # file ID or path
    args: /SILENT /DIR="C:/game"
    prefix: $GAMEDIR        # optional
    arch: win64             # optional
    blocking: true          # wait for completion (default: non-blocking)
    description: "Installing..." # shown to user
    working_dir: $GAMEDIR   # optional
    overrides:              # optional DLL overrides for this run
      d3d9: b
    env:                    # optional env vars for this run
      DXVK_HUD: fps
    exclude_processes: "proc1 Proc2"  # space-separated
    include_processes: "proc3"        # override built-in exclusion list
```

**`winetricks`** — Run winetricks components:

```yaml
- task:
    name: winetricks
    app: vcrun2019 directplay  # space-separated for multiple
    prefix: $GAMEDIR           # optional
    silent: false              # default: true. Set false for XNA etc.
```

**`set_regedit`** — Modify Windows registry:

```yaml
- task:
    name: set_regedit
    path: HKEY_CURRENT_USER\Software\Valve\Steam
    key: SuppressAutoRun
    value: '00000000'
    type: REG_DWORD           # default: REG_SZ
    prefix: $GAMEDIR          # optional
    arch: win64               # optional
```

**`delete_registry_key`** — Delete a registry key:

```yaml
- task:
    name: delete_registry_key
    key: HKEY_CURRENT_USER\Software\SomeKey
    prefix: $GAMEDIR
    arch: win64
```

**`set_regedit_file`** — Apply a `.reg` file:

```yaml
- task:
    name: set_regedit_file
    filename: myfile.reg
    arch: win64
```

**`winekill`** — Stop all Wine processes in a prefix:

```yaml
- task:
    name: winekill
    prefix: $GAMEDIR
    arch: win64
```

**`eject_disc`** — Eject disc from optical drive:

```yaml
- task:
    name: eject_disc
    prefix: $GAMEDIR
```

**DOSBox tasks:**

```yaml
- task:
    name: dosexec
    executable: file_id       # file ID or path
    config_file: $GAMEDIR/game.conf  # optional .conf file
    args: -scaler normal3x
    working_dir: $GAMEDIR     # defaults to executable's dir
    exit: false               # keep DOSBox open after exec
```

---

#### `execute` — Run Arbitrary Commands

```yaml
- execute:
    file: some_file_id        # or use command: instead
    args: --arg
    working_dir: $GAMEDIR
    env: {KEY: value}
    disable_runtime: true     # skip LD_LIBRARY_PATH wrapping
    exclude_processes: "..."
    include_processes: "..."

# Alternative: shell command
- execute:
    command: 'echo Hello | cat'
```

The `command` parameter uses `bash` internally and adds it to
`include_processes`. The file is made executable automatically.

---

#### `extract` — Extract Archives

```yaml
- extract:
    file: game_archive   # file ID or path with optional wildcards
    dst: $GAMEDIR/data/  # optional, defaults to $GAMEDIR
    format: zip          # optional override: tgz, tar, zip, 7z, rar,
                         # txz, bz2, gzip, deb, exe, gog (innoextract),
                         # plus all formats supported by 7zip
```

---

#### `merge` / `copy` — Copy Files/Directories

`copy` is an alias for `merge`. When merging into an existing directory,
original files with the same name are overwritten.

```yaml
- merge:
    src: game_file_id    # file ID or path
    dst: $GAMEDIR/location

- copy:                  # identical behavior
    src: game_file_id
    dst: $GAMEDIR/location
```

If `src` is a file ID, it's updated with the destination path for use in
subsequent commands.

---

#### `move` — Move Files/Directories

Cannot overwrite existing files. Creates destination directories if missing.
Give the full destination path including filename, not just the directory.

```yaml
- move:
    src: game_file_id    # file ID, or $CACHE/path, or $GAMEDIR/path
    dst: $GAMEDIR/location
```

---

#### `chmodx` — Make Executable

```yaml
- chmodx: $GAMEDIR/game_binary
```

Commonly needed after extracting zip archives (which don't retain permissions).

---

#### `write_file` — Write Text File

```yaml
- write_file:
    file: $GAMEDIR/config.txt
    content: "key=value"
    mode: w              # 'w' write (default), 'a' append
```

---

#### `write_config` — Modify INI-Style Config

```yaml
# Single key/value
- write_config:
    file: $GAMEDIR/settings.ini
    section: Engine
    key: Renderer
    value: OpenGL

# Multiple keys at once
- write_config:
    file: $GAMEDIR/settings.ini
    data:
      General:
        iNumHWThreads: 2
        bUseThreadedAI: 1
    merge: false         # truncate first (default: merge)
```

**Note:** The file is entirely rewritten. Comments are stripped. Compare
before/after to catch parsing issues.

---

#### `write_json` — Modify JSON File

```yaml
- write_json:
    file: $GAMEDIR/config.json
    data:
      Video:
        Fullscreen: false
    merge: false          # overwrite instead of update (default: merge)
```

Also rewrites the entire file. Check for parsing issues.

---

#### `input_menu` — User Choice Dropdown

```yaml
- input_menu:
    description: "Choose language:"
    id: LANG              # optional; value available as $INPUT_LANG
    options:
      - en: English
      - fr: French
      - "value and": "label can be anything"
    preselect: en         # optional default selection
```

The last selected value is always available as `$INPUT`. If `id` is set, the
value is also available as `$INPUT_<id>`. IDs must contain only numbers,
letters, and underscores.

---

#### `insert-disc` — Insert Disc Dialog

```yaml
- insert-disc:
    requires: setup.exe   # file or folder to verify disc presence
    message: "Insert the game disc"  # custom text (optional)
```

The `$DISC` variable contains the drive path for use in subsequent commands.
If CDEmu is not installed, a link to its homepage is shown.

---

### 3.7 Meta-Directives (Outside `installer`)

| Directive | Location | Description |
|-----------|----------|-------------|
| `require-binaries` | Script root | Comma-separated (AND), `\|`-separated (OR). E.g., `cmake, gcc \| clang` |
| `requires` | Script root | Base game slug for mods/add-ons. E.g., `requires: quake-2` |
| `extends` | Script root | Base game slug — modifies existing game config instead of creating a new entry. E.g., `extends: unreal-gold` |
| `install_complete_text` | Script root | Custom message shown when installation finishes |

### 3.8 Script Lifecycle

```
User triggers install (lutris: URL, -i file, or manual add)
    ↓
Lutris resolves all files in `files:` section
  - Downloads URLs
  - Prompts user for N/A files
  - Acquires from Steam if needed
    ↓
Runs each directive in `installer:` in order
  - Creates prefix
  - Runs executables
  - Extracts archives
  - Moves/copies files
  - Applies registry changes
    ↓
Strips `files` and `installer` keys from script
    ↓
Substitutes variables ($GAMEDIR, $WINEBIN, etc.) with final values
    ↓
Saves cooked config to ~/.local/share/lutris/games/<game>-<timestamp>.yml
    ↓
Game appears in library, ready to launch
```

### 3.9 ⚠️ Pitfalls

- **YAML indentation**: 2-space indent, no tabs. This is the most common
  failure when writing scripts.
- **Community script quality**: Published scripts vary widely. Some pin
  outdated Wine versions or miss dependencies. Always review a script before
  using it.
- **`blocking: true` for wineexec**: When you have multiple sequential
  installer steps, the first `wineexec` must be `blocking: true` or the next
  step starts before the installer finishes.
- **Silent GOG installers**: May need `/SUPPRESSMSGBOXES /NOGUI` flags in
  addition to `/SILENT` (documented in Lutris examples).
- **`requires` vs `extends`**: `requires` creates a new game entry that
  depends on a base game being installed. `extends` modifies an existing
  game's config in-place.

### 3.10 Example Walkthrough: Freelancer Lutris Script

To make the reference concrete, here's how a Lutris install script for
Freelancer (the game from [freelancer-setup.md](../guides/freelancer-setup.md)) would
look, with a step-by-step explanation of each field.

#### The Script

```yaml
name: "Freelancer"
game_slug: freelancer
version: "MagiPacks Repack + HD Edition"
slug: freelancer-magipacks-hd
runner: wine

script:
  game:
    exe: $GAMEDIR/drive_c/MagiPacks/Freelancer/EXE/freelancer.exe
    prefix: $GAMEDIR
    arch: win64
    working_dir: $GAMEDIR/drive_c/MagiPacks/Freelancer/EXE

  wine:
    version: lutris-7.2-x86_64
    dxvk: false              # No Vulkan on VMware SVGA II
    esync: false             # VMware VM, keep it simple
    overrides:
      dinput.dll: b,n        # Builtin first, fall back to native

  system:
    env:
      WINEDEBUG: -all        # Suppress fixme spam
    pulse_latency: true      # Reduce audio crackling

  files:
    - repack_setup: "N/A:Select Freelancer_Repack_Setup.exe"
    - repack_bin: "N/A:Select Freelancer_Repack_Setup-1.bin"
    - hd_installer: "N/A:Select FreelancerHDESetup_v0_7_1.exe"

  installer:
    - task:
        name: create_prefix
        arch: win64
        install_gecko: false
        install_mono: false

    - task:
        name: wineexec
        executable: repack_setup
        args: /SILENT /DIR="C:\MagiPacks\Freelancer"
        blocking: true
        description: "Installing Freelancer (MagiPacks repack)..."

    - task:
        name: winetricks
        app: directplay
        silent: true

    - task:
        name: wineexec
        executable: hd_installer
        args: /SILENT
        blocking: true
        description: "Installing Freelancer HD Edition..."
```

#### Step-by-Step

| Section | What It Does | Why It's Set This Way |
|---------|-------------|----------------------|
| `game.exe` | Points to the game executable inside the prefix | After install, the exe is at `C:\MagiPacks\Freelancer\EXE\freelancer.exe` — Lutris resolves `$GAMEDIR/drive_c/...` to the real path |
| `game.prefix` | Tells Lutris to create the Wine prefix at the game directory | Each game gets its own isolated prefix, no conflicts with other games |
| `game.arch: win64` | Creates a 64-bit prefix | Needed for the WoW64 layer; Freelancer is 32-bit but runs fine in a 64-bit prefix |
| `game.working_dir` | Sets CWD to the EXE directory | Some games need to find relative assets from their own directory |
| `wine.dxvk: false` | Skips DXVK injection | VMware SVGA II has no Vulkan support — DXVK would fail at the vulkan check and waste time |
| `wine.overrides` | Prefers builtin dinput over the game's copy | The builtin handles X11 mouse events better (see freelancer-setup.md for the full explanation) |
| `system.env` | Disables all wine debug output | Prevents millions of `fixme:d3d:format` lines from flooding stderr |
| `files: N/A:...` | Prompts the user for each file | The game files are copyrighted — Lutris can't redistribute them, so the user must point to their local copies |
| `create_prefix` | Initializes the Wine prefix (reg files, drive_c, wineserver) | Equivalent to `wine winecfg` in the manual setup |
| `wineexec repack_setup` | Runs the MagiPacks installer silently | `/SILENT` for Inno Setup; `blocking: true` ensures the next step waits for install to finish |
| `winetricks directplay` | Registers DirectPlay DLLs via regsvr32 | Same `winetricks -q directplay` from the manual setup — Freelancer needs DirectPlay for session management |
| `wineexec hd_installer` | Runs the HD Edition mod installer | Applied after the base game and DirectPlay registration |

#### What Lutris Would Do vs Manual

| Step | Lutris | Manual (from freelancer-setup.md) |
|------|--------|-----------------------------------|
| Prefix creation | Automatic via `create_prefix` task | `export WINEPREFIX=... wine winecfg` |
| Set Windows version | Not shown here (would need `set_regedit` in installer) | GUI: select Windows 7 in winecfg |
| Install DirectPlay | `task: winetricks app: directplay` | `winetricks -q directplay` |
| Run installer | `task: wineexec executable: repack_setup args: /SILENT` | `wine ~/Games/Freelancer_Repack_Setup.exe` |
| Install HD Edition | `task: wineexec executable: hd_installer args: /SILENT` | `wine ~/Games/FreelancerHDESetup_v0_7_1.exe` |
| Launch command | Auto-generated from cooked config at click time | `WINEDLLOVERRIDES="dinput.dll=b,n" WINEDEBUG=-all wine "$WINEPREFIX/.../freelancer.exe"` |
| Session switching | Lutris works in any session (X11 or Wayland) | Must log out of Sway, log into i3/Xorg |

#### Key Difference

The Lutris script would **fail to run the installer** on this system just
like the manual setup would — because the manual setup had to switch to
Xorg/i3 for wine to work. Lutris doesn't solve the XWayland font crash or
the Wayland wine driver `kernel32.dll` failure. The install script is only
useful after those fundamental issues are addressed, which is part of why
the manual approach was chosen (noted in §8).


## 4. Game Execution Details

### 4.1 The Launch Chain

```
User clicks "Play"
    ↓
Game.launch()
    ↓ loads cooked config from ~/.config/lutris/games/<game>.yml
    ↓ applies cascading overrides: system → runner → game
    ↓
Game.configure_game() — resolves runner binary, builds environment
    ↓
Game.start_game() → Runner.play()
    ↓ returns gameplay_info dict (command list, env vars, working dir)
    ↓
get_launch_parameters() — wraps with optional external tools
    ↓  (GameMode, Gamescope, MangoHud — in that order? ⚠️)
MonitoredCommand.start()
    ↓ forks via lutris-wrapper helper
Game process running
    ↓ game exits
MonitoredCommand detects exit via child_watch_add
    ↓
Updates lastplayed and playtime in pga.db
    ↓
Cleans up return code file
```

### 4.2 Config Resolution at Launch

The cooked game config is what the install script produced after stripping
`files`/`installer`. At launch, Lutris reads it then applies the
three-layer override cascade:

1. Load `~/.config/lutris/system.yml` (global defaults)
2. Load `~/.config/lutris/runners/<runner>.yml` (runner defaults, overrides system)
3. Load `~/.config/lutris/games/<game>.yml` (game-specific, overrides runner)

Each layer can set `game`, `wine`/runner, and `system` directives. The merged
result shapes the actual launch command.

### 4.3 Wine Runner: Exact Command

When the runner is `wine`, `Runner.play()` in `lutris/runners/wine.py`
builds a command equivalent to:

```bash
env WINEPREFIX=/path/to/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEESYNC=1 \
    WINEFSYNC=1 \
    DXVK_LOG_LEVEL=error \
    DXVK_STATE_CACHE=1 \
    DXVK_STATE_CACHE_PATH=/path/to/prefix \
    LUTRIS_GAME_UUID=<uuid> \
    LUTRIS_RETURN_CODE_FILE=/tmp/lutris_rc_<uuid> \
    LD_LIBRARY_PATH=<runtime_paths>:/path/to/wine/lib:$LD_LIBRARY_PATH \
    <gamemoderun> <mangohud> \
    /path/to/wine/bin/wine \
    /path/to/game.exe \
    <args>
```

Key details:
- `LUTRIS_GAME_UUID` and `LUTRIS_RETURN_CODE_FILE` are set by
  `MonitoredCommand` for process tracking and exit code collection
- `WINEDLLOVERRIDES` is set if DLL overrides are configured
- `LD_LIBRARY_PATH` includes: runtime paths + wine build's own `lib/`/`lib64/` + system
- DXVK/VKD3D DLLs were already injected into the prefix during `prelaunch()`

### 4.4 Proton/UMU Runner Command

For the Proton runner (default as of v0.5.20):

```bash
env PROTONPATH=GE-Proton \
    PROTON_NO_ESYNC=0 \
    PROTON_NO_FSYNC=0 \
    PROTON_BATTLEYE_RUNTIME=~/.local/share/lutris/runtime/battleye \
    PROTON_EAC_RUNTIME=~/.local/share/lutris/runtime/eac \
    LUTRIS_GAME_UUID=<uuid> \
    LUTRIS_RETURN_CODE_FILE=/tmp/lutris_rc_<uuid> \
    umu-run /path/to/game.exe <args>
```

- ⚠️ `umu-run` handles Proton version selection internally. Lutris passes
  `PROTONPATH` to select a specific GE-Proton build.
- Proton bundles its own DXVK/VKD3D — Lutris skips DLL injection for Proton games.

### 4.5 The Lutris Runtime

The runtime provides a consistent set of shared libraries across distros,
reducing "missing .so" errors. It is located at:

```
~/.local/share/lutris/runtime/
├── lib32/       # 32-bit libraries (Ubuntu 14.04 based)
├── lib64/       # 64-bit libraries
└── steam/       # Steam Runtime subset (modified — problematic libs removed)
```

**What it is**: The first part is based on the Steam runtime with known
problematic libraries removed. The second part (Lutris runtime) completes it
with additional or newer libraries. The Lutris runtime is built from
**Ubuntu 14.04** ⚠️, which is also the base used for most runners —
minimizing incompatibilities. (Same caveat as above — the build base may have
been updated since this note was written.)

**What is NOT bundled**: `glibc`, `libstdc++`, OpenGL drivers, Vulkan drivers.
These come from the host system to avoid conflicts. You must install 32-bit
variants separately.

**LD_LIBRARY_PATH construction order**:
1. Wine build's own `lib/` and `lib64/` directories
2. System libraries (if `prefer_system_libs` is enabled)
3. Lutris runtime paths (`lib32/`, `lib64/`)
4. Steam runtime subset paths
5. Existing `LD_LIBRARY_PATH` from environment

**Auto-update**: On client start, Lutris checks
`runtime_versions.json` (6-hour staleness threshold). A `RuntimeUpdater`
handles download and extraction through states: `PENDING → DOWNLOADING →
EXTRACTING → COMPLETED`.

**Disabling the runtime** (in order of precedence):
- Per-game: Configure → System Options → Disable Lutris Runtime
- Per-runner: Runner-specific settings
- Global: `export LUTRIS_RUNTIME=0` (takes precedence over everything)

### 4.5a System Dependencies (What Lutris Doesn't Bundle)

Lutris's official [WineDependencies.md](https://github.com/lutris/docs/blob/master/WineDependencies.md)
lists required system packages per-distro. These must be installed manually
because the runtime intentionally excludes them to avoid conflicts:

| Category | Packages (Arch Linux) | Why Needed |
|----------|----------------------|------------|
| **32-bit OpenGL** | `lib32-mesa`, `lib32-libgl` | WineD3D needs 32-bit OpenGL for WoW64 |
| **Vulkan** | `vulkan-radeon`/`vulkan-intel`/`lib32-vulkan-*` | DXVK/VKD3D require 32+64-bit Vulkan drivers. See [vmware.md](vmware.md#limitations) for why this matters on non-Vulkan GPUs |
| **Audio** | `lib32-pipewire`/`lib32-pulseaudio`, `lib32-alsa-lib` | Wine's audio (DirectSound, XAudio) needs 32-bit ALSA/Pulse |
| **Networking** | `lib32-gnutls` | Wine's crypt32 / schannel (HTTPS, certificate validation) |
| **Fonts** | `lib32-fontconfig`, `ttf-liberation` | Wine's GDI font rendering |
| **SDL2** | `lib32-sdl2` | Some game launchers need 32-bit SDL2 |

On Arch, these are grouped in the `lutris` package's optional dependencies.
Running `lutris --check-dependencies` (⚠️ may not exist in all versions)
or checking `/usr/share/doc/lutris/dependencies/` lists missing items.

The official dependency list is maintained at:
https://github.com/lutris/docs/blob/master/WineDependencies.md

### 4.6 Gamescope / MangoHud / GameMode Wrapping

`get_launch_parameters()` wraps the base command with optional tools:

| Tool | Config Key | Mechanism |
|------|-----------|-----------|
| **GameMode** | `gamemode: true` | Prepends `gamemoderun` to the command. Optimizes CPU governor, I/O priority, scheduler via `LD_PRELOAD` |
| **MangoHud** | `mangohud: true` | Prepends `mangohud` to the command. Overlays FPS, temps, etc. Can use `mangohud_config` for a custom config path |
| **Gamescope** | `gamescope: true` | Wraps the entire game in a nested micro-compositor. Configured via `gamescope_output`, `gamescope_fsr`, etc. |

⚠️ The exact wrapping order is not confirmed from source — likely GameMode
outermost, then Gamescope, then MangoHud, but this may vary by version.

### 4.7 Process Tracking: MonitoredCommand & lutris-wrapper

Lutris uses a two-tier system to track game processes:

**Tier 1: `MonitoredCommand`** (Python, in-process via GLib)
- Spawns the game process
- Uses GLib `child_watch_add` for **async exit detection** (non-blocking)
- Runs a **heartbeat at 2000ms** that updates `playtime` in the SQLite database
- Tracks the full process tree, waits for all children to exit
- Log lines you see in Lutris output:
  ```
  Started initial process <pid> from <command>
  Start monitoring process.
  Monitored process exited.
  Initial process has exited (return code: <code>)
  All children have exited.
  Exit with return code <code>
  ```

**Tier 2: `lutris-wrapper`** (helper shipped with Lutris)
- Forks the actual game process
- Writes the child PID to a known location
- On child exit, writes the return code to `LUTRIS_RETURN_CODE_FILE`
- Can kill the entire process tree on timeout
- Sets `LUTRIS_GAME_UUID` for correlation

On exit, Lutris reads the return code, updates `lastplayed` and `playtime`
in `pga.db`, and cleans up the return code file.

### 4.8 CLI Alternatives

| Command | What It Does |
|---------|-------------|
| `lutris -b <game-id>` | Generates a standalone bash script to run the game without the Lutris client. Embeds all env vars, runtime paths, and the wine/proton command |
| `lutris -e <program>` | Runs an arbitrary program with the Lutris Runtime `LD_LIBRARY_PATH` applied (no game config, no runner) |
| `lutris lutris:rungame/<slug>` | Launches a game directly from CLI by slug |
| `lutris lutris:rungameid/<id>` | Launches by numeric database ID from `lutris -l` |
| `lutris -i <file.yaml>` | Install a game from a local YAML script |

### 4.9 ⚠️ Uncertainties

- **Wrapping order**: The exact nesting of GameMode / Gamescope / MangoHud
  is not confirmed because `get_launch_parameters()` in the Lutris source
  was examined only through its interface, not the full command composition
  logic. The ordering likely matters — GameMode outermost, Gamescope
  wrapping the game, MangoHud innermost — but this hasn't been verified
  against the actual code path.
- **`lutris-wrapper` binary**: Whether `/usr/bin/lutris-wrapper` is a
  compiled C binary or a shell/Python script depends on how the distro
  packages Lutris. The source tree `monitored_command.py` contains a Python
  class, but some package builds ship a standalone helper. The exact
  mechanism on any given system may differ.
- **OAuth token refresh**: The `service_games` authentication flows for
  GOG, Epic, Humble, etc. live in `lutris/services/` and were not examined
  in detail. Token expiry, refresh behavior, and error handling may vary
  per service.

---

## 5. Library & Database

### SQLite Schema

Database path: `~/.local/share/lutris/pga.db` (pga = "Personal Game Archive")

**`games`** — Primary table for installed games:

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment |
| `slug` | TEXT | Unique game identifier |
| `name` | TEXT | Display name |
| `runner` | TEXT | Runner slug (`wine`, `linux`, `steam`, etc.) |
| `platform` | TEXT | Platform string |
| `installed` | INTEGER | Boolean (0/1) |
| `install_dir` | TEXT | Path to game files |
| `appid` | TEXT | Steam AppID or other service ID |
| `config_id` | TEXT | References cooked config filename |
| `year` | INTEGER | Release year |
| `playtime` | REAL | Total playtime in seconds |
| `lastplayed` | INTEGER | Unix timestamp |
| `installed_at` | INTEGER | Unix timestamp of install |
| `service` | TEXT | Service slug (`gog`, `steam`, `epic`, etc.) |
| `service_id` | TEXT | Service-specific game ID |

**Other tables**: `categories`, `games_categories` (many-to-many join),
`service_games` (external service cache), `sources` (file paths for game
discovery), `saved_searches` (persistent UI queries).

Schema synchronization: On startup, `syncdb()` compares the schema definition
against actual SQLite columns; missing columns are added via
`ALTER TABLE ... ADD COLUMN`. Complex migrations use `lutris/migrations/`.

Thread safety: A `threading.RLock` (`DB_LOCK`) with 5-second timeout wraps
all SQLite access.

### Library Sync Sources

| Service | Sync Method |
|---------|-------------|
| lutris.net | Token-based auth → account library |
| Steam | Public profile scrape + local `appmanifest_*.acf` scanning |
| GOG | API key (OAuth2 login) |
| Epic Games Store | API integration via Sources tab |
| Humble Bundle | Login |
| Itch.io | API key |
| Amazon Prime | Account connection |
| Zoom Platform | New in v0.5.20 |
| Steam Family | New in v0.5.20 |
| EA App / Origin | Launcher install via Lutris |
| Ubisoft Connect | Launcher install via Lutris |

⚠️ The exact OAuth flows for each service are in `lutris/services/` but
were not examined in detail.

### Common Database Operations

**Backup and restore:**

```bash
# Backup the entire Lutris data directory
cp -a ~/.local/share/lutris ~/.local/share/lutris.backup
cp -a ~/.config/lutris ~/.config/lutris.backup

# Or just the database
cp ~/.local/share/lutris/pga.db ~/lutris-pga-backup.db
```

The `pga.db` contains the game library (installed status, playtime, paths)
but not the game files themselves. If you restore a backup after a reformat,
Lutris will show all your games but will need the config YAMLs in
`~/.config/lutris/games/` and the actual game files at their original paths.
The runner binaries in `~/.local/share/lutris/runners/` are re-downloadable.

**Re-scanning for games after moving files:**

If you move a game's install directory, Lutris won't automatically find it.
You need to:
1. Right-click the game → Configure → Game Options
2. Update the game directory path
3. Verify the executable path under the same tab

Or delete the entry and re-add it (if you have an install script, re-run it
pointing to the existing files).

**Importing after reformat (from [Lutris forums](https://forums.lutris.net/t/installed-games-after-reformat/17331)):**

If you kept your home partition but reinstalled Lutris:
1. Copy back `~/.config/lutris/games/*.yml` — these are the cooked configs
2. Copy back `~/.local/share/lutris/pga.db` — game library database
3. Reinstall runners via Manage Runners dialog (re-downloads binaries)
4. Games should appear in your library with their original settings

If you only kept the game files but lost the Lutris configs, you'll need to
manually add each game (click `+` → add a locally installed game) and fill
in the executable path, runner, and prefix.

**Playtime tracking:**

Playtime is stored in `pga.db` in the `playtime` column (seconds) and
`lastplayed` (Unix timestamp). There's no built-in UI to reset or edit
playtime, but you can do it manually:

```bash
sqlite3 ~/.local/share/lutris/pga.db "UPDATE games SET playtime = 0 WHERE slug = 'game-slug';"
```

---

## 6. Lutris vs Manual Wine Setup

| Aspect | Lutris | Manual |
|--------|--------|--------|
| Prefix creation | Automatic per-game | Manual `WINEPREFIX=... winecfg` |
| Wine version mgmt | GUI picker, auto-download | Manual binary management |
| DXVK/VKD3D | One-click toggle, auto-inject | Manual DLL copy into prefix |
| DLL overrides | GUI checkboxes | `wine reg add` or env vars |
| Environment vars | GUI key-value editor | Shell wrapper or `env` |
| Runtime libs | Automatic LD_LIBRARY_PATH | Manual system package install |
| Multi-game library | Centralized SQLite with metadata | No built-in concept |
| Installation | Script-based automation | Manual `wine setup.exe` |
| Steam integration | Import + launch from Lutris | Manual Proton/wine launch |
| Controller/output config | Per-game display settings | Manual xrandr/gamescope |
| Debug logging | Built-in `-d` flag, log viewer | Manual `WINEDEBUG`. See [wine-deep-dive.md](wine-deep-dive.md#debug-channels) for channel reference |

## 7. What You Lose With Lutris

| Issue | Details |
|-------|---------|
| **Runtime conflicts** | Games needing newer glibc/libstdc++ (Dolphin, some native ports) crash with runtime; must disable per-game |
| **Script quality** | Community scripts vary wildly — some are outdated, use wrong Wine versions, or miss dependencies |
| **API dependency** | "Unable to connect to server" errors break installer download; offline installs require local YAML |
| **Hidden debug knobs** | Some low-level Wine debugging is abstracted away |
| **GPU driver masking** | Runtime LD_LIBRARY_PATH can hide driver issues |
| **Prefix corruption** | Switching Wine versions mid-prefix or sharing prefixes between games can break installations |
| **GTK aesthetics** | Can look out of place on Qt/Plasma desktops |
| **UI slowdown** | Large libraries cause UI lag; SQLite queries not optimized |
| **Update regressions** | New Lutris releases occasionally break previously working games |

## 8. Why Manual Setup Was Chosen Here

The dotfiles environment (VMware VM with no Vulkan support — see
[vmware.md](vmware.md#limitations), running Freelancer as the single game
target — see [freelancer-setup.md](../guides/freelancer-setup.md)) is a case where
Lutris adds abstraction without benefit:

1. **No Vulkan** — DXVK (Lutris's main wine advantage) is irrelevant on
   VMware SVGA II
2. **Single game** — No library to manage, no multi-game complexity
3. **Full visibility** — Manual setup gives complete control over wine
   debug channels, DLL overrides, and the render path
4. **No install scripts needed** — Freelancer's setup is straightforward
   enough that an automated script isn't saving much
5. **Known working config** — Once the game is running, there's nothing to
   gain from Lutris's version-switching or prefix-management features

---

## See Also

Other notes in this directory that provide related context:

| Note | Relevance |
|------|-----------|
| [wine-deep-dive.md](wine-deep-dive.md) | Wine architecture, WineD3D internals, prefix anatomy, DLL overrides — Lutris wraps all of this under the hood |
| [proton-deep-dive.md](proton-deep-dive.md) | Proton vs stock wine, DXVK/VKD3D details, GE-Proton — Lutris defaults to Proton-GE via umu as of v0.5.20 |
| [freelancer-setup.md](../guides/freelancer-setup.md) | The workflow that §3.10's example walkthrough is based on — manual wine setup for the same game |
| [vmware.md](vmware.md) | VMware SVGA II graphics stack — explains why DXVK is disabled in the example script (no Vulkan) |
| [sessions-display-servers.md](sessions-display-servers.md) | X11 vs Wayland — Lutris doesn't solve the wine Wayland issues that forced the Xorg+i3 workaround |

## Reference

### Source Code Repositories

| Repo | Purpose |
|------|---------|
| https://github.com/lutris/lutris | Main client (Python/GTK) |
| https://github.com/lutris/buildbot | Runner/build infrastructure |
| https://github.com/lutris/docs | Official documentation |
| https://github.com/GloriousEggroll/wine-ge-custom | Wine-GE builds (archived, superseded by umu) |
| https://github.com/Open-Wine-Components/ULWGL-launcher | Unified launcher (umu) |

### Official Documentation

- Installer script format: https://github.com/lutris/lutris/blob/master/docs/installers.rst
- Lutris Runtime: https://github.com/lutris/docs/blob/master/LutrisRuntime.md
- Wine dependencies: https://github.com/lutris/docs/blob/master/WineDependencies.md

### Version

Latest stable as of 2026: **v0.5.22** (released Feb 2026).
