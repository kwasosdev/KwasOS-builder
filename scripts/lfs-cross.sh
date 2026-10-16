#!/bin/bash
# LFS 13.0 Build Script (systemd edition)
# Builds the cross-toolchain and cross compiling temporary tools from chapters 5 and 6
# by Luís Mendes :)
# Updated for LFS 13.0
#
# Автономный вариант: сам скачивает и распаковывает пакеты LFS,
# проверяет зависимости хоста и не требует предварительного `make prepare`.
#
# Запуск: sudo ./scripts/lfs-cross.sh

set -e

# --- Самонастройка окружения ---
export LFS="${LFS:-/mnt/lfs}"
export LFS_TGT="${LFS_TGT:-$(uname -m)-lfs-linux-gnu}"
export SRC_DIR="${SRC_DIR:-$LFS/sources}"
export PATH="$LFS/tools/bin:$PATH"

# --- Параметры загрузки пакетов ---
LFS_VERSION="13.0"
TARBALL_SIZE=633282560
LFS_TARBALL="lfs-packages-${LFS_VERSION}.tar"
LFS_TARBALL_URLS=(
    "http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_TARBALL}"
    "https://anduin.linuxfromscratch.org/LFS/${LFS_TARBALL}"
    "http://mirrors.lfs-matrix.net/pub/lfs/lfs-packages/${LFS_TARBALL}"
)
MD5SUMS_URLS=(
    "http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_VERSION}/md5sums"
    "https://anduin.linuxfromscratch.org/LFS/${LFS_VERSION}-packages.md5"
)

# --- Каталоги ---
LOG_DIR="${LOG_DIR:-$(cd "$(dirname "$0")/.." && pwd)/logs}"
mkdir -p "$LOG_DIR"
DOWNLOAD_LOG="$LOG_DIR/download.log"

package_name=""
package_ext=""

# --- Служебные функции ---
log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }
warn() { printf '[%(%H:%M:%S)T] ПРЕДУПРЕЖДЕНИЕ: %s\n' -1 "$*" >&2; }
die() { printf '[%(%H:%M:%S)T] ОШИБКА: %s\n' -1 "$*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Запускайте через sudo."
}

check_host_deps() {
    local missing=()
        for cmd in wget tar make gcc g++ patch sed awk bison flex makeinfo python3 xz; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Не найдены утилиты: ${missing[*]}. Установите их перед запуском."
    fi
}

init_dirs() {
    mkdir -p "$LFS" "$SRC_DIR" "$LOG_DIR" "$LFS/tools" "$LFS/tools/bin"
    mkdir -pv "$LFS"/{etc,var}
    mkdir -pv "$LFS"/usr/{bin,lib,sbin,share/man}
    for i in bin lib sbin; do
        [ -L "$LFS/$i" ] || ln -sv usr/"$i" "$LFS/$i"
    done
    case $(uname -m) in
        x86_64) [ -d "$LFS/lib64" ] || mkdir -pv "$LFS/lib64" ;;
    esac
}

# --- Загрузка и распаковка пакетов LFS (аналог stage_prepare из build.sh) ---
download_with_wget() {
    local url="$1" part="$2" pid wpid have last=0
    ( cd "$(dirname "$part")" && \
      wget -c --progress=dot:mega --tries=0 --timeout=60 --waitretry=15 \
           "$url" ) >>"$DOWNLOAD_LOG" 2>&1 &
    pid=$!
    ( while kill -0 "$pid" 2>/dev/null; do
        have=$(stat -c%s "$part" 2>/dev/null || echo 0)
        if (( have != last )); then
            printf '[%(%H:%M:%S)T] Загрузка: %s/%s байт (%d%%)\n' -1 \
                "$have" "$TARBALL_SIZE" $(( have * 100 / TARBALL_SIZE ))
            last=$have
        fi
        sleep 5
      done ) &
    wpid=$!
    wait "$pid"; local rc=$?
    kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
    have=$(stat -c%s "$part" 2>/dev/null || echo 0)
    if (( have >= TARBALL_SIZE )); then
        printf '[%(%H:%M:%S)T] ✓ Загрузка завершена: %s/%s байт (100%%)\n' -1 \
            "$have" "$TARBALL_SIZE"
        return 0
    fi
    printf '[%(%H:%M:%S)T] ⏳ Остановлено на %s/%s байт (%d%%), wget rc=%s\n' -1 \
        "$have" "$TARBALL_SIZE" $(( have * 100 / TARBALL_SIZE )) "$rc"
    return 1
}

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

