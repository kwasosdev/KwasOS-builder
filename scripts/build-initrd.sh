#!/bin/bash
# Сборка initrd для KwasOS Live
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

LFS="${LFS:-/mnt/lfs}"
INITRAMFS_DIR="${INITRAMFS_DIR:-$(pwd)/initramfs}"
WORK_DIR=$(mktemp -d)
OUTPUT="$LFS/boot/initrd.img-6.18.10"

log() { echo -e "\033[0;34m[initrd]\033[0m $*"; }
ok()  { echo -e "\033[0;32m✓\033[0m $*"; }

log "Подготовка initramfs в $WORK_DIR..."

# Базовая структура
mkdir -p "$WORK_DIR"/{bin,sbin,proc,sys,dev,mnt}
mkdir -p "$WORK_DIR"/mnt/{root,squashfs,overlay,newroot}

# busybox (статический!)
if [ ! -f /bin/busybox ]; then
    echo "ERROR: /bin/busybox не найден. Установите busybox-static."
    exit 1
fi
cp /bin/busybox "$WORK_DIR/bin/busybox"
chmod +x "$WORK_DIR/bin/busybox"

# Симлинки
cd "$WORK_DIR/bin"
for cmd in sh mount umount mkdir mknod switch_root modprobe sleep echo ls; do
    ln -sf busybox "$cmd"
done
cd "$WORK_DIR/sbin"
ln -sf /bin/busybox switch_root
ln -sf /bin/busybox mdev

# Init-скрипт
cp "$INITRAMFS_DIR/init" "$WORK_DIR/init"
chmod +x "$WORK_DIR/init"

# Упаковка
log "Упаковка в $OUTPUT..."
cd "$WORK_DIR"
find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$OUTPUT"
rm -rf "$WORK_DIR"

ok "Готово: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"