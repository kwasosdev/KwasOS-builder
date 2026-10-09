#!/bin/bash
# KwasOS Build System — полностью автоматическая сборка
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ============================================================
# КОНФИГУРАЦИЯ (не требует ручного вмешательства)
# ============================================================
LFS="${LFS:-/mnt/lfs}"
VERSION="${VERSION:-1.0}"
KERNEL_VER="6.18.10"
KERNEL_PKG="linux-${KERNEL_VER}"
KERNEL_NAME="vmlinuz-${KERNEL_VER}-lfs-13.0-systemd"
INITRD_NAME="initrd.img-${KERNEL_VER}"
LFS_TARBALL_URL="http://ftp.osuosl.org/pub/lfs/lfs-packages/lfs-packages-13.0.tar"
LFS_TARBALL="lfs-packages-13.0.tar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="${BUILD:-$PROJECT_DIR/build}"
LOG="${LOG:-$PROJECT_DIR/logs}"
STAMPS="$LFS/.stamps"
NPROC="$(nproc)"

# ============================================================
# ЦВЕТА И ЛОГИ
# ============================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ============================================================
# УТИЛИТЫ
# ============================================================
check_root() {
    [ "$EUID" -eq 0 ] || die "Запустите от root: sudo make <stage>"
}

check_deps() {
    local missing=()
    for cmd in wget tar xz mksquashfs xorriso grub-mkrescue cpio nproc; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        err "Отсутствуют утилиты: ${missing[*]}"
        err "Установите: sudo apt install build-essential wget xz-utils \\"
        err "              squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \\"
        err "              mtools cpio busybox-static"
        exit 1
    fi
    [ -f /bin/busybox ] || die "busybox-static не установлен (apt install busybox-static)"
    file /bin/busybox | grep -q "statically linked" || die "/bin/busybox не статический"
}

# Проверить, выполнена ли стадия (по маркеру)
stage_done()  { [ -f "$STAMPS/$1.done" ]; }
mark_done()   { mkdir -p "$STAMPS"; touch "$STAMPS/$1.done"; }

# Выполнить стадию, если не сделана
run_stage() {
    local name="$1"; shift
    if stage_done "$name" && [ "${FORCE:-0}" != "1" ]; then
        ok "Стадия '$name' уже выполнена (пропускаем)"
        return 0
    fi
    log "=== Стадия: $name ==="
    "$@"
    mark_done "$name"
    ok "Стадия '$name' завершена"
}

# Отмонтировать всё в $LFS
unmount_all() {
    for m in dev/pts dev/shm dev proc sys run tmp; do
        if mountpoint -q "$LFS/$m" 2>/dev/null; then
            umount "$LFS/$m" 2>/dev/null || true
        fi
    done
}

# Исправить владельца tools/usr/etc/var (частая проблема после cross)
fix_ownership() {
    local owner="$1"
    chown -R "$owner:$owner" "$LFS/tools" 2>/dev/null || true
    chown -R "$owner:$owner" "$LFS/usr"  2>/dev/null || true
    chown -R "$owner:$owner" "$LFS/var"  2>/dev/null || true
    chown -R "$owner:$owner" "$LFS/etc"  2>/dev/null || true
    chown -R "$owner:$owner" "$LFS/lib64" 2>/dev/null || true
}