download_tarball() {
    local url urlhash partdir part got rc
    for url in "${LFS_TARBALL_URLS[@]}"; do
        log "Зеркало: $url"
        urlhash=$(printf '%s' "$url" | md5sum | cut -c1-8)
        partdir="$LFS/.dl-$urlhash"
        part="$partdir/$LFS_TARBALL"
        mkdir -p "$partdir"
        got=$(stat -c%s "$part" 2>/dev/null || echo 0)
        if (( got >= TARBALL_SIZE )); then
            log "Файл уже загружен полностью ($got/$TARBALL_SIZE байт), проверяю целостность..."
        elif (( got > 0 )); then
            log "Продолжаю загрузку: $got/$TARBALL_SIZE байт уже есть."
            log "Прогресс в реальном времени: tail -f $DOWNLOAD_LOG"
            download_with_wget "$url" "$part" | tee -a "$DOWNLOAD_LOG"
            rc=$?
        else
            log "Начинаю загрузку 0/$TARBALL_SIZE байт..."
            log "Прогресс в реальном времени: tail -f $DOWNLOAD_LOG"
            download_with_wget "$url" "$part" | tee -a "$DOWNLOAD_LOG"
            rc=$?
        fi
        if [[ -f "$part" && -f "$part.part" ]]; then
            cat "$part.part" >> "$part" && rm -f "$part.part"
        fi
        if check_tarball "$part"; then
            mv -f "$part" "$SRC_DIR/$LFS_TARBALL"
            rm -rf "$partdir"
            log "✓ Архив скачан и проверен ($(du -h "$SRC_DIR/$LFS_TARBALL" | cut -f1))"
            return 0
        fi
        got=$(stat -c%s "$part" 2>/dev/null || echo 0)
        if (( got > 0 && got < TARBALL_SIZE )); then
            warn "Загрузка прервана на ${got}/${TARBALL_SIZE} байт (wget rc=${rc:-0})."
            warn "Повторите запуск — продолжит с этого места."
            return 1
        fi
        warn "Файл с $url непригоден, пробую следующее зеркало..."
        rm -f "$part" "$part".part
    done
    return 1
}

fetch_per_package() {
    local md5file base name sum u ok=0 fail=0
    md5file="$SRC_DIR/md5sums"
    if [[ ! -s "$md5file" ]]; then
        for u in "${MD5SUMS_URLS[@]}"; do
            if wget -c -nv -O "$md5file.tmp" "$u" >>"$DOWNLOAD_LOG" 2>&1; then
                mv -f "$md5file.tmp" "$md5file"; break
            fi
            rm -f "$md5file.tmp"
        done
    fi
    [[ -s "$md5file" ]] || { warn "Не получен список md5sums"; return 1; }
    base="http://ftp.osuosl.org/pub/lfs/lfs-packages/${LFS_VERSION}"
    while read -r sum name _; do
        [[ -z "${name:-}" ]] && continue
        if [[ -f "$SRC_DIR/$name" ]] && echo "$sum $SRC_DIR/$name" | md5sum -c --status - 2>/dev/null; then
            ok=$((ok+1)); continue
        fi
        if wget -c -nv -O "$SRC_DIR/$name" "$base/$name" >>"$DOWNLOAD_LOG" 2>&1 \
           && echo "$sum $SRC_DIR/$name" | md5sum -c --status - 2>/dev/null; then
            ok=$((ok+1))
        else
            warn "Пакет $name не удалось получить/проверить"
            fail=$((fail+1))
        fi
    done < "$md5file"
    log "Поштучно: ок=$ok, ошибок=$fail"
    (( fail == 0 ))
}

