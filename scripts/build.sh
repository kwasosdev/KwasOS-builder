#!/usr/bin/env bash
#==============================================================================
# KwasOS-builder — скрипт подготовки и сборки LFS 13.0
#
# Стадии: prepare | build | configure | package | iso | all
#
# Особенности стадии prepare:
#  * Скачивается МОНОЛИТНЫЙ tar со всеми пакетами LFS (~633 МБ), как в оригинале.
#  * Загрузка идёт во временный каталог на зеркало; НЕ используется wget -O
#    вместе с -c (с -O докачка молча отключается и качает с нуля).
#  * При обрыве связи повторный запуск продолжает загрузку с того же байта.
#  * Прогресс wget (-nv пишет его в stderr) перенаправляется в logs/download.log.
#  * После загрузки проверяются точный размер и целостность архива (tar tf);
#    битый/неполный файл с одного зеркала -> автоматический переход на следующее.
#  * Распаковка выполняется во временный каталог и только при успехе
#    перемещается в /mnt/lfs/sources (защита от «огрызков» при Ctrl+C).
#  * Повторные запуски дешёвые: готовый tar переиспользуется, распаковка
#    помечается отметкой .unpack-done и пропускается.
#==============================================================================
set -u

LFS="${LFS:-/mnt/lfs}"
SRC="$LFS/sources"
LOG="$(cd "$(dirname "$0")/.." && pwd)/logs"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)"

LFS_VERSION="13.0"
TARBALL_SIZE=633282560   # точный Content-Length lfs-packages-13.0.tar
LFS_TARBALL="lfs-packages-13.0.tar"
LFS_TARBALL_URLS=(
    "http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_TARBALL}"
    "https://anduin.linuxfromscratch.org/LFS/${LFS_TARBALL}"
    "http://mirrors.lfs-matrix.net/pub/lfs/lfs-packages/${LFS_TARBALL}"
)
# Запасной режим: поштучная докачка пакетов по списку md5sums
MD5SUMS_URLS=(
    "http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_VERSION}/md5sums"
    "https://anduin.linuxfromscratch.org/LFS/${LFS_VERSION}-packages.md5"
)

#------------------------------------------------------------------------------
# Служебные функции
#------------------------------------------------------------------------------
log()  { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }
warn() { printf '[%(%H:%M:%S)T] ПРЕДУПРЕЖДЕНИЕ: %s\n' -1 "$*" >&2; }
die()  { printf '[%(%H:%M:%S)T] ОШИБКА: %s\n' -1 "$*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Запускайте через sudo make ..."
}

init_dirs() {
    mkdir -p "$LFS" "$SRC" "$LOG"
    chmod a+wt "$LFS" 2>/dev/null || true
}

#------------------------------------------------------------------------------
# Подготовка: скачивание и распаковка пакетов
#------------------------------------------------------------------------------

# Целостность готового tar: точный размер + читается ли архив целиком
check_tarball() {
    local f="$1" size
    [[ -f "$f" ]] || return 1
    size=$(stat -c%s "$f")
    if (( size != TARBALL_SIZE )); then
        warn "Размер $f = $size, ожидалось $TARBALL_SIZE"
        return 1
    fi
    if ! tar tf "$f" >/dev/null 2>&1; then
        warn "Архив $f повреждён (tar tf не проходит)"
        return 1
    fi
    return 0
}

