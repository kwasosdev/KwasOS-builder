# KwasOS builder

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Based on LFS 13.0](https://img.shields.io/badge/LFS-13.0--systemd-orange.svg)](https://www.linuxfromscratch.org/lfs/)
[![Kernel](https://img.shields.io/badge/Kernel-6.18.10-green.svg)](https://www.kernel.org/)

**KwasOS** — кастомный Live Linux дистрибутив, собранный с нуля на базе Linux From Scratch 13.0 (systemd edition). Проект представляет собой набор скриптов и конфигураций для автоматической сборки загрузочного LiveUSB/LiveCD.

## ✨ Особенности

- **Универсальная графика** — открытые драйверы NVIDIA (`nouveau`), AMD (`amdgpu`), Intel (`i915`) собраны как модули и загружаются автоматически.
- **Быстрая загрузка** — squashfs + overlayfs, старт за 15–20 секунд.
- **Полный toolchain** — GCC, Binutils, Glibc, Python, Perl для сборки софта из исходников.
- **systemd 259.1** — управление сервисами, сеть через systemd-networkd.
- **Гибридный ISO** — загружается и на UEFI, и на Legacy BIOS.
- **Без bloatware** — только необходимые пакеты, никаких Snap/Flatpak/телеметрии.

## 📋 Системные требования

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| CPU | x86_64, 1 ГГц | 2+ ядра |
| RAM | 2 ГБ | 4 ГБ |
| USB-флешка | 4 ГБ | 8 ГБ |
| Место на диске хоста | 30 ГБ | 50 ГБ |

## 🚀 Быстрый старт

### 1. Клонировать репозиторий

```bash
git clone https://github.com/your-username/kwasos-build.git
cd kwasos-build
```

### 2. Подготовить хост-систему

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y build-essential bison gawk texinfo python3 wget \
    xz-utils squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    mtools cpio
```

Arch:

```bash
sudo pacman -S --needed base-devel wget xz squashfs-tools xorriso \
    grub mtools cpio
```

### 3. Запустить сборку

```bash
sudo make all
```

Или пошагово:

```bash
sudo make prepare    # Скачать пакеты, создать структуру
sudo make cross      # Собрать кросс-тулчейн (главы 5–6)
sudo make chroot     # Дополнительные временные инструменты (глава 7)
sudo make system     # Базовая система (глава 8)
sudo make final      # Ядро + финальная настройка (главы 9–11)
sudo make live       # Собрать Live ISO
```

Результат: `build/kwasos-1.0.iso` (~1.2 ГБ).

## Запись на USB

### !!! Важно: используйте DD-режим, а не ISO-режим !!!

### balenaEtcher (рекомендуется)

1. Скачайте с https://etcher.balena.io/
2. Выберите `kwasos-1.0.iso` -> флешка -> Flash!

### Rufus (BIOS)

1. Скачайте с https://rufus.ie/
2. Выберите ISO, MBR схему раздела
3. Нажмите СТАРТ
4. В появившемся окне выберите «Запись в режиме DD-образ»

### Rufus (UEFI)

1. Скачайте с https://rufus.ie/
2. Выберите ISO, GPT схему раздела
3. Нажмите СТАРТ
4. В появившемся окне выберите «Запись в режиме DD-образ»

### dd (Linux)

```bash
lsblk # Найдите флешку
sudo dd if=build/kwasos-1.0.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Загрузка

1. Вставьте флешку
2. В BIOS/UEFI: Secure Boot → Disabled, Fast Boot → Disabled
3. Выберите USB в Boot Menu (`F12`, `F11`, `Esc` — зависит от материнки)
4. Выберите «KwasOS 1.0 Live»

Логин: `root`
Пароль: `root`
(Пока что)

## Структура проекта

```
├── scripts/          # Скрипты сборки
├── initramfs/        # initrd (busybox + /init)
├── configs/          # Конфиги ядра, GRUB, os-release
├── docs/             # Документация
├── patches/          # Патчи к пакетам
└── Makefile          # Оркестратор сборки
```

## Документация

- docs/INSTALL.md — подробная инструкция по сборке
- docs/TROUBLESHOOTING.md — частые проблемы и решения
- docs/ARCHITECTURE.md — как устроена сборка
- docs/CHANGELOG.md — история версий

## Contributing

Pull requests приветствуются. Для крупных изменений сначала откройте issue.

## Лицензия

GPL v3 — см. LICENSE.

## Благодарности

- ОГРОМНОЕ спасибо основателю Linux From Scratch - Герард Бикманс (Gerard Beekmans). За его прекрасную книгу.
- https://github.com/luisgbm/lfs-scripts/ — помощь с первой сборкой (скрипты)
- Сообщество LFS за бесценную документацию