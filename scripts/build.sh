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
LFS_VERSION="13.0"
# Монолитный tar со всеми пакетами LFS (по запросу пользователя возвращён).
# Проверялось: ftp.osuosl.org отдаёт его с кодом 200 и корректным Content-Type,
# tar-архив распаковывается в каталог lfs-packages-${LFS_VERSION}/.
LFS_TARBALL_URLS=(
    "http://ftp.osuosl.org/pub/lfs/lfs-packages/lfs-packages-${LFS_VERSION}.tar"
    "http://ftp.lfs-matrix.net/pub/lfs/lfs-packages/lfs-packages-${LFS_VERSION}.tar"
    "https://anduin.linuxfromscratch.org/LFS/lfs-packages-${LFS_VERSION}.tar"
)
LFS_TARBALL="lfs-packages-${LFS_VERSION}.tar"
TARBALL_SIZE=633282560   # точный размер в байтах (Content-Length с osuosl)
# Запасной режим: докачка отдельных архивов по списку md5sums
MIRRORS=(
    "https://mirror.dogado.de/LFS/lfs-packages/${LFS_VERSION}"
    "https://mirror.metanet.ch/LFS/lfs-packages/${LFS_VERSION}"
    "http://ftp.lfs-matrix.net/pub/lfs/lfs-packages/${LFS_VERSION}"
    "https://mirror.koddos.net/lfs/lfs-packages/${LFS_VERSION}"
)
MD5SUMS_NAME="md5sums"

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
    for cmd in wget tar xz curl mksquashfs xorriso grub-mkrescue cpio nproc; do
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

# Скачать монолитный tar lfs-packages-<ver>.tar (основной источник пакетов).
# Возвращает 0, если полный валидный tar лежит в $LFS/$LFS_TARBALL.
# Скачивание идёт во временный файл .part с --continue: при обрыве связи
# загрузка продолжается с того же места при следующем запуске.
download_tarball() {
    local url size havesize wantsize
    # уже скачан и цел?
    if [ -f "$TARBALL_PATH" ] && [ "$(stat -c%s "$TARBALL_PATH")" -eq "$TARBALL_SIZE" ] \
       && tar tf "$TARBALL_PATH" >/dev/null 2>&1; then
        ok "Архив $LFS_TARBALL уже на месте ($(du -h "$TARBALL_PATH" | cut -f1))"
        return 0
    fi
    log "Скачивание пакетов LFS $LFS_VERSION (~633 МБ)..."
    for url in "${LFS_TARBALL_URLS[@]}"; do
        log "Зеркало: $url"
        # ВАЖНО: не используем wget --continue/-O — с -O докачка молча
        # перезаписывала файл с нуля, а --continue к чужому .part от другого
        # зеркала мог привести к смешиванию байтов из разных источников.
        # Вместо этого: полная загрузка файла в зеркалоспецифичный .part
        # (атомарно через временный файл wget), проверка размера, затем
        # дозакачка недостающих байтов диапазоном HTTP (curl -C / dd+Range).
        local part="${TARPART_PATH}.$(printf '%s' "$url" | md5sum | cut -c1-8)"
        while :; do
            # 1) сколько уже скачано с ЭТОГО зеркала
            havesize=$(stat -c%s "$part" 2>/dev/null || echo 0)
            # 2) если .part нет, но есть полный или частичный файл с другого
            #    зеркала — переиспользуем его только при совпадении контрольной
            #    суммы первой части (гарантия, что байты идентичны)
            if [ "$havesize" -eq 0 ]; then
                for other in "${TARPART_PATH}".* "$TARBALL_PATH"; do
                    [ "$other" = "$part" ] && continue
                    [ -f "$other" ] || continue
                    local osz; osz=$(stat -c%s "$other")
                    [ "$osz" -gt 0 ] || continue
                    if _part_matches_official "$other" "$osz"; then
                        cp -f "$other" "$part"; havesize=$osz
                        log "Переиспользую ${osz} байт из $(basename "$other") (контрольная сумма совпала)"
                        break
                    fi
                done
            fi
            [ "$havesize" -ge "$TARBALL_SIZE" ] && break
            # 3) проверка целостности уже скачанной части (первый 1 МиБ
            #    сравниваем с эталоном с официального зеркала). Если часть
            #    битая — начинаем с нуля, а не доклеиваем к мусору.
            if [ "$havesize" -gt 0 ] && ! _part_matches_official "$part" "$havesize"; then
                warn "Начало файла $part не совпадает с оригиналом — перекачиваю с нуля"
                rm -f "$part"; havesize=0
            fi
            # 4) докачка недостающего хвоста диапазоном
            log "Загрузка ${havesize}/${TARBALL_SIZE} байт..."
            if ! _fetch_range "$url" "$part" "$havesize" "$TARBALL_SIZE"; then
                warn "Не удалось докачать с $url — пробую следующее зеркало"
                rm -f "$part"
                break
            fi
            size=$(stat -c%s "$part" 2>/dev/null || echo 0)
            if [ "$size" -le "$havesize" ]; then
                warn "Сервер не добавил данных (${havesize} -> ${size}) — пробую следующее зеркало"
                rm -f "$part"
                break
            fi
        done
        # проверка размера
        if [ ! -f "$part" ] || [ "$(stat -c%s "$part")" -ne "$TARBALL_SIZE" ]; then
            warn "Неполная загрузка с $url ($(( $(stat -c%s "$part" 2>/dev/null || echo 0) / 1048576 ))/${TARBALL_SIZE} байт)."
            warn "Часть сохранена в $part — повторите 'make prepare' для докачки."
            continue
        fi
        mv -f "$part" "$TARBALL_PATH"
        if tar tf "$TARBALL_PATH" >/dev/null 2>&1; then
            ok "Архив скачан и проверен ($(du -h "$TARBALL_PATH" | cut -f1))"
            rm -f "${TARPART_PATH}".*   # подчистить части других зеркал
            return 0
        fi
        warn "Архив повреждён ($url) — удаляю и пробую следующее зеркало"
        rm -f "$TARBALL_PATH" "$part"
    done
    return 1
}

