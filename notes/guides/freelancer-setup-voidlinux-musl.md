# Freelancer Setup

Target: Freelancer (MagiPacks repack) via wine on VoidLinux-musl, Distrobox, niri, VMware VM.

---


## Step 1: Setup niri

Install `dbus`,`seatd`,`niri`

niri uses `xwayland-satellite`. Install that as well.

In VMware you have to install `mesa-dri`

Link all services

```bash

sudo ln -s /etc/sv/dbus/ /var/service/

sudo ln -s /etc/sv/seatd/ /var/service/

```

Add user to _seatd group. (Also video,input,audio)

```bash
sudo usermod -aG wheel,video,input,audio,_seatd YOURUSERNAME

```

Create `Wayland` required directory and start niri with dbus.

Add to `~/.bash_profile`:

```bash
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        mkdir -pm 0700 "$XDG_RUNTIME_DIR"
    fi
fi

exec dbus-run-session niri
```


## Step 2: Install distrobox, podman, crun

`crun` is non-`systemd` alternative for `runc`. 

```bash

sudo xbps-install -S podman crun

```
set up `registries.conf` ,`containers.conf` and `crun`

```toml
# ~/.config/containers/registries.conf
unqualified-search-registries = ['docker.io', 'quay.io', 'registry.fedoraproject.org']


[[registry]]
# In Nov. 2020, Docker rate-limits image pulling.  To avoid hitting these
# limits while testing, always use the google mirror for qualified and
# unqualified `docker.io` images.
# Ref: https://cloud.google.com/container-registry/docs/pulling-cached-images
prefix="docker.io"
location="mirror.gcr.io"
```

```toml
#~/.config/containers/containers.conf

# The containers configuration file specifies all of the available configuration
# command-line options/flags for container engine tools like Podman & Buildah,
# but in a TOML format that can be easily modified and versioned.

# Please refer to containers.conf(5) for details of all configuration options.
# Not all container engines implement all of the options.
# All of the options have hard coded defaults and these options will override
# the built in defaults. Users can then override these options via the command
# line. Container engines will read containers.conf files in up to three
# locations in the following order:
#  1. /usr/share/containers/containers.conf
#  2. /etc/containers/containers.conf
#  3. $XDG_CONFIG_HOME/containers/containers.conf or
#     $HOME/.config/containers/containers.conf if $XDG_CONFIG_HOME is not set
#  Items specified in the latter containers.conf, if they exist, override the
# previous containers.conf settings, or the default settings.

[containers]

# Control container cgroup configuration
# Determines  whether  the  container will create CGroups.
# Options are:
# `enabled`   Enable cgroup support within container
# `disabled`  Disable cgroup support, will inherit cgroups from parent
# `no-conmon` Do not create a cgroup dedicated to conmon.
#
cgroups = "disabled"

# A list of sysctls to be set in containers by default,
# specified as "name=value",
# for example:"net.ipv4.ping_group_range=0 0".
#
default_sysctls = [
  "net.ipv4.ping_group_range=0 0",
]

# Default proxy environment variables passed into the container.
# The environment variables passed in include:
# http_proxy, https_proxy, ftp_proxy, no_proxy, and the upper case versions of
# these. This option is needed when host system uses a proxy but container
# should not use proxy. Proxy environment variables specified for the container
# in any other way will override the values passed from the host.
#
http_proxy = true

[engine]
# Cgroup management implementation used for the runtime.
# Valid options "systemd" or "cgroupfs"
#
cgroup_manager = "cgroupfs"

# Default OCI runtime
#
runtime = "crun"

# List of the OCI runtimes that supports running containers without cgroups.
#
runtime_supports_nocgroups = ["crun"]

# Paths to look for a valid OCI runtime (crun, runc, kata, runsc, krun, etc)
[engine.runtimes]
crun = [
  "/usr/bin/crun",
  "/usr/sbin/crun",
  "/usr/local/bin/crun",
  "/usr/local/sbin/crun",
  "/sbin/crun",
  "/bin/crun",
  "/run/current-system/sw/bin/crun",
]

# Default flags for a valid OCI runtime (crun, runc, kata, runsc, krun, etc)
# Note: Do not pass the leading -- to the flag. To pass the runc flag --log-format json, the option given is log-format=json.
[engine.runtimes_flags]
crun = []

```