# Загрузка монолитного tar с зеркал с корректной докачкой.
download_tarball() {
    local url urlhash partdir part got rc odd
    for url in "${LFS_TARBALL_URLS[@]}"; do
        log "Зеркало: $url"

        # Уникальный каталог на каждое зеркало: нельзя склеивать байты
        # из разных источников (даже если имя файла одинаковое).
        urlhash=$(printf '%s' "$url" | md5sum | cut -c1-8)
        partdir="$LFS/.dl-$urlhash"
        part="$partdir/$LFS_TARBALL"
        mkdir -p "$partdir"

        got=$(stat -c%s "$part" 2>/dev/null || echo 0)
        log "Загрузка $got/$TARBALL_SIZE байт уже есть."

        # Если загрузка уже завершена, но проверка ещё не выполнялась
        # (например, прошлый запуск прервали Ctrl+C сразу после wget),
        # сразу переходим к проверке целостности.
        if (( got == TARBALL_SIZE )); then
            log "Файл уже загружен полностью, проверяю целостность..."
        else
            log "Прогресс в реальном времени: tail -f $LOG/download.log"

            # ВАЖНО: НЕ используем -O — с ним --continue молча качает с нуля.
            # wget запускается из partdir и пишет в ./$LFS_TARBALL(.part).
            # Прогресс (-nv пишет его в STDERR!) перенаправляем именно так:
            # stdout+stderr -> logs/download.log.
            if ! ( cd "$partdir" && \
                   wget -c -nv --progress=dot:mega --tries=10 \
                        --timeout=60 --waitretry=15 \
                        --user-agent="wget" "$url" ) >>"$LOG/download.log" 2>&1; then
                warn "wget завершился с ошибкой (см. $LOG/download.log)"
            fi
        fi

        # wget без -O может оставить имя вида file.tar.part.NNN — нормализуем.
        if [[ ! -f "$part" ]]; then
            odd=$(find "$partdir" -maxdepth 1 -name "${LFS_TARBALL}.part.*" -type f 2>/dev/null | head -n1)
            [[ -n "$odd" ]] && mv -f "$odd" "$part"
        fi
        # Если остался .part от предыдущих версий wget — объединяем один раз.
        if [[ -f "$part" && -f "$part.part" ]]; then
            cat "$part.part" >> "$part" && rm -f "$part.part"
        fi

        if check_tarball "$part"; then
            mv -f "$part" "$SRC/$LFS_TARBALL"
            rm -rf "$partdir"
            log "✓ Архив скачан и проверен ($(du -h "$SRC/$LFS_TARBALL" | cut -f1))"
            return 0
        fi

        # Неполный файл: если размер меньше ожидаемого — это просто
        # обрыв связи, оставляем часть для докачки при следующем запуске.
        rc=$?
        got=$(stat -c%s "$part" 2>/dev/null || echo 0)
        if (( got > 0 && got < TARBALL_SIZE )); then
            warn "Загрузка прервана на ${got}/${TARBALL_SIZE} байт (rc=$rc)."
            warn "Повторите: sudo make prepare — продолжит с этого места."
            return 1
        fi
        # Размер «достигнут», но архив битый -> пробуем следующее зеркало.
        warn "Файл с $url непригоден, пробую следующее зеркало..."
        rm -f "$part" "$part".part
    done
    return 1
}

# Запасной вариант: поштучная докачка пакетов по списку md5sums.
fetch_per_package() {
    local md5file base name sum u ok=0 fail=0
    md5file="$SRC/md5sums"
    if [[ ! -s "$md5file" ]]; then
        for u in "${MD5SUMS_URLS[@]}"; do
            if wget -c -nv -O "$md5file.tmp" "$u" >>"$LOG/download.log" 2>&1; then
                mv -f "$md5file.tmp" "$md5file"; break
            fi
            rm -f "$md5file.tmp"
        done
    fi
    [[ -s "$md5file" ]] || { warn "Не получен список md5sums"; return 1; }

    base="http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_VERSION}"
    while read -r sum name _; do
        [[ -z "${name:-}" ]] && continue
        if [[ -f "$SRC/$name" ]] && echo "$sum  $SRC/$name" | md5sum -c --status - 2>/dev/null; then
            ok=$((ok+1)); continue
        fi
        if wget -c -nv -O "$SRC/$name" "$base/$name" >>"$LOG/download.log" 2>&1 \
           && echo "$sum  $SRC/$name" | md5sum -c --status - 2>/dev/null; then
            ok=$((ok+1))
        else
            warn "Пакет $name не удалось получить/проверить"; fail=$((fail+1))
        fi
    done < "$md5file"
    log "Поштучно: ок=$ok, ошибок=$fail"
    (( fail == 0 ))
}