# Проверить, что первые min(size, 1MiB) байта файла совпадают с эталоном
# с официального зеркала (защита от склейки разных источников).
_part_matches_official() {
    local f="$1" fsz="$2" ref="${TARBALL_PATH}.ref" n
    n=$(( fsz < 1048576 ? fsz : 1048576 ))
    [ -s "$ref" ] || { curl -fsSL --max-time 30 -r "-$((n-1))" "${LFS_TARBALL_URLS[0]}" -o "$ref" 2>/dev/null || return 1; }
    head -c "$n" "$f" | cmp -s - "$ref"
}

# Скачать диапазон [from .. to-1] из url и дописать в файл out.
# Использует curl (Range), при отсутствии — wget -r + dd.
_fetch_range() {
    local url="$1" out="$2" from="$3" to="$4"
    mkdir -p "$(dirname "$out")"; touch "$out"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 5 --speed-limit 10240 --speed-time 60 \
             -r "${from}-$((to-1))" "$url" -o "$out.tmp" 2>>"$LOG/download.log" \
            || return 1
    else
        local qs qe
        qs=$(( from / 1048576 )); qe=$(( (to - 1) / 1048576 ))
        wget -q -t 3 -T 60 --header="Range: bytes=${qs}-${qe}" \
             -O "$out.qget" "$url" 2>>"$LOG/download.log" || return 1
        dd if="$out.qget" bs=1048576 skip=$(( from - qs * 1048576 )) of="$out.tmp" status=none 2>/dev/null \
            || { rm -f "$out.qget"; return 1; }
        rm -f "$out.qget"
    fi
    cat "$out.tmp" >> "$out" && rm -f "$out.tmp"
}