`distrobox` has to be install with their official [install-script](https://github.com/89luca89/distrobox#alternative-methods) (void doesn't have package for it) 


## Step 3: Reboot and check if xwayland-satellite is running correctly

if you do

```bash
echo $DISPLAY
```
and there is an output number such as `:0` then you succeed.


## Step 4: Create game box

Determine where do you want to put your distrobox and it's name.

example path is `~/boxes`
example name is `gambox`

```bash
mkdir -p ~/boxes/gamebox
```

make the box
```bash

distrobox create --name gamebox \
                 --image archlinux:latest \
                 --home ~/boxes/gamebox \
                 --unshare-process
```

## Step 5: Prepare the game box

Enter the box
```bash
distrobox enter gamebox

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

Install `wine`, `winetricks`

```bash
sudo pacman -S wine winetricks
```

Install Audio libs (`pipewire` and `alsa` in my case)

```bash
sudo pacman -S lib32-libpulse lib32-alsa-plugins lib32-alsa-lib
```
You can also install 64bit version if you want (not needed but for future use)
```bash
sudo pacman -S libpulse alsa-plugins alsa-lib
```

32bit Graphics lib
```bash
sudo pacman -S lib32-mesa
```

## Step 6: Wineprefixes and winecfg

make directories

```bash
mkdir -p ~/wine
mkdir -p ~/games
```

add to gamebox's bash_profile for easier future use

```.bash_profile
export WINEPREFIX=$HOME/wine
export WINEARCH=win64
export PATH="$HOME/games:$PATH"
```

restart gamebox or run these lines in bash to continue

```bash
winecfg
```

select `Windows Version` and test `Audio` in the popup. Should just works.

you can kill the server if there is something running after you close it

```bash
wineserver -k
```

### Step 7: Installing Freelancer

Get the installer and put it wherever you want. In my case ~/install/freelancer

```bash
wine ~/install/freelancer/Freelancer_Repack_Setup.exe
```

Install. I installed it in `Games/Freelancer`

make a bash file to run the game so it doesn't do fullscreen in niri

```bash
vim ~/games/freelancer.sh
```

```freelancer.sh
#!/bin/bash

wine explorer /desktop=Freelancer,1024x768 ~/wine/drive_c/Games/Freelancer/EXE/freelancer.exe
```

The original freelancer's font render will break if you go any higher than 1024x768. You will have to install the HD patch. But since we are in VMware that's too demanding for software rendering.


Chmod the bash file

```bash
chmod +x ~/games/freelancer.sh
```

Run it. (it should just fine it because we added the games folder in the .bash_profile)

```bash
bash freelancer.sh

```

### Step 8: Fix for higher resolution

<!-- While higher resolution is available from the repack edit already. The texts rendering of the ordinal Freelancer is still busted on higher resolution (Anything above 1024p)

Get `d3d8.dll`[https://github.com/crosire/d3d8to9] and drop into `~/wine/drive_c/Games/Freelancer/EXE/`.

Add `d3d8` in the `libraries` tab in `winecfg` and choose `native,builtin` (persistent) Or you can do `WINEDLLOVERRIDES="d3d8=n,b"` (pre-launch)

Note: the game scales up with ultrawide perfectly. All the cutscene are real-time rendered. The quirk is the aspect ratio changes would show a lot of behind the scene (characters appearing and disappearing) -->

Nope I was just being stupid. Just make sure you chose the 32bit version in stead of 16bit.

### DONE

note if using in a bare metal machine. you can use `gamescope` from `Valve` to scale the game without the HD patch (although why would you do that?). But since it's in a vm and we don't have `vulkan` support so it is what it is.