# ============================================================
# ЭТАП 1 — PREPARE
# ============================================================
stage_prepare() {
    check_root
    check_deps

    # FIX: создаём $LFS ДО скачивания, иначе wget не может открыть
    #      /mnt/lfs/lfs-packages-13.0.tar (нет родительского каталога).
    #      Проверяем также, что LFS не пустой и абсолютный.
    [ -n "$LFS" ]            || die "LFS не задан"
    [ "${LFS#/}" != "$LFS" ] || die "LFS должен быть абсолютным путём (сейчас: '$LFS')"
    mkdir -pv "$LFS"
    mkdir -pv "$LOG"

    log "Подготовка окружения..."

    # --- Скачать пакеты ---
    if [ ! -f "$LFS/$LFS_TARBALL" ]; then
        log "Скачивание пакетов LFS 13.0 (~633 МБ)..."
        wget --progress=dot:giga -O "$LFS/$LFS_TARBALL" "$LFS_TARBALL_URL" 2>&1 | \
            tee "$LOG/download.log" | tail -5
    else
        ok "Пакеты уже скачаны"
    fi

    # --- Распаковать ---
    if [ ! -d "$LFS/sources" ]; then
        log "Распаковка пакетов..."
        (cd "$LFS" && tar xf "$LFS_TARBALL" && mv lfs-packages-13.0 sources)
        chmod -v a+wt "$LFS/sources"
    else
        ok "Пакеты уже распакованы"
    fi

    # --- Структура LFS ---
    log "Создание базовой структуры..."
    mkdir -pv "$LFS"/{etc,var} "$LFS"/usr/{bin,lib,sbin}
    for i in bin lib sbin; do
        [ -L "$LFS/$i" ] || ln -sv usr/$i "$LFS/$i"
    done
    case $(uname -m) in
        x86_64) mkdir -pv "$LFS/lib64" ;;
    esac
    mkdir -pv "$LFS"/{tools,dev,proc,sys,run,tmp}

    # --- Копировать скрипты ---
    log "Копирование скриптов..."
    [ -f "$PROJECT_DIR"/scripts/lfs-cross.sh ] || \
        die "Нет scripts/lfs-*.sh! Скачайте из luisgbm/lfs-scripts"
    cp -v "$PROJECT_DIR"/scripts/lfs-*.sh "$LFS/"

    # --- Пользователь lfs ---
    if ! id lfs >/dev/null 2>&1; then
        log "Создание пользователя lfs..."
        groupadd lfs
        useradd -s /bin/bash -g lfs -m -k /dev/null lfs
        # Без пароля — root сможет sudo -u lfs без запроса
        passwd -d lfs 2>/dev/null || true
        ok "Пользователь lfs создан (без пароля)"
    fi

    # --- Права ---
    fix_ownership lfs
    ok "Подготовка завершена"
}

