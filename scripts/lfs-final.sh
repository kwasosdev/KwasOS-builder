#!/bin/bash
# LFS 13.0 Build Script (systemd edition)
# Final steps to configure and boot the system (chapters 9-11)
# by Luís Mendes :)
# Updated for LFS 13.0

package_name=""
package_ext=""

begin() {
	package_name=$1
	package_ext=$2

	echo "[lfs-final] Starting build of $package_name at $(date)"

	tar xf $package_name.$package_ext
	cd $package_name
}

finish() {
	echo "[lfs-final] Finishing build of $package_name at $(date)"

	cd /sources
	rm -rf $package_name
}

cd /sources

# 9.2. General Network Configuration (systemd-networkd)
# Use DHCP on any wired interface so the booted system gets networking
# automatically, regardless of the interface name it is given.
ln -sfv /dev/null /etc/systemd/network/99-default.link

cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=en* eth*

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF

# 9.2.4. Creating the /etc/resolv.conf File
cat > /etc/resolv.conf << "EOF"
# Begin /etc/resolv.conf

nameserver 8.8.8.8
nameserver 8.8.4.4

# End /etc/resolv.conf
EOF

# 9.2.5. Configuring the system hostname
echo "lfs" > /etc/hostname

# 9.2.6. Customizing the /etc/hosts File
cat > /etc/hosts << "EOF"
# Begin /etc/hosts

127.0.0.1 localhost.localdomain localhost
127.0.1.1 lfs
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF

# 9.6. Configuring the Linux Console
cat > /etc/vconsole.conf << "EOF"
KEYMAP=us
FONT=Lat2-Terminus16
EOF

# 9.7. Configuring the System Locale
cat > /etc/locale.conf << "EOF"
LANG=en_US.UTF-8
EOF

cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
      export $key
    fi
  done
fi

# End /etc/profile
EOF

# 9.8. Creating the /etc/inputrc File
cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF

# 9.9. Creating the /etc/shells File
cat > /etc/shells << "EOF"
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
EOF

# 10.2. Creating the /etc/fstab File
# ROOT_UUID and GRUB_DISK are exported by the build orchestration so the system
# boots reliably regardless of how the disk is enumerated (sda/sdb/vda...).
# The fallbacks match the LFS book's single-disk example (root on /dev/sda1).
ROOT_UUID="${ROOT_UUID:-}"
ROOT_PARTUUID="${ROOT_PARTUUID:-}"
GRUB_DISK="${GRUB_DISK:-/dev/sda}"
if [ -n "$ROOT_UUID" ]; then ROOT_SPEC="UUID=$ROOT_UUID"; else ROOT_SPEC="/dev/sda1"; fi

cat > /etc/fstab << EOF
# Begin /etc/fstab

# file system    mount-point  type     options             dump  fsck
#                                                                 order

$ROOT_SPEC  /            ext4     defaults            1     1

# End /etc/fstab
EOF

cd /sources

# 10.3. Linux-6.18.10
begin linux-6.18.10 tar.xz
make mrproper
make defconfig
# Ensure the options systemd and this VM need are enabled, then let the kernel
# resolve dependencies non-interactively.
scripts/config --enable  CONFIG_DEVTMPFS                \
               --enable  CONFIG_DEVTMPFS_MOUNT          \
               --enable  CONFIG_CGROUPS                 \
               --enable  CONFIG_INOTIFY_USER            \
               --enable  CONFIG_SIGNALFD                \
               --enable  CONFIG_TIMERFD                 \
               --enable  CONFIG_EPOLL                   \
               --enable  CONFIG_FHANDLE                 \
               --enable  CONFIG_SECCOMP                 \
               --enable  CONFIG_SECCOMP_FILTER          \
               --enable  CONFIG_FANOTIFY                \
               --enable  CONFIG_AUTOFS_FS               \
               --enable  CONFIG_TMPFS                   \
               --enable  CONFIG_TMPFS_POSIX_ACL         \
               --enable  CONFIG_TMPFS_XATTR             \
               --enable  CONFIG_CRYPTO_USER_API_HASH    \
               --enable  CONFIG_CRYPTO_HMAC             \
               --enable  CONFIG_CRYPTO_SHA256           \
               --enable  CONFIG_EXT4_FS                 \
               --enable  CONFIG_SATA_AHCI               \
               --enable  CONFIG_ATA                     \
               --enable  CONFIG_ATA_PIIX                \
               --enable  CONFIG_VIRTIO_BLK              \
               --enable  CONFIG_VIRTIO_PCI              \
               --enable  CONFIG_VIRTIO_NET              \
               --enable  CONFIG_E1000                   \
               --enable  CONFIG_BLK_DEV_SD
make olddefconfig
make
make modules_install
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.18.10-lfs-13.0-systemd
cp -iv System.map /boot/System.map-6.18.10
cp -iv .config /boot/config-6.18.10
cp -r Documentation -T /usr/share/doc/linux-6.18.10
finish

# 10.3.1. Configuring Linux Module Load Order
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf

install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

# End /etc/modprobe.d/usb.conf
EOF

# 10.4. Using GRUB to Set Up the Boot Process
# Install GRUB to the MBR of the disk holding the LFS root (GRUB_DISK, provided
# by the orchestration; defaults to /dev/sda). GRUB locates /boot by filesystem
# UUID (search --fs-uuid), which is immune to disk reordering. The kernel's
# root= must use PARTUUID (not the filesystem UUID): without an initramfs -- and
# LFS builds none -- the kernel cannot resolve a filesystem UUID, but it can
# resolve a PARTUUID natively. PARTUUID is likewise immune to disk reordering.
grub-install "$GRUB_DISK"
if [ -n "$ROOT_UUID" ] && [ -n "$ROOT_PARTUUID" ]; then
cat > /boot/grub/grub.cfg << EOF
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_msdos
insmod ext2
search --set=root --fs-uuid $ROOT_UUID

menuentry "GNU/Linux, Linux 6.18.10-lfs-13.0-systemd" {
        linux   /boot/vmlinuz-6.18.10-lfs-13.0-systemd root=PARTUUID=$ROOT_PARTUUID ro
}
EOF
else
cat > /boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_msdos
insmod ext2
set root=(hd0,1)

menuentry "GNU/Linux, Linux 6.18.10-lfs-13.0-systemd" {
        linux   /boot/vmlinuz-6.18.10-lfs-13.0-systemd root=/dev/sda1 ro
}
EOF
fi

# 11.1. The End
echo 13.0-systemd > /etc/lfs-release
cat > /etc/lsb-release << "EOF"
DISTRIB_ID="Linux From Scratch"
DISTRIB_RELEASE="13.0-systemd"
DISTRIB_CODENAME="lfs"
DISTRIB_DESCRIPTION="Linux From Scratch"
EOF
cat > /etc/os-release << "EOF"
NAME="Linux From Scratch"
VERSION="13.0-systemd"
ID=lfs
PRETTY_NAME="Linux From Scratch 13.0-systemd"
VERSION_CODENAME="lfs"
HOME_URL="https://www.linuxfromscratch.org/lfs/"
RELEASE_TYPE="stable"
EOF

echo "[lfs-final] The end"
