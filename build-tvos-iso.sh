#!/usr/bin/env bash
# TV OS ISO builder (Debian 12 "bookworm" + Kodi 10-foot UI, boots straight into the TV interface)
# Run on any Debian/Ubuntu machine with internet, ~15 GB free disk:   sudo ./build-tvos-iso.sh
# Output: ./tvos-build/tvos-amd64.hybrid.iso  (BIOS + UEFI, flash with Rufus / balenaEtcher / dd)
set -euo pipefail

OS_NAME="TV OS"            # change to rename the OS
WORKDIR="$(pwd)/tvos-build"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }

apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools

mkdir -p "$WORKDIR" && cd "$WORKDIR"
lb clean --purge >/dev/null 2>&1 || true

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloaders "syslinux,grub-efi" \
  --debian-installer live \
  --archive-areas "main contrib non-free non-free-firmware" \
  --iso-application "$OS_NAME" \
  --iso-volume "TVOS" \
  --bootappend-live "boot=live components quiet splash username=tv hostname=tvos"

# ---------- Packages ----------
mkdir -p config/package-lists
cat > config/package-lists/tv.list.chroot <<'EOF'
linux-image-amd64
live-boot
live-config
live-config-systemd
firmware-linux
firmware-misc-nonfree
firmware-realtek
firmware-iwlwifi
firmware-atheros
intel-microcode
amd64-microcode
xserver-xorg
xinit
x11-xserver-utils
xserver-xorg-video-all
xserver-xorg-input-all
mesa-utils
mesa-va-drivers
intel-media-va-driver-non-free
vainfo
kodi
kodi-inputstream-adaptive
kodi-pvr-iptvsimple
kodi-peripheral-joystick
libcec6
cec-utils
kodi-eventclients-kodi-send
pipewire
pipewire-pulse
wireplumber
alsa-utils
network-manager
network-manager-gnome
wpasupplicant
avahi-daemon
openssh-server
bluez
firefox-esr
sudo
udisks2
ntfs-3g
exfat-fuse
unattended-upgrades
EOF

# ---------- Auto-start the TV UI ----------
mkdir -p config/includes.chroot/etc/skel config/includes.chroot/etc/X11

cat > config/includes.chroot/etc/X11/Xwrapper.config <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

cat > config/includes.chroot/etc/skel/.bash_profile <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  while true; do
    startx /usr/bin/kodi-standalone -- :0 vt1 -nocursor
    sleep 1
  done
fi
EOF

cat > config/includes.chroot/etc/skel/.xserverrc <<'EOF'
#!/bin/sh
exec /usr/bin/X "$@"
EOF
chmod +x config/includes.chroot/etc/skel/.xserverrc

cat > config/includes.chroot/etc/skel/.xinitrc.d-noblank <<'EOF'
xset s off -dpms s noblank
EOF

mkdir -p config/includes.chroot/etc/skel/.kodi/userdata
cat > config/includes.chroot/etc/skel/.kodi/userdata/advancedsettings.xml <<'EOF'
<advancedsettings>
  <videoplayer><usedisplayasclock>true</usedisplayasclock></videoplayer>
  <network><cachemembuffersize>157286400</cachemembuffersize></network>
</advancedsettings>
EOF

mkdir -p config/hooks/normal
cat > config/hooks/normal/0100-tvos.hook.chroot <<'EOF'
#!/bin/sh
set -e
echo 'tv ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tv
chmod 440 /etc/sudoers.d/tv
systemctl enable NetworkManager bluetooth avahi-daemon ssh || true
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="TV OS (Debian 12 based)"/' /etc/os-release || true
EOF
chmod +x config/hooks/normal/0100-tvos.hook.chroot

# ---------- Build ----------
lb build 2>&1 | tee build.log

ISO="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO" ] && echo -e "\nDONE -> $WORKDIR/$ISO" || { echo "Build failed, see $WORKDIR/build.log"; exit 1; }
