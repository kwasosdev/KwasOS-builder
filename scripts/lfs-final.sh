#!/bin/bash
# LFS 13.0 Build Script (systemd edition)
# Final steps to configure and boot the system (chapters 9-11)
# by Luís Mendes :)
# Updated for LFS 13.0
# FIX: добавлены опции ядра для Live-режима (squashfs/overlay/loop/USB),
#      брендинг заменён с LFS на KwasOS.

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
# FIX: kwasos вместо lfs
echo "kwasos" > /etc/hostname

# 9.2.6. Customizing the /etc/hosts File
# FIX: kwasos вместо lfs
cat > /etc/hosts << "EOF"
# Begin /etc/hosts

127.0.0.1 localhost.localdomain localhost
127.0.1.1 kwasos
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
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none

"\eOd": backward-word
"\eOc": forward-word

"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

"\eOH": beginning-of-line
"\eOF": end-of-line

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

# --- Base options systemd needs ---
# FIX: расширен набор опций — теперь ядро умеет squashfs/overlay/loop,
#      читает ISO9660/UDF, видит USB-накопители и Fat-разделы.
#      Всё это должно быть =y (встроено), потому что initramfs
#      не содержит модулей и busybox modprobe не сможет их подгрузить.
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
               --enable  CONFIG_BLK_DEV_SD              \
               --enable  CONFIG_SCSI                    \
               \
               --enable  CONFIG_SQUASHFS                \
               --enable  CONFIG_SQUASHFS_XZ             \
               --enable  CONFIG_OVERLAY_FS              \
               --enable  CONFIG_BLK_DEV_LOOP            \
               --enable  CONFIG_BLK_DEV_INITRD          \
               --enable  CONFIG_RD_GZIP                 \
               \
               --enable  CONFIG_ISO9660_FS              \
               --enable  CONFIG_UDF_FS                  \
               --enable  CONFIG_VFAT_FS                 \
               --enable  CONFIG_FAT_FS                  \
               --enable  CONFIG_MSDOS_FS                \
               --enable  CONFIG_NLS_CODEPAGE_437        \
               --enable  CONFIG_NLS_ISO8859_1           \
               --enable  CONFIG_NLS_UTF8                \
               \
               --enable  CONFIG_USB_SUPPORT             \
               --enable  CONFIG_USB                     \
               --enable  CONFIG_USB_XHCI_HCD            \
               --enable  CONFIG_USB_EHCI_HCD            \
               --enable  CONFIG_USB_OHCI_HCD            \
               --enable  CONFIG_USB_STORAGE             \
               --enable  CONFIG_USB_UAS                 \
               --enable  CONFIG_USB_HID                 \
               --enable  CONFIG_HID_GENERIC             \
               --enable  CONFIG_INPUT_EVDEV             \
               --enable  CONFIG_INPUT_KEYBOARD          \
               --enable  CONFIG_KEYBOARD_ATKBD          \
               --enable  CONFIG_SERIO                   \
               --enable  CONFIG_SERIO_I8042             \
               \
               --enable  CONFIG_FB                      \
               --enable  CONFIG_FRAMEBUFFER_CONSOLE     \
               --enable  CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY \
               --enable  CONFIG_DRM                     \
               --enable  CONFIG_DRM_SIMPLEDRM           \
               --enable  CONFIG_DRM_I915                \
               --enable  CONFIG_DRM_AMDGPU              \
               --enable  CONFIG_DRM_NOUVEAU

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
# FIX: релиз теперь KwasOS, а не Linux From Scratch.
echo 13.0-systemd > /etc/lfs-release

cat > /etc/lsb-release << "EOF"
DISTRIB_ID="KwasOS"
DISTRIB_RELEASE="1.0"
DISTRIB_CODENAME="kwasik"
DISTRIB_DESCRIPTION="KwasOS 1.0"
EOF

cat > /etc/os-release << "EOF"
NAME="KwasOS"
VERSION="1.0"
ID=kwasos
ID_LIKE=lfs
PRETTY_NAME="KwasOS 1.0"
VERSION_CODENAME="kwasik"
HOME_URL="https://github.com/kwasosdev/KwasOS"
RELEASE_TYPE="stable"
EOF

echo "[lfs-final] The end"