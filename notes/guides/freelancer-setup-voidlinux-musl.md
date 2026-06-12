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
set up registries.conf and `crun`

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

[containers]
cgroup_manager="none"
events_backend="file"

[engine]
runtime="crun"
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
                 --home ~/boxes/gamebox
```

## Step 5: Prepare the game box

Enter the box
```bash
distrobox enter gamebox

```

Enable `multilib` on Arch. Add or uncomment.

```/etc/pacman.conf
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

### DONE

note if using in a bare metal machine. you can use `gamescope` from `Valve` to scale the game without the HD patch (although why would you do that?). But since it's in a vm and we don't have `vulkan` support so it is what it is.


