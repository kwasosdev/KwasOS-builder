#!/bin/bash
# KwasOS Build Orchestrator
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Абсолютные пути к проекту
LOG="${LOG:-$(pwd)/logs}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NPROC="$(nproc)"
BUILD="${BUILD:-$(pwd)/build}"

# === Конфигурация ===
LFS="${LFS:-/mnt/lfs}"
VERSION="${VERSION:-1.0}"
BUILD_DIR="${BUILD:-$(pwd)/build}"
LFS_TARBALL_URL="http://ftp.osuosl.org/pub/lfs/lfs-packages/lfs-packages-13.0.tar"
LFS_TARBALL="lfs-packages-13.0.tar"

# === Цвета для вывода ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

# === Проверка окружения ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Запустите от root (sudo make ...)"
        exit 1
    fi
}

check_deps() {
    local missing=()
    for cmd in wget tar xz mksquashfs xorriso grub-mkrescue cpio; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        err "Отсутствуют: ${missing[*]}"
        err "Установите их и повторите."
        exit 1
    fi
}

# === Этап 1: Подготовка ===
stage_prepare() {
    check_root
    check_deps
    log "Подготовка окружения..."

    # Создать LFS-директорию
    mkdir -p "$LFS"
    mkdir -pv "$LFS"/{dev,proc,sys,run}

    # Скачать пакеты
    if [ ! -f "$LFS/$LFS_TARBALL" ]; then
        log "Скачивание пакетов LFS 13.0 (~633 МБ)..."
        wget -O "$LFS/$LFS_TARBALL" "$LFS_TARBALL_URL"
    else
        ok "Пакеты уже скачаны"
    fi

    # Распаковать
    if [ ! -d "$LFS/sources" ]; then
        log "Распаковка пакетов..."
        cd "$LFS"
        tar xf "$LFS_TARBALL"
        mv 13.0 sources
        chmod -v a+wt sources
    else
        ok "Пакеты уже распакованы"
    fi

    # Создать структуру
    log "Создание базовой структуры LFS..."
    mkdir -pv "$LFS"/{etc,var} "$LFS"/usr/{bin,lib,sbin}
    for i in bin lib sbin; do
        [ -L "$LFS/$i" ] || ln -sv usr/$i "$LFS/$i"
    done
    case $(uname -m) in
        x86_64) mkdir -pv "$LFS/lib64" ;;
    esac
    mkdir -pv "$LFS/tools"

    # Копировать скрипты
    log "Копирование скриптов..."
    cp -v "$PROJECT_DIR"/scripts/lfs-*.sh "$LFS/"

    # Создать пользователя lfs
    if ! id lfs >/dev/null 2>&1; then
        log "Создание пользователя lfs..."
        groupadd lfs
        useradd -s /bin/bash -g lfs -m -k /dev/null lfs
        warn "Задайте пароль для пользователя lfs:"
        passwd lfs
    fi

    # Права
    chown -v lfs "$LFS"/{usr{,/*},var,etc,tools}
    chown -Rv lfs "$LFS/tools"
    case $(uname -m) in
        x86_64) chown -v lfs "$LFS/lib64" ;;
    esac

    ok "Подготовка завершена"
}

# === Этап 2: Кросс-тулчейн ===
stage_cross() {
    check_root
    log "Сборка кросс-тулчейна (главы 5-6)..."

    # Гарантируем, что lfs владеет всей структурой
    chown -R lfs:lfs "$LFS"/usr "$LFS"/var "$LFS"/etc "$LFS"/tools "$LFS"/lib64

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

# === Этап 3: Chroot-инструменты ===
stage_chroot() {
    check_root
    log "Сборка chroot-инструментов (глава 7)..."

    # Передать владение root
    chown --from lfs -R root:root "$LFS"/{usr,var,etc,tools}
    case $(uname -m) in
        x86_64) chown --from lfs -R root:root "$LFS/lib64" ;;
    esac

    # Монтирование
    mount -v --bind /dev "$LFS/dev"
    mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mount -vt proc proc "$LFS/proc"
    mount -vt sysfs sysfs "$LFS/sys"
    mount -vt tmpfs tmpfs "$LFS/run"

    # Chroot
    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -c "bash /lfs-chroot.sh"

    ok "Chroot-инструменты собраны"
}

# === Этап 4: Базовая система ===
stage_system() {
    check_root
    log "Сборка базовой системы (глава 8)..."

    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -c "bash /lfs-system.sh"

    ok "Базовая система собрана"
}

# === Этап 5: Ядро и финал ===
stage_final() {
    check_root
    log "Сборка ядра и финальная настройка (главы 9-11)..."

    chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(kwasos) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$NPROC" \
        TESTSUITEFLAGS="-j$NPROC" \
        /bin/bash -c "bash /lfs-final.sh"

    ok "Ядро и настройка завершены"
}

# === Этап 6: Live ISO ===
stage_live() {
    check_root
    log "Сборка Live ISO..."

    local live_dir="$LFS/live_iso"
    mkdir -p "$live_dir/boot/grub" "$BUILD"

    # Ядро и initrd
    log "Копирование ядра..."
    cp -v "$LFS/boot/vmlinuz-6.18.10-kwasos-1.0" "$live_dir/boot/"
    cp -v "$LFS/boot/System.map-6.18.10"         "$live_dir/boot/"
    cp -v "$LFS/boot/config-6.18.10"             "$live_dir/boot/"
    cp -v "$LFS/boot/initrd.img-6.18.10"         "$live_dir/boot/"

    # GRUB конфиг
    log "Копирование grub.cfg..."
    cp -v "$PROJECT_DIR/configs/grub.cfg" "$live_dir/boot/grub/grub.cfg"

    # Squashfs
    log "Создание squashfs (это займёт 15-30 минут)..."
    rm -f "$live_dir/filesystem.squashfs"
    mksquashfs "$LFS" "$live_dir/filesystem.squashfs" \
        -comp xz \
        -e boot live_iso sources lfs-packages-13.0.tar kwasos-*.iso

    # ISO
    log "Сборка ISO..."
    rm -f "$BUILD/kwasos-$VERSION.iso"
    grub-mkrescue -o "$BUILD/kwasos-$VERSION.iso" "$live_dir" --iso-level 3

    # SHA256
    log "Вычисление контрольной суммы..."
    (cd "$BUILD" && sha256sum "kwasos-$VERSION.iso" > "kwasos-$VERSION.iso.sha256")

    ok "ISO готов: $BUILD/kwasos-$VERSION.iso"
    log "SHA256: $(cat $BUILD/kwasos-$VERSION.iso.sha256)"
}

# === Диспетчер ===
case "${1:-}" in
    prepare) stage_prepare ;;
    cross)   stage_cross ;;
    chroot)  stage_chroot ;;
    system)  stage_system ;;
    final)   stage_final ;;
    live)    stage_live ;;
    *)
        echo "Использование: $0 {prepare|cross|chroot|system|final|live}"
        exit 1
        ;;
esac