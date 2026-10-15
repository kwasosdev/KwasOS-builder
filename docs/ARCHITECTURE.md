# Архитектура сборки

## Общая схема

```
[Хост-система] [Целевая система]
│ │
│ 1. prepare (скачать, структура) │
│─────────────────────────────────────>│ /mnt/lfs
│ │
│ 2. cross (кросс-тулчейн) │
│─────────────────────────────────────>│ /mnt/lfs/tools
│ │
│ 3. chroot (временные утилиты) │
│─────────────────────────────────────>│ /mnt/lfs/usr
│ │
│ 4. system (базовая система) │
│─────────────────────────────────────>│ /mnt/lfs
│ │
│ 5. final (ядро + настройка) │
│─────────────────────────────────────>│ /mnt/lfs/boot
│ │
│ 6. live (squashfs + ISO) │
│─────────────────────────────────────>│ build/kwasos-1.0.iso
```

## Компоненты

### Скрипты сборки
- `lfs-cross.sh` — главы 5–6 (binutils, GCC, glibc)
- `lfs-chroot.sh` — глава 7 (gettext, perl, python, util-linux)
- `lfs-system.sh` — глава 8 (~80 пакетов)
- `lfs-final.sh` — главы 9–11 (ядро, GRUB)

### Initramfs
- BusyBox (статический)
- mdev для hotplug
- Поиск squashfs на всех блочных устройствах
- Overlayfs для записи в RAM

### Ядро
- CONFIG_SQUASHFS=y, CONFIG_OVERLAY_FS=y, CONFIG_UDF_FS=y
- GPU-драйверы как модули (=m)
- Firmware: linux-firmware

### Live-система
- squashfs (xz compression)
- overlayfs (tmpfs upper)
- systemd 259.1
- Гибридный GRUB (BIOS + UEFI)

## Порядок загрузки

```
BIOS/UEFI → GRUB → vmlinuz → initrd → /init (busybox)
→ mdev → поиск squashfs → mount → overlay → switch_root
→ systemd → login
```

