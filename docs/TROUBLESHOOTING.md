# Troubleshooting

## Kernel panic: Attempted to kill init

**Причина:** init не может смонтировать squashfs или overlay.

**Решение:** проверьте, что в ядре включены:
- `CONFIG_SQUASHFS=y`
- `CONFIG_OVERLAY_FS=y`
- `CONFIG_BLK_DEV_LOOP=y`
- `CONFIG_UDF_FS=y`

```bash
grep -E 'CONFIG_(SQUASHFS|OVERLAY_FS|UDF_FS|BLK_DEV_LOOP)=' /mnt/lfs/boot/config-6.18.10
```

## filesystem.squashfs not found

**Причина:** init не находит squashfs на блочных устройствах.

**Решение:** загрузитесь в debug-режиме. В логе смотрите:

```
[init] block devices:
[init] try /dev/sda2 as udf
```

В busybox выполните:

```sh
ls /dev/sd*
mount /dev/sda2 /mnt/t && ls /mnt/t
mount -t iso9660 /dev/sda2 /mnt/t && ls /mnt/t
```

Если squashfs на другом разделе — поправьте список CANDS в `initramfs/init`.

## Чёрный экран при загрузке

**Причина:** nouveau/amdgpu/i915 конфликтуют с simpledrm.

**Решение:** выберите "KwasOS Live (safe mode)" в GRUB — там `nomodeset`.

Для NVIDIA добавьте в grub.cfg параметр `nouveau.config=NvGspRm=1`.

## USB-флешка не определяется

**Причина:** ядро не видит USB-контроллер.

**Решение:** проверьте в конфиге ядра:

```bash
grep -E 'CONFIG_USB_XHCI_HCD=|CONFIG_USB_EHCI_HCD=|CONFIG_USB_STORAGE=' /mnt/lfs/boot/config-6.18.10
```

Всё должно быть `=y` или `=m`.

## Rufus записал ISO, но squashfs обрезан

**Причина:** Rufus в ISO-режиме копирует файлы как есть, но не сохраняет DD-структуру.

**Решение:** используйте balenaEtcher или Rufus в DD-режиме.

(Это все проблемы с которыми столкнулся я, после всё будет дополняться.)