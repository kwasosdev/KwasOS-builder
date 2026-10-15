# KwasOS Initramfs

Минимальный initramfs на базе BusyBox для KwasOS Live.

## Как это работает

1. Ядро распаковывает initramfs в RAM
2. Запускается `/init` (BusyBox sh)
3. `mdev` сканирует устройства и создаёт узлы в `/dev`
4. Явно загружаются модули USB/SATA/NVMe
5. Скрипт ищет `filesystem.squashfs` на всех блочных устройствах,
   пробуя разные ФС (udf, iso9660, vfat, ext4)
6. Squashfs монтируется через loop, overlayfs даёт запись в RAM
7. `switch_root` передаёт управление systemd

## Сборка

```bash
sudo bash ../scripts/build-initrd.sh
```

## Требования к пакетам

- `busybox` (static)
- cpio
- gzip