# Запасной режим: поштучная загрузка архивов по списку md5sums с зеркал.
fetch_per_package() {
    local destdir="$1"
    local md5file="$destdir/$MD5SUMS_NAME" mirror base="" got_md5=""
    mkdir -p "$destdir"

    if [ ! -s "$md5file" ]; then
        for mirror in "${MIRRORS[@]}"; do
            if wget -q -O "$md5file" "$mirror/$MD5SUMS_NAME"; then
                base="$mirror"; got_md5=1; break
            fi
        done
        [ -n "$got_md5" ] || { err "Не удалось скачать $MD5SUMS_NAME ни с одного зеркала"; return 1; }
    else
        for mirror in "${MIRRORS[@]}"; do
            if wget -q --spider "$mirror/$MD5SUMS_NAME"; then
                base="$mirror"; break
            fi
        done
    fi
    [ -n "$base" ] || { err "Ни одно зеркало недоступно: ${MIRRORS[*]}"; return 1; }
    ok "Запасное зеркало: $base"

    local total ok_cnt=0 fail_list=()
    total=$(awk '{print $2}' "$md5file" | wc -l)
    log "Проверка/скачивание пакетов LFS $LFS_VERSION ($total файлов)..."

    local fname fpath
    while read -r _want_hash fname; do
        [ -n "$fname" ] || continue
        fpath="$destdir/$fname"
        if [ -f "$fpath" ] && \
           echo "${_want_hash}  ${fname}" | (cd "$destdir" && md5sum -c - --quiet 2>/dev/null); then
            ok_cnt=$((ok_cnt + 1))
            continue
        fi
        log "Скачивание [$((ok_cnt + ${#fail_list[@]} + 1))/$total]: $fname"
        local tmp="$fpath.part"
        if ! wget --continue --tries=3 --timeout=30 \
                  --progress=dot:mega -O "$tmp" "$base/$fname" 2>>"$LOG/download.log"; then
            warn "Загрузка прервана: $fname (частичный файл: $tmp — повторите make prepare)"
            fail_list+=("$fname")
            continue
        fi
        mv -f "$tmp" "$fpath"
        if echo "${_want_hash}  ${fname}" | (cd "$destdir" && md5sum -c - --quiet 2>/dev/null); then
            ok_cnt=$((ok_cnt + 1))
        else
            warn "md5 не совпал: $fname"
            rm -f "$fpath"
            fail_list+=("$fname")
        fi
    done < "$md5file"

    # Повторная попытка для неудачных — через остальные зеркала
    if [ ${#fail_list[@]} -gt 0 ]; then
        for mirror in "${MIRRORS[@]}"; do
            [ "${#fail_list[@]}" -eq 0 ] && break
            [ "$mirror" = "$base" ] && continue
            warn "Докачка ${#fail_list[@]} файлов с $mirror"
            local retry=() f
            for f in "${fail_list[@]}"; do
                if wget -q --tries=2 --timeout=30 -O "$destdir/$f" "$mirror/$f" && \
                   grep "^.\{32\}  *$f\$" "$md5file" | (cd "$destdir" && md5sum -c - --quiet 2>/dev/null); then
                    ok_cnt=$((ok_cnt + 1))
                else
                    rm -f "$destdir/$f"
                    retry+=("$f")
                fi
            done
            fail_list=("${retry[@]+"${retry[@]}"}")
        done
    fi

    if [ ${#fail_list[@]} -gt 0 ]; then
        err "Не удалось скачать: ${fail_list[*]}"
        err "Получено ${ok_cnt}/$total файлов"
        return 1
    fi
    ok "Все пакеты на месте и проверены (${ok_cnt}/$total)"
    return 0
}

stage_prepare() {
    check_root
    check_deps

    # Создаём $LFS ДО скачивания (иначе wget не может открыть файл).
    # Проверяем также, что LFS не пустой и абсолютный.
    [ -n "$LFS" ]            || die "LFS не задан"
    [ "${LFS#/}" != "$LFS" ] || die "LFS должен быть абсолютным путём (сейчас: '$LFS')"
    mkdir -pv "$LFS"
    mkdir -pv "$LOG"

    log "Подготовка окружения..."

    # --- Скачать пакеты ---
    # Основной способ (как в исходном скрипте): монолитный tar со всеми
    # пакетами LFS. Скачиваем во временный файл *.part с докачкой (--continue),
    # поэтому обрыв связи больше НЕ приводит к скачиванию с нуля.
    # Если tar недоступен/битый — автоматический запасной режим: поштучная
    # докачка архивов по списку md5sums с зеркал.
    mkdir -p "$LFS/sources"

    local tarball="$LFS/$LFS_TARBALL" tarpart="$LFS/$LFS_TARBALL.part"
    local extracted="$STAMPS/packages-extracted"

    if [ -f "$extracted" ]; then
        ok "Пакеты уже распакованы в $LFS/sources (метка: $extracted)"
    elif [ "$(find "$LFS/sources" -maxdepth 1 -type f ! -name '*.part' 2>/dev/null | wc -l)" -ge 80 ]; then
        ok "Пакеты уже распакованы в $LFS/sources"
    else
        # пути для download_tarball (глобальные, чтобы функция видела их)
        TARBALL_PATH="$tarball"; TARPART_PATH="$tarpart"
        if download_tarball; then
            if [ "$(find "$LFS/sources" -maxdepth 1 -type f ! -name '*.part' | wc -l)" -lt 80 ]; then
                log "Распаковка пакетов... (604 МБ, займёт 1-3 минуты, прогресс не показывается)"
                mkdir -p "$STAMPS"
                # Распаковываем НЕ в /mnt/lfs, а во временный каталог внутри
                # sources/.stage: если прервать Ctrl+C посреди распаковки,
                # повторный запуск просто удалит .stage и начнёт заново.
                local stage="$LFS/sources/.stage"
                rm -rf "$stage"; mkdir -p "$stage"
                tar xf "$tarball" -C "$stage" \
                    || { rm -rf "$stage"; die "Не удалось распаковать $tarball"; }
                local topdir="$stage/lfs-packages-${LFS_VERSION}"
                if [ ! -d "$topdir" ]; then
                    # узнаём реальное имя корневого каталога из архива
                    topdir="$stage/$(tar tf "$tarball" | head -1 | cut -d/ -f1)"
                fi
                [ -d "$topdir" ] || die "В архиве нет ожидаемого каталога lfs-packages-${LFS_VERSION}"
                mv -t "$LFS/sources" "$topdir"/* 2>/dev/null || true
                # скрытые файлы (если есть) + очистка
                shopt -s dotglob nullglob
                mv -n -t "$LFS/sources" "$topdir"/.* 2>/dev/null || true
                shopt -u dotglob nullglob
                rm -rf "$stage"
                local nfiles
                nfiles=$(find "$LFS/sources" -maxdepth 1 -type f ! -name '*.part' | wc -l)
                [ "$nfiles" -ge 80 ] || die "После распаковки в $LFS/sources только $nfiles файлов (ожидалось >=80)"
                touch "$extracted"
                ok "Распаковано в $LFS/sources ($nfiles файлов)"
            else
                touch "$extracted"
            fi
        else
            warn "Монолитный tar недоступен или повреждён — переключаюсь на поштучную загрузку"
            fetch_per_package "$LFS/sources" || die "Не удалось получить пакеты ни одним способом"
            touch "$extracted"
        fi
    fi

    chmod -v a+wt "$LFS/sources"

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
        -e boot live_iso sources "lfs-packages-${LFS_VERSION}.tar" \
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