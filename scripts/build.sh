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
#  * Прогресс загрузки печатается в консоль и дублируется в logs/download.log.
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

CHUNK_SIZE=$((32 * 1024 * 1024))   # 32 МБ на чанк

# Загрузка одного диапазона байтов [from..to] с повторными попытками.
# curl: Range + дописывание в файл (-C - при существовании части).
fetch_range() {
    local url="$1" file="$2" from="$3" to="$4" attempt rc have
    for attempt in 1 2 3 4 5; do
        # если файл уже содержит нужный диапазон — пропускаем
        if [[ -f "$file" ]] && (( $(stat -c%s "$file") > to )); then
            echo "чанк ${from}-${to} уже загружен, пропуск"
            return 0
        fi
        if command -v curl >/dev/null 2>&1; then
            # -r скачивает диапазон; >> без --output-dir не подходит,
            # поэтому curl пишет во временный файл, затем дописываем.
            local tmp="$file.rangefetch"
            rm -f "$tmp"
            curl -fL --retry 3 --retry-delay 1 --retry-connrefused \
                 --connect-timeout 20 \
                 --speed-limit 1024 --speed-time 90 \
                 -r "${from}-${to}" -o "$tmp" "$url" 2>&1
            rc=$?
            if (( rc == 0 )) && [[ -s "$tmp" ]]; then
                cat "$tmp" >> "$file"
            fi
            rm -f "$tmp"
        else
            # Без curl: одна полная попытка wget -c (докачка с места
            # остановки), прогресс — в stdout.
            ( cd "$(dirname "$file")" && \
              wget -c --progress=dot:mega --tries=5 --timeout=60 \
                   --waitretry=15 "$(basename "$url")" ) 2>&1
            return 0
        fi
        have=$(stat -c%s "$file" 2>/dev/null || echo 0)
        if (( have > to )); then return 0; fi
        if (( rc != 0 )); then
            echo "curl вернул код $rc (попытка $attempt/5)"
            sleep $((attempt * 3))
        fi
    done
    return 1
}

# Загрузка файла чанками по CHUNK_SIZE с докачкой с точного байта.
# Прогресс печатается в stdout (оттуда идёт и в консоль, и в download.log).
fetch_chunked() {
    local url="$1" file="$2" have total target rc=0
    while true; do
        have=$(stat -c%s "$file" 2>/dev/null || echo 0)
        if (( have >= TARBALL_SIZE )); then break; fi
        target=$(( have + CHUNK_SIZE - 1 ))
        (( target >= TARBALL_SIZE )) && target=$(( TARBALL_SIZE - 1 ))
        printf '[%(%H:%M:%S)T] Чанк %s-%s из %s (%d%%)\n' -1 \
               "$have" "$target" "$TARBALL_SIZE" \
               $(( have * 100 / TARBALL_SIZE ))
        if ! fetch_range "$url" "$file" "$have" "$target"; then
            rc=1; break
        fi
    done
    have=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if (( rc == 0 && have >= TARBALL_SIZE )); then
        printf '[%(%H:%M:%S)T] ✓ Загрузка завершена: %s/%s байт (100%%)\n' \
               -1 "$have" "$TARBALL_SIZE"
    else
        printf '[%(%H:%M:%S)T] ⏳ Остановлено на %s/%s байт (%d%%)\n' -1 \
               "$have" "$TARBALL_SIZE" $(( have * 100 / TARBALL_SIZE ))
    fi
    return $rc
}

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
    local url urlhash partdir part got rc
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
        log "Прогресс в реальном времени: tail -f $LOG/download.log"

        # ВАЖНО: НЕ используем wget -O — с ним --continue молча качает с нуля.
        # Загрузка чанками по 32 МБ (curl Range / wget -c): при обрыве связи
        # или Ctrl+C часть остаётся на диске, повторный запуск продолжает
        # с того же байта. Прогресс — и в консоли, и в logs/download.log.
        fetch_chunked "$url" "$part" | tee -a "$LOG/download.log"

        # Если от предыдущих версий скрипта остался .part — объединяем один раз.
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
# Последующие стадии (заглушки для этого репозитория)
#------------------------------------------------------------------------------
stage_build()      { log "=== Стадия: build ===";      log "TODO: сборка LFS/chroot"; }
stage_configure()  { log "=== Стадия: configure ===";  log "TODO: настройка системы"; }
stage_package()    { log "=== Стадия: package ===";    log "TODO: упаковка"; }
stage_iso()        { log "=== Стадия: iso ===";        log "TODO: создание ISO"; }

main() {
    local stage="${1:-prepare}"
    case "$stage" in
        prepare)     stage_prepare ;;
        build)       stage_build ;;
        configure)   stage_configure ;;
        package)     stage_package ;;
        iso)         stage_iso ;;
        all)         stage_prepare && stage_build && stage_configure && stage_package && stage_iso ;;
        *)           die "Неизвестная стадия: $stage (prepare|build|configure|package|iso|all)" ;;
    esac
}

main "$@"
