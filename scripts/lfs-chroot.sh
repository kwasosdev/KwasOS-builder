#!/bin/bash
# LFS 13.0 Build Script (systemd edition)
# Builds the additional temporary tools from chapter 7
# by Luís Mendes :)
# Updated for LFS 13.0

package_name=""
package_ext=""

begin() {
	package_name=$1
	package_ext=$2

	echo "[lfs-chroot] Starting build of $package_name at $(date)"

	tar xf "/sources/$package_name.$package_ext" || return 1
	cd "$package_name" || return 1
}

finish() {
	echo "[lfs-chroot] Finishing build of $package_name at $(date)"

	cd /sources
	rm -rf "$package_name"
}

# Останавливаем сборку при первой же ошибке (см. комментарий в lfs-cross.sh).
# --- Если запущены на хосте — войти в chroot и перезапустить себя ---
if [ ! -d /sources ]; then
    export LFS="${LFS:-/mnt/lfs}"

    # 1) Каталоги внутри нового корня
    mkdir -pv "$LFS"/{dev,proc,sys,run,tmp,var}
    mkdir -pv "$LFS"/dev/pts

    # 2) Монтирование виртуальных ФС
    mountpoint -q "$LFS/dev"       || mount -v --bind /dev "$LFS/dev"
    mountpoint -q "$LFS/dev/pts"   || mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mountpoint -q "$LFS/proc"      || mount -vt proc proc "$LFS/proc"
    mountpoint -q "$LFS/sys"       || mount -vt sysfs sysfs "$LFS/sys"
    mountpoint -q "$LFS/run"       || mount -vt tmpfs tmpfs "$LFS/run"
    if [ -h "$LFS/dev/shm" ]; then
        mkdir -pv "$LFS/$(readlink "$LFS/dev/shm")"
    else
        mountpoint -q "$LFS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
    fi

    # 3) Копируем скрипт внутрь и запускаем в chroot
    cp -v "$0" "$LFS/tmp/lfs-chroot.sh"
    chroot "$LFS" /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-linux}" \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j$(nproc)" \
        TESTSUITEFLAGS="-j$(nproc)" \
        /bin/bash /tmp/lfs-chroot.sh
    rc=$?

    # 4) Размонтирование (порядок важен)
    for mp in dev/pts dev/shm dev proc sys run; do
        mountpoint -q "$LFS/$mp" && umount -v "$LFS/$mp" || true
    done
    exit $rc
fi
# --- Конец преамбулы; дальше идёт обычная логика, теперь уже внутри chroot ---

# 7.5-7.6. Essential Files and Symlinks, passwd/group/logs
ln -sv /proc/self/mounts /etc/mtab
cat > /etc/hosts <<'EOF'
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

cat > /etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group <<'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

mkdir -pv /var/log
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

# 7.7. Gettext-1.0
begin gettext-1.0 tar.xz
./configure --disable-shared
make
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
finish

# 7.8. Bison-3.8.2
begin bison-3.8.2 tar.xz
./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
make
make install
finish

# 7.9. Perl-5.42.0
begin perl-5.42.0 tar.xz
sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.42/core_perl     \
             -D archlib=/usr/lib/perl5/5.42/core_perl     \
             -D sitelib=/usr/lib/perl5/5.42/site_perl     \
             -D sitearch=/usr/lib/perl5/5.42/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
make
make install
finish

# 7.10. Python-3.14.3
begin Python-3.14.3 tar.xz
./configure --prefix=/usr       \
            --enable-shared     \
            --without-ensurepip \
            --without-static-libpython
make
make install
finish

# 7.11. Texinfo-7.2
begin texinfo-7.2 tar.xz
./configure --prefix=/usr
make
make install
finish

# 7.12. Util-linux-2.41.3
begin util-linux-2.41.3 tar.xz
mkdir -pv /var/lib/hwclock
./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.3
make
make install
finish