prepare_packages() {
    if [[ -f "$SRC_DIR/.unpack-done" ]]; then
        log "Пакеты уже распакованы ($SRC_DIR/.unpack-done) — пропускаю."
        return 0
    fi
    local nfiles
    nfiles=$(find "$SRC_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if (( nfiles >= 80 )); then
        touch "$SRC_DIR/.unpack-done"
        log "В $SRC_DIR уже $nfiles файлов — считаю распакованным, пропускаю."
        return 0
    fi
    if ! check_tarball "$SRC_DIR/$LFS_TARBALL"; then
        rm -f "$SRC_DIR/$LFS_TARBALL"
        log "Скачивание пакетов LFS $LFS_VERSION (~633 МБ)..."
        if ! download_tarball; then
            warn "Переключаюсь на поштучную загрузку пакетов..."
            fetch_per_package || die "Не удалось получить пакеты LFS."
            touch "$SRC_DIR/.unpack-done"
            log "✓ Пакеты готовы (поштучный режим)."
            return 0
        fi
    else
        log "✓ Архив уже скачан и цел ($SRC_DIR/$LFS_TARBALL), пропущено."
    fi
    log "Распаковка пакетов (~633 МБ, обычно 1–3 минуты, зависит от диска)..."
    local tmpd root real
    tmpd="$LFS/.unpack-tmp"
    rm -rf "$tmpd"; mkdir -p "$tmpd"
    if ! tar xf "$SRC_DIR/$LFS_TARBALL" -C "$tmpd"; then
        rm -rf "$tmpd"
        die "Распаковка $SRC_DIR/$LFS_TARBALL завершилась с ошибкой (нехватка места?)"
    fi
    root="$tmpd/lfs-packages-${LFS_VERSION}"
    if [[ ! -d "$root" ]]; then
        real=$(tar tf "$SRC_DIR/$LFS_TARBALL" 2>/dev/null | head -n1 | cut -d/ -f1)
        if [[ -n "$real" && -d "$tmpd/$real" ]]; then
            root="$tmpd/$real"
        else
            root="$tmpd"
        fi
    fi
    [[ -d "$root" ]] || { rm -rf "$tmpd"; die "Не найден корневой каталог распакованного архива"; }
    if [[ "$root" == "$tmpd" ]]; then
        cp -a "$tmpd"/. "$SRC_DIR"/
    else
        cp -a "$root"/. "$SRC_DIR"/
    fi
    rm -rf "$tmpd"
    touch "$SRC_DIR/.unpack-done"
    log "✓ Распаковано в $SRC_DIR ($(find "$SRC_DIR" -maxdepth 1 -type f | wc -l) файлов)."
}

# --- Загрузка патчей LFS ---
fetch_patches() {
    local patch_dir="${PATCH_DIR:-$SRC_DIR}"
    mkdir -p "$patch_dir"
    # Массив «url|имя_файла»
    local patches=(
        "http://lfs.linux-sysadmin.com/patches/downloads/glibc/glibc-fhs-1.patch|glibc-fhs-1.patch"
        "http://lfs.linux-sysadmin.com/patches/downloads/glibc/glibc-2.43-upstream_fixes-1.patch|glibc-2.43-upstream_fixes-1.patch"
    )
    local entry url name dest
    for entry in "${patches[@]}"; do
        url="${entry%%|*}"
        name="${entry##*|}"
        dest="$patch_dir/$name"
        if [[ -s "$dest" ]] && head -1 "$dest" | grep -qE '^(diff|---|\+\+\+)'; then
            log "✓ Патч уже есть: $name"
            continue
        fi
        log "Скачиваю патч: $name"
        if ! wget -c -nv -O "$dest.tmp" "$url" >>"$DOWNLOAD_LOG" 2>&1; then
            warn "Не удалось скачать $name с $url"
            rm -f "$dest.tmp"
            # Попробуем зеркало
            local alt="https://www.linuxfromscratch.org/patches/downloads/glibc/$name"
            log "Пробую зеркало: $alt"
            if wget -c -nv -O "$dest.tmp" "$alt" >>"$DOWNLOAD_LOG" 2>&1; then
                mv -f "$dest.tmp" "$dest"
            else
                rm -f "$dest.tmp"
                die "Патч $name не удалось скачать ни с одного зеркала"
            fi
        else
            mv -f "$dest.tmp" "$dest"
        fi
        if ! head -1 "$dest" | grep -qE '^(diff|---|\+\+\+)'; then
            warn "Файл $dest не похож на патч (первые байты: $(head -c 40 "$dest" | tr -d '\n'))"
        else
            log "✓ Патч скачан: $name ($(du -h "$dest" | cut -f1))"
        fi
    done
}

# --- Функции сборки (begin / finish) ---
begin() {
    package_name=$1
    package_ext=$2
    echo "[lfs-cross] Starting build of $package_name at $(date)"
    tar xf "$SRC_DIR/$package_name.$package_ext" || return 1
    cd "$package_name" || return 1
}

finish() {
    echo "[lfs-cross] Finishing build of $package_name at $(date)"
    cd "$SRC_DIR"
    rm -rf "$package_name"
}

# --- Основной блок ---
require_root
check_host_deps
init_dirs
prepare_packages
fetch_patches
cd "$SRC_DIR"

# 5.2. Binutils-2.46.0 - Pass 1
begin binutils-2.46.0 tar.xz
mkdir -p build
cd       build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
make
make install
finish

# 5.3. GCC-15.2.0 - Pass 1
begin gcc-15.2.0 tar.xz
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -p build
cd       build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.43 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ..

# Генерация limits.h с проверками
if ! command -v "$LFS_TGT-gcc" >/dev/null 2>&1; then
    echo "[lfs-cross] ERROR: $LFS_TGT-gcc не найден в PATH. Похоже, GCC Pass 1 не установлен." >&2
    exit 1
fi
libgcc_file="$("$LFS_TGT-gcc" -print-libgcc-file-name 2>/dev/null || true)"
if [ -z "$libgcc_file" ] || [ ! -f "$libgcc_file" ]; then
    echo "[lfs-cross] ERROR: не найден libgcc.a для $LFS_TGT (получено: '$libgcc_file')" >&2
    exit 1
fi
libgcc_include_dir="$(dirname "$libgcc_file")/include"
mkdir -p "$libgcc_include_dir"
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > "$libgcc_include_dir/limits.h"
finish

# 5.4. Linux-6.18.10 API Headers
begin linux-6.18.10 tar.xz
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
mkdir -p "$LFS/usr"
cp -rv usr/include "$LFS/usr"
finish

# 5.5. Glibc-2.43
begin glibc-2.43 tar.xz
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) mkdir -pv "$LFS/lib64"
        ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
        ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
    ;;
