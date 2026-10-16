# shellcheck shell=bash
# Универсальная преамбула для скриптов, работающих внутри chroot.
# Подключается через: source "$(dirname "$0")/chroot-reexec.sh"
# Если мы на хосте (нет /sources) — монтирует виртуальные ФС и перезапускает
# текущий скрипт через chroot. После выхода размонтирует.

# (c) kirka

if [ ! -d /sources ]; then
    export LFS="${LFS:-/mnt/lfs}"
    SELF="$(readlink -f "$0")"
    SELF_NAME="$(basename "$SELF")"

    mkdir -pv "$LFS"/{dev,proc,sys,run,tmp,var}
    mkdir -pv "$LFS"/dev/pts

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

    cp -v "$SELF" "$LFS/tmp/$SELF_NAME"
    chroot "$LFS" /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-linux}" \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j$(nproc)" \
        TESTSUITEFLAGS="-j$(nproc)" \
        /bin/bash "/tmp/$SELF_NAME"
    rc=$?

    for mp in dev/pts dev/shm dev proc sys run; do
        mountpoint -q "$LFS/$mp" && umount -v "$LFS/$mp" || true
    done
    exit $rc
fi