stage_prepare() {
    require_root
    init_dirs
    log "=== Стадия: prepare ==="
    log "Подготовка окружения..."

    # Уже распаковано? (отметка или большое число файлов) — ничего не делаем.
    if [[ -f "$SRC/.unpack-done" ]]; then
        log "Пакеты уже распакованы ($SRC/.unpack-done) — пропускаю."
        return 0
    fi
    local nfiles
    nfiles=$(find "$SRC" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if (( nfiles >= 80 )); then
        touch "$SRC/.unpack-done"
        log "В $SRC уже $nfiles файлов — считаю распакованным, пропускаю."
        return 0
    fi

    # Нужен ли вообще скачивать? Готовый tar переиспользуем.
    if ! check_tarball "$SRC/$LFS_TARBALL"; then
        rm -f "$SRC/$LFS_TARBALL"
        log "Скачивание пакетов LFS $LFS_VERSION (~633 МБ)..."
        if ! download_tarball; then
            warn "Переключаюсь на поштучную загрузку пакетов..."
            fetch_per_package || die "Не удалось получить пакеты LFS. Повторите: sudo make prepare"
            touch "$SRC/.unpack-done"
            log "✓ Пакеты готовы (поштучный режим)."
            return 0
        fi
    else
        log "✓ Архив уже скачан и цел ($SRC/$LFS_TARBALL), пропущено."
    fi

    log "Распаковка пакетов (~633 МБ, обычно 1–3 минуты, зависит от диска)..."
    local tmpd root real
    tmpd="$LFS/.unpack-tmp"
    rm -rf "$tmpd"
    mkdir -p "$tmpd"

    # Распаковываем ВО ВРЕМЕННЫЙ каталог: при Ctrl+C/нехватке памяти не
    # остаётся «огрызков» в sources, и следующий запуск начнёт чисто.
    if ! tar xf "$SRC/$LFS_TARBALL" -C "$tmpd"; then
        rm -rf "$tmpd"
        die "Распаковка $SRC/$LFS_TARBALL завершилась с ошибкой (нехватка места?)"
    fi

    # Ищем реальный корневой каталог архива (обычно lfs-packages-13.0).
    root="$tmpd/lfs-packages-${LFS_VERSION}"
    if [[ ! -d "$root" ]]; then
        real=$(tar tf "$SRC/$LFS_TARBALL" 2>/dev/null | head -n1 | cut -d/ -f1)
        if [[ -n "$real" && -d "$tmpd/$real" ]]; then
            root="$tmpd/$real"
        else
            # Архив без единого корневого каталога — содержимое tmpd и есть packages
            root="$tmpd"
        fi
    fi
    [[ -d "$root" ]] || { rm -rf "$tmpd"; die "Не найден корневой каталог распакованного архива"; }

    # Переносим в sources: сначала содержимое, потом отметка о завершении.
    if [[ "$root" == "$tmpd" ]]; then
        cp -a "$tmpd"/. "$SRC"/
    else
        cp -a "$root"/. "$SRC"/
    fi
    rm -rf "$tmpd"

    touch "$SRC/.unpack-done"
    log "✓ Распаковано в $SRC ($(find "$SRC" -maxdepth 1 -type f | wc -l) файлов)."
}

#------------------------------------------------------------------------------
# Запуск скриптов сборки глав LFS (5–11) с отметками о завершении
#------------------------------------------------------------------------------
STAMPS="$LFS/.stamps"

run_stage_script() {
    # $1 — имя стадии (cross|chroot|system|final), $2 — скрипт в scripts/
    local name="$1" script="$BUILD_DIR/scripts/$2"
    require_root
    init_dirs
    mkdir -p "$STAMPS"
    if [[ -f "$STAMPS/$name.done" ]]; then
        log "Стадия '$name' уже выполнена ($STAMPS/$name.done) — пропускаю."
        log "Для пересборки: rm -f $STAMPS/$name.done (или 'sudo make clean')."
        return 0
    fi
    [[ -x "$SRC" ]] || die "Каталог $SRC не найден. Сначала выполните: sudo make prepare"
    [[ -f "$script" ]] || die "Не найден скрипт: $script"
    log "=== Стадия: $name ($(basename "$script")) ==="
    if bash -n "$script"; then
        :
    else
        die "Синтаксическая ошибка в $script — исправьте её перед запуском"
    fi
    # Экспортируем переменные, которые ждут внутренние скрипты
    export LFS LFS_TGT="${LFS_TGT:-$(uname -m)-lfs-linux-gnu}"
    if ! bash "$script" 2>&1 | tee -a "$LOG/$name.log"; then
        die "Стадия '$name' завершилась с ошибкой (см. $LOG/$name.log)"
    fi
    local rc=${PIPESTATUS[0]}
    (( rc == 0 )) || die "Стадия '$name' завершилась с кодом $rc (см. $LOG/$name.log)"
    touch "$STAMPS/$name.done"
    log "✓ Стадия '$name' завершена."
}

stage_cross()   { run_stage_script cross   lfs-cross.sh; }
stage_chroot()  { run_stage_script chroot  lfs-chroot.sh; }
stage_system()  { run_stage_script system  lfs-system.sh; }
stage_final()   { run_stage_script final   lfs-final.sh; }

#------------------------------------------------------------------------------
# Стадия live: initrd + squashfs из /mnt/lfs + гибридный ISO
#------------------------------------------------------------------------------
KERNEL_VER="6.18.10"
VMLINUZ_NAME="vmlinuz-${KERNEL_VER}-lfs-13.0-systemd"
INITRD_NAME="initrd.img-${KERNEL_VER}"

stage_live() {
    require_root
    log "=== Стадия: live ==="
    local iso_root="$BUILD_DIR/build/iso" out_iso="$BUILD_DIR/build/kwasos-${VERSION:-1.0}.iso"
    local lfs_boot="$LFS/boot"

    [[ -f "$lfs_boot/$VMLINUZ_NAME" ]] || die "Нет ядра $lfs_boot/$VMLINUZ_NAME. Выполните: sudo make final"

    # 1. initrd
    bash "$BUILD_DIR/scripts/build-initrd.sh" || die "Не удалось собрать initrd (нужен busybox-static)"

    # 2. squashfs из корневой ФС LFS
    log "Упаковка корневой ФС в squashfs..."
    rm -rf "$iso_root"
    mkdir -p "$iso_root/boot"
    mksquashfs "$LFS" "$iso_root/filesystem.squashfs" \
        -e boot .stamps sources proc sys dev run tmp \
        -comp xz -noappend || die "mksquashfs завершился с ошибкой"

    # 3. загрузочные файлы
    cp "$lfs_boot/$VMLINUZ_NAME"  "$iso_root/boot/"
    cp "$lfs_boot/$INITRD_NAME"   "$iso_root/boot/"
    mkdir -p "$iso_root/boot/grub"
    cp "$BUILD_DIR/configs/grub.cfg" "$iso_root/boot/grub/grub.cfg"

    # 4. гибридный ISO (BIOS + UEFI)
    log "Сборка ISO: $out_iso"
    mkdir -p "$BUILD_DIR/build"
    local grub_efi_img="$BUILD_DIR/build/boot.img-efi-fat-no-part.bin"
    if command -v grub-mkimage >/dev/null 2>&1; then
        ( cd "$iso_root" && \
          grub-mkstandalone -O x86_64-efi -d /usr/lib/grub/x86_64-efi \
              -o "$grub_efi_img" "boot/grub/grub.cfg=$BUILD_DIR/configs/grub.cfg" ) \
            || warn "grub-mkstandalone (UEFI) не удался — BIOS-загрузка всё равно будет работать"
    fi
    xorriso -as mkisofs -o "$out_iso" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin 2>/dev/null \
        -V "KWASOS_1_0" \
        -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
        --efi-boot "$grub_efi_img" -no-emul-boot \
        -isohybrid-gpt-basdat \
        -r -J "$iso_root" >>"$LOG/download.log" 2>&1 \
        || die "xorriso не смог собрать ISO (проверьте установку xorriso/grub-pc-bin/grub-efi-amd64-bin)"

    sha256sum "$out_iso" > "$out_iso.sha256"
    log "✓ Готово: $out_iso ($(du -h "$out_iso" | cut -f1))"
}

usage() {
    cat << 'EOF'
KwasOS builder — оркестратор сборки LFS 13.0 → Live ISO

Использование: sudo make <цель>   (или bash scripts/build.sh <стадия>)

Стадии:
  prepare   Скачать пакеты LFS и распаковать в $LFS/sources
  cross     Кросс-тулчейн и временные инструменты (главы 5–6)
  chroot    Дополнительные временные инструменты (глава 7, внутри chroot)
  system    Базовая система (глава 8, внутри chroot)
  final     Ядро + финальная настройка (главы 9–11)
  live      initrd + squashfs + гибридный ISO (build/kwasos-<VERSION>.iso)
  all       Все стадии по порядку

Переменные окружения:
  LFS=/mnt/lfs   VERSION=1.0
EOF
}

main() {
    local stage="${1:-help}"
    case "$stage" in
        help|-h|--help) usage ;;
        prepare)     stage_prepare ;;
        cross)       stage_cross ;;
        chroot)      stage_chroot ;;
        system)      stage_system ;;
        final)       stage_final ;;
        live)        stage_live ;;
        # обратная совместимость со старыми именами стадий
        build)       stage_cross && stage_chroot ;;
        configure)   stage_system ;;
        package)     stage_final ;;
        iso)         stage_live ;;
        all)         stage_prepare && stage_cross && stage_chroot && stage_system && stage_final && stage_live ;;
        *)           usage; die "Неизвестная стадия: $stage (prepare|cross|chroot|system|final|live|all)" ;;
    esac
}

main "$@"