# ============================================================
# ЭТАП 2 — CROSS
# ============================================================
stage_cross() {
    check_root
    log "Сборка кросс-тулчейна (главы 5-6)..."

    fix_ownership lfs

    # Очищаем возможные остатки прошлой сборки
    find "$LFS/sources" -maxdepth 1 -type d \( -name 'binutils-*' -o -name 'gcc-*' \) -exec rm -rf {} + rm -rf "$LFS"/tools/*

    # Явно передаём все переменные — никаких .bash_profile!
    sudo -u lfs env -i \
        HOME=/home/lfs \
        TERM="${TERM:-linux}" \
        PS1='\u:\w\$ ' \
        LFS="$LFS" \
        LC_ALL=POSIX \
        LFS_TGT="$(uname -m)-lfs-linux-gnu" \
        PATH="$LFS/tools/bin:/usr/bin:/bin" \
        CONFIG_SITE="$LFS/usr/share/config.site" \
        MAKEFLAGS="-j$NPROC" \
        bash -e "$LFS/lfs-cross.sh" 2>&1 | tee "$LOG/cross.log"

    ok "Кросс-тулчейн собран"
}

# ============================================================
# ЭТАП 3 — CHROOT (глава 7)
# ============================================================
stage_chroot() {
    check_root
    log "Сборка chroot-инструментов (глава 7)..."

    unmount_all

    # --- Владелец root ---
    chown --from lfs -R root:root "$LFS"/{usr,var,etc,tools} 2>/dev/null || true
    case $(uname -m) in
        x86_64) chown --from lfs -R root:root "$LFS/lib64" 2>/dev/null || true ;;
    esac

    # --- Структура директорий (LFS 7.5) ---
    log "Создание директорий (LFS 7.5)..."
    mkdir -pv "$LFS"/{dev,proc,sys,run,tmp}
    chmod 1777 "$LFS/tmp"
    mkdir -pv "$LFS"/{boot,home,mnt,opt,srv}
    mkdir -pv "$LFS"/etc/{opt,sysconfig}
    mkdir -pv "$LFS"/lib/firmware
    mkdir -pv "$LFS"/media/{floppy,cdrom}
    mkdir -pv "$LFS"/usr/{,local/}{include,src}
    mkdir -pv "$LFS"/usr/lib/locale
    mkdir -pv "$LFS"/usr/local/{bin,lib,sbin}
    mkdir -pv "$LFS"/usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -pv "$LFS"/usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -pv "$LFS"/usr/{,local/}share/man/man{1..8}
    mkdir -pv "$LFS"/var/{cache,local,log,mail,opt,spool}
    mkdir -pv "$LFS"/var/lib/{color,misc,locate}
    install -dv -m 0750 "$LFS/root"
    install -dv -m 1777 "$LFS/tmp" "$LFS/var/tmp"
    ln -sfv /run "$LFS/var/run"
    ln -sfv /run/lock "$LFS/var/lock"

    # --- Essential files (LFS 7.6) ---
    log "Создание /etc/passwd, /etc/group, /etc/hosts (LFS 7.6)..."
    cat > "$LFS/etc/passwd" << "PASSWD"
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
PASSWD

    cat > "$LFS/etc/group" << "GROUP"
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
clock:x:14:
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
GROUP

    cat > "$LFS/etc/hosts" << "HOSTS"
127.0.0.1  localhost
::1        localhost
HOSTS

    ln -sfv /proc/self/mounts "$LFS/etc/mtab"

    # Лог-файлы
    touch "$LFS/var/log/"{btmp,lastlog,faillog,wtmp}
    chgrp -v utmp "$LFS/var/log/lastlog"
    chmod -v 664 "$LFS/var/log/lastlog"
    chmod -v 600 "$LFS/var/log/btmp"

    # --- Монтирование ---
    log "Монтирование виртуальных ФС..."
    mount -v --bind /dev "$LFS/dev"
    mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mount -vt proc proc "$LFS/proc"
    mount -vt sysfs sysfs "$LFS/sys"
    mount -vt tmpfs tmpfs "$LFS/run"
    mount -vt tmpfs -o mode=1777 tmpfs "$LFS/tmp"

    # --- Chroot ---
    log "Вход в chroot и сборка..."
    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -e /lfs-chroot.sh 2>&1 | tee "$LOG/chroot.log"

    # --- Отмонтировать ---
    unmount_all
    ok "Chroot-инструменты собраны"
}

# ============================================================
# ЭТАП 4 — SYSTEM (глава 8)
# ============================================================
stage_system() {
    check_root
    log "Сборка базовой системы (глава 8, ~80 пакетов, ~30-60 мин)..."
    unmount_all

    # Перемонтировать (chroot вышел)
    mkdir -pv "$LFS"/{dev,proc,sys,run,tmp}
    mount -v --bind /dev "$LFS/dev"
    mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mount -vt proc proc "$LFS/proc"
    mount -vt sysfs sysfs "$LFS/sys"
    mount -vt tmpfs tmpfs "$LFS/run"
    mount -vt tmpfs -o mode=1777 tmpfs "$LFS/tmp"

    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -e /lfs-system.sh 2>&1 | tee "$LOG/system.log"

    unmount_all
    ok "Базовая система собрана"
}

# ============================================================
# ЭТАП 5 — FINAL (главы 9-11)
# ============================================================
stage_final() {
    check_root
    log "Настройка и ядро (главы 9-11)..."
    unmount_all

    # Патчим grub-install (в WSL/контейнере не работает)
    if grep -q "^grub-install " "$LFS/lfs-final.sh"; then
        sed -i 's|^grub-install |true |' "$LFS/lfs-final.sh"
    fi

    mkdir -pv "$LFS"/{dev,proc,sys,run,tmp}
    mount -v --bind /dev "$LFS/dev"
    mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mount -vt proc proc "$LFS/proc"
    mount -vt sysfs sysfs "$LFS/sys"
    mount -vt tmpfs tmpfs "$LFS/run"
    mount -vt tmpfs -o mode=1777 tmpfs "$LFS/tmp"

    # /boot/grub — grub-install упадёт если нет
    mkdir -pv "$LFS/boot/grub"

    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -e /lfs-final.sh 2>&1 | tee "$LOG/final.log"

    unmount_all

    ok "Ядро и настройка завершены"
}

# ============================================================
# ЭТАП 6 — LIVE
# ============================================================
stage_live() {
    check_root
    log "Сборка Live ISO..."

    local live_dir="$LFS/live_iso"
    rm -rf "$live_dir"
    mkdir -p "$live_dir/boot/grub" "$BUILD"

    # --- Проверка ядра ---
    local kernel_path="$LFS/boot/$KERNEL_NAME"
    [ -f "$kernel_path" ] || die "Ядро не найдено: $kernel_path"
    cp -v "$kernel_path" "$live_dir/boot/"

    # --- System.map и config ---
    [ -f "$LFS/boot/System.map-$KERNEL_VER" ] && \
        cp -v "$LFS/boot/System.map-$KERNEL_VER" "$live_dir/boot/"
    [ -f "$LFS/boot/config-$KERNEL_VER" ] && \
        cp -v "$LFS/boot/config-$KERNEL_VER" "$live_dir/boot/"

    # --- initramfs ---
    log "Сборка initramfs..."
    build_initramfs
    cp -v "$LFS/boot/$INITRD_NAME" "$live_dir/boot/"

    # --- GRUB ---
    log "Копирование grub.cfg..."
    if [ -f "$PROJECT_DIR/configs/grub.cfg" ]; then
        cp -v "$PROJECT_DIR/configs/grub.cfg" "$live_dir/boot/grub/grub.cfg"
    else
        die "Нет configs/grub.cfg"
    fi

    # --- squashfs ---
    log "Создание squashfs (15-30 минут)..."
    rm -f "$live_dir/filesystem.squashfs"
    # FIX: явно исключаем виртуальные каталоги и служебные пути
    mksquashfs "$LFS" "$live_dir/filesystem.squashfs" \
        -comp xz \
        -e boot live_iso sources "${LFS_TARBALL}" \
           proc sys dev run tmp mnt media \
           kwasos-*.iso 2>&1 | tail -20

    # --- ISO ---
    log "Сборка ISO через grub-mkrescue..."
    rm -f "$BUILD/kwasos-$VERSION.iso"
    grub-mkrescue -o "$BUILD/kwasos-$VERSION.iso" "$live_dir" --iso-level 3 2>&1 | tail -10

    [ -f "$BUILD/kwasos-$VERSION.iso" ] || die "ISO не собрался"

    # --- SHA256 ---
    (cd "$BUILD" && sha256sum "kwasos-$VERSION.iso" > "kwasos-$VERSION.iso.sha256")

    ok "ISO готов: $BUILD/kwasos-$VERSION.iso ($(du -h "$BUILD/kwasos-$VERSION.iso" | cut -f1))"
}

# ============================================================
# СБОРКА INITRAMFS (встроенная)
# ============================================================
build_initramfs() {
    local work="/tmp/kwasos-initramfs-$$"
    rm -rf "$work"
    mkdir -p "$work"/{bin,sbin,proc,sys,dev,mnt}

    # busybox
    cp /bin/busybox "$work/bin/busybox"
    chmod +x "$work/bin/busybox"

    # Симлинки
    ( cd "$work/bin"
      for cmd in sh mount umount mkdir mknod switch_root modprobe sleep \
                 echo ls cat mdev blkid; do
          ln -sf busybox "$cmd"
      done )
    ( cd "$work/sbin"
      ln -sf /bin/busybox switch_root
      ln -sf /bin/busybox mdev )

    # init-скрипт
    cp "$PROJECT_DIR/initramfs/init" "$work/init"
    chmod +x "$work/init"

    # Упаковка
    ( cd "$work"
      find . -print0 | cpio --null -ov --format=newc 2>/dev/null | \
          gzip -9 > "$LFS/boot/$INITRD_NAME" )

    rm -rf "$work"

    local size
    size=$(stat -c%s "$LFS/boot/$INITRD_NAME")
    [ "$size" -gt 1000000 ] || die "initrd слишком маленький ($size байт) — что-то не так"
    ok "initramfs собран: $(du -h "$LFS/boot/$INITRD_NAME" | cut -f1)"
}

# ============================================================
# ALL — все стадии
# ============================================================
stage_all() {
    run_stage prepare stage_prepare
    run_stage cross   stage_cross
    run_stage chroot  stage_chroot
    run_stage system  stage_system
    run_stage final   stage_final
    run_stage live    stage_live

    echo ""
    echo "========================================="
    echo " KwasOS $VERSION собран успешно!"
    echo " ISO: $BUILD/kwasos-$VERSION.iso"
    echo "========================================="
}

# ============================================================
# ДИСПЕТЧЕР
# ============================================================
case "${1:-}" in
    prepare) run_stage prepare stage_prepare ;;
    cross)   run_stage cross   stage_cross ;;
    chroot)  run_stage chroot  stage_chroot ;;
    system)  run_stage system  stage_system ;;
    final)   run_stage final   stage_final ;;
    live)    run_stage live    stage_live ;;
    all)     stage_all ;;
    clean)
        rm -rf "$LOG" "$STAMPS"
        ok "Логи и маркеры очищены"
        ;;
    *)
        cat <<HELP
KwasOS Build System

Использование: sudo make <stage>

Стадии:
  prepare   Скачать пакеты, создать структуру, создать пользователя lfs
  cross     Кросс-тулчейн (главы 5-6)
  chroot    Временные инструменты (глава 7)
  system    Базовая система (глава 8, долго!)
  final     Ядро и настройка (главы 9-11)
  live      Сборка Live ISO
  all       Всё подряд
  clean     Очистить логи и маркеры

Переменные:
  FORCE=1   Перезапустить стадию, даже если она помечена как выполненная
  LFS=...   Путь к LFS (по умолчанию /mnt/lfs)
  VERSION=  Версия (по умолчанию 1.0)
HELP
        exit 1
        ;;
esac