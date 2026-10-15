# Changelog

Все значимые изменения проекта.

## [1.0.0] — 2026-10-05

### Добавлено
- Первый релиз KwasOS
- База: LFS 13.0-systemd
- Ядро: 6.18.10
- systemd 259.1
- GCC 15.2.0, Glibc 2.43, Binutils 2.46.0
- Универсальная поддержка GPU: nouveau, amdgpu, i915
- Firmware: linux-firmware (2 ГБ)
- Гибридный ISO: UEFI + BIOS
- initramfs с mdev и перебором разделов
- Btrfs/UDF/ISO9660/VFAT поддержка

### Известные проблемы
- NVIDIA RTX 40-серии: требуется `nouveau.config=NvGspRm=1`
- Проприетарные драйверы NVIDIA не включены
- Нет установщика на диск (только Live-режим)