# Установка и сборка KwasOS

## Требования

### Аппаратные
- 30+ ГБ свободного места
- 4+ ГБ RAM (рекомендуется 8 ГБ)
- Интернет-соединение

### Программные (хост-система)
- Ubuntu 22.04+ / Arch / Fedora
- GCC, Make, Bison, Gawk, Texinfo
- Python 3, wget, xz-utils
- squashfs-tools, xorriso, grub-pc-bin, grub-efi-amd64-bin
- cpio, mtools

## Установка зависимостей

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y build-essential bison gawk texinfo python3 wget \
    xz-utils squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    mtools cpio busybox-static
```

### Arch

```bash
sudo pacman -S --needed base-devel wget xz squashfs-tools xorriso \
    grub mtools cpio busybox
```

## Пошаговая сборка

### Шаг 1: Клонирование

```bash
git clone https://github.com/your-username/kwasos-build.git
cd kwasos-build
```

### Шаг 2: Подготовка (5-10 минут)

```bash
sudo make prepare
```

Скачивает пакеты LFS 13.0 (~633 МБ), создаёт структуру в `/mnt/lfs`, создаёт пользователя `lfs`.

### Шаг 3: Кросс-тулчейн (30-60 минут)

```bash
sudo make cross
```

Собирает binutils, GCC, glibc для целевой системы.

### Шаг 4: Chroot-инструменты (20-40 минут)

```bash
sudo make chroot
```

Утилиты главы 7 (gettext, perl, python, util-linux).

### Шаг 5: Базовая система (1.5-3 часа)

```bash
sudo make system
```

~80 пакетов главы 8. Самый долгий этап.

### Шаг 6: Ядро и настройка (30-60 минут)

```bash
sudo make final
```

Ядро 6.18.10, конфиги, GRUB.

### Шаг 7: Live ISO (20-40 минут)

```bash
sudo make live
```

Собирает squashfs и ISO в `build/kwasos-1.0.iso`.

## Проверка результата

```bash
ls -lh build/
# build/kwasos-1.0.iso
# build/kwasos-1.0.iso.sha256
```

Проверка SHA256:

```bash
cd build && sha256sum -c kwasos-1.0.iso.sha256
```

## Запись на USB

См. README.md в корне репозитория.