esac
patch -Np1 -i ../glibc-fhs-1.patch
patch -Np1 -i ../glibc-2.43-upstream_fixes-1.patch
mkdir -p build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib           \
      --enable-kernel=5.4
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
rm -v a.out dummy.log
finish

# 5.6. Libstdc++ from GCC-15.2.0
begin gcc-15.2.0 tar.xz
mkdir -p build
cd       build
../libstdc++-v3/configure      \
    --host=$LFS_TGT            \
    --build=$(../config.guess) \
    --prefix=/usr              \
    --disable-multilib         \
    --disable-nls              \
    --disable-libstdcxx-pch    \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
finish

# 6.2. M4-1.4.21
begin m4-1.4.21 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.3. Ncurses-6.6
begin ncurses-6.6 tar.gz
mkdir -p build
pushd build
  ../configure --prefix=$LFS/tools AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic $LFS/tools/bin
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            AWK=gawk
make
make DESTDIR=$LFS install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
finish

# 6.4. Bash-5.3
begin bash-5.3 tar.gz
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
finish

# 6.5. Coreutils-9.10
begin coreutils-9.10 tar.xz
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
finish

# 6.6. Diffutils-3.12
begin diffutils-3.12 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            gl_cv_func_strcasecmp_works=y \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.7. File-5.46
begin file-5.46 tar.gz
mkdir -p build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
finish

# 6.8. Findutils-4.10.0
begin findutils-4.10.0 tar.xz
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.9. Gawk-5.3.2
begin gawk-5.3.2 tar.xz
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.10. Grep-3.12
begin grep-3.12 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.11. Gzip-1.14
begin gzip-1.14 tar.xz
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
finish

# 6.12. Make-4.4.1
begin make-4.4.1 tar.gz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.13. Patch-2.8
begin patch-2.8 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.14. Sed-4.9
begin sed-4.9 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.15. Tar-1.35
begin tar-1.35 tar.xz
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
finish

# 6.16. Xz-5.8.2
begin xz-5.8.2 tar.xz
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.8.2
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
finish

# 6.17. Binutils-2.46.0 - Pass 2
begin binutils-2.46.0 tar.xz
sed '6031s/$add_dir//' -i ltmain.sh
mkdir -p build
cd       build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
finish

# 6.18. GCC-15.2.0 - Pass 2
begin gcc-15.2.0 tar.xz
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir -p build
cd       build
../configure                   \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --target=$LFS_TGT          \
    --prefix=/usr              \
    --with-build-sysroot=$LFS  \
    --enable-default-pie       \
    --enable-default-ssp       \
    --disable-nls              \
    --disable-multilib         \
    --disable-libatomic        \
    --disable-libgomp          \
    --disable-libquadmath      \
    --disable-libsanitizer     \
    --disable-libssp           \
    --disable-libvtv           \
    --enable-languages=c,c++   \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
finish
