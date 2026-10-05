#!/bin/bash
# LFS 13.0 Build Script (systemd edition)
# Builds the basic system software from chapter 8
# by Luís Mendes :)
# Updated for LFS 13.0

package_name=""
package_ext=""

begin() {
	package_name=$1
	package_ext=$2

	echo "[lfs-system] Starting build of $package_name at $(date)"

	tar xf $package_name.$package_ext
	cd $package_name
}

finish() {
	echo "[lfs-system] Finishing build of $package_name at $(date)"

	cd /sources
	rm -rf $package_name
}

cd /sources

# 8.3. Man-pages-6.17
begin man-pages-6.17 tar.xz
rm -v man3/crypt*
make -R GIT=false prefix=/usr install
finish

# 8.4. Iana-Etc-20260202
begin iana-etc-20260202 tar.gz
cp -v services protocols /etc
finish

# 8.5. Glibc-2.43
begin glibc-2.43 tar.xz
patch -Np1 -i ../glibc-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4
make
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
make install
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
localedef -i C -f UTF-8 C.UTF-8
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8
cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF
tar -xf ../../tzdata2025c.tar.gz

ZONEINFO=/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica  \
          asia australasia backward; do
    zic -L /dev/null   -d $ZONEINFO       ${tz}
    zic -L /dev/null   -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p America/New_York
unset ZONEINFO tz
ln -sfv /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF
cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
mkdir -pv /etc/ld.so.conf.d
finish

# 8.6. Zlib-1.3.2
begin zlib-1.3.2 tar.gz
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libz.a
finish

# 8.7. Bzip2-1.0.8
begin bzip2-1.0.8 tar.gz
patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do
  ln -sfv bzip2 $i
done
rm -fv /usr/lib/libbz2.a
finish

# 8.8. Xz-5.8.2
begin xz-5.8.2 tar.xz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.8.2
make
make install
finish

# 8.9. Lz4-1.10.0
begin lz4-1.10.0 tar.gz
make BUILD_STATIC=no PREFIX=/usr
make BUILD_STATIC=no PREFIX=/usr install
finish

# 8.10. Zstd-1.5.7
begin zstd-1.5.7 tar.gz
make prefix=/usr
make prefix=/usr install
rm -v /usr/lib/libzstd.a
finish

# 8.11. File-5.46
begin file-5.46 tar.gz
./configure --prefix=/usr
make
make install
finish

# 8.12. Readline-8.3
begin readline-8.3 tar.gz
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
sed -e '270a\
     else\
       chars_avail = 1;'      \
    -e '288i\   result = -1;' \
    -i.orig input.c
./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline-8.3
make SHLIB_LIBS="-lncursesw"
make install
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3
finish

# 8.13. Pcre2-10.47
begin pcre2-10.47 tar.bz2
./configure --prefix=/usr                       \
            --docdir=/usr/share/doc/pcre2-10.47 \
            --enable-unicode                    \
            --enable-jit                        \
            --enable-pcre2-16                   \
            --enable-pcre2-32                   \
            --enable-pcre2grep-libz             \
            --enable-pcre2grep-libbz2           \
            --enable-pcre2test-libreadline      \
            --disable-static
make
make install
finish

# 8.14. M4-1.4.21
begin m4-1.4.21 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.15. Bc-7.0.3
begin bc-7.0.3 tar.xz
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
make
make install
finish

# 8.16. Flex-2.6.4
begin flex-2.6.4 tar.gz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/flex-2.6.4
make
make install
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
finish

# 8.17. Tcl-8.6.17
mv -v tcl8.6.17-src.tar.gz tcl8.6.17.tar.gz
begin tcl8.6.17 tar.gz
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --disable-rpath
make

sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|"     \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|"  \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|"             \
    -i pkgs/tdbc1.1.12/tdbcConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|"            \
    -i pkgs/itcl4.3.4/itclConfig.sh

unset SRCDIR
make install
chmod 644 /usr/lib/libtclstub8.6.a
chmod -v u+w /usr/lib/libtcl8.6.so
make install-private-headers
ln -sfv tclsh8.6 /usr/bin/tclsh
mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
cd ..
tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1
mkdir -v -p /usr/share/doc/tcl-8.6.17
cp -v -r  ./html/* /usr/share/doc/tcl-8.6.17
finish

# 8.18. Expect-5.45.4
begin expect5.45.4 tar.gz
patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include
make
make install
ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
finish

# 8.19. DejaGNU-1.6.3
begin dejagnu-1.6.3 tar.gz
mkdir -v build
cd       build
../configure --prefix=/usr
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
make install
install -v -dm755  /usr/share/doc/dejagnu-1.6.3
install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
finish

# 8.20. Pkgconf-2.5.1
begin pkgconf-2.5.1 tar.xz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/pkgconf-2.5.1
make
make install
ln -sv pkgconf   /usr/bin/pkg-config
ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
finish

# 8.21. Binutils-2.46.0
begin binutils-2.46.0 tar.xz
mkdir -v build
cd       build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
make tooldir=/usr
make tooldir=/usr install
rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
        /usr/share/doc/gprofng/
finish

# 8.22. GMP-6.3.0
begin gmp-6.3.0 tar.xz
sed -i '/long long t1;/,+1s/()/(...)/' configure
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0
make
make html
make install
make install-html
finish

# 8.23. MPFR-4.2.2
begin mpfr-4.2.2 tar.xz
./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-4.2.2
make
make html
make install
make install-html
finish

# 8.24. MPC-1.3.1
begin mpc-1.3.1 tar.gz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-1.3.1
make
make html
make install
make install-html
finish

# 8.25. Attr-2.5.2
begin attr-2.5.2 tar.gz
./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-2.5.2
make
make install
finish

# 8.26. Acl-2.3.2
begin acl-2.3.2 tar.xz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/acl-2.3.2
make
make install
finish

# 8.27. Libcap-2.77
begin libcap-2.77 tar.xz
sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib
make prefix=/usr lib=lib install
finish

# 8.28. Libxcrypt-4.5.2
begin libxcrypt-4.5.2 tar.xz
sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens
make
make install
finish

# 8.29. Shadow-4.19.3
begin shadow-4.19.3 tar.xz
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --disable-logind    \
            --with-group-name-max-length=32
make
make exec_prefix=/usr install
make -C man install-man
pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd
echo "root:root" | chpasswd
finish

# 8.30. GCC-15.2.0
begin gcc-15.2.0 tar.xz
sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
mkdir -v build
cd       build
../configure --prefix=/usr            \
             LD=ld                    \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib
make
make install
chown -v -R root:root \
    /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}
ln -svr /usr/bin/cpp /usr/lib
ln -sv gcc.1 /usr/share/man/man1/cc.1
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so \
        /usr/lib/bfd-plugins/
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
finish

# 8.31. Ncurses-6.6
begin ncurses-6.6 tar.gz
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make
make DESTDIR=$PWD/dest install
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i dest/usr/include/curses.h
cp --remove-destination -av dest/* /
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cp -v -R doc -T /usr/share/doc/ncurses-6.6
finish

# 8.32. Sed-4.9
begin sed-4.9 tar.xz
./configure --prefix=/usr
make
make html
make install
install -d -m755           /usr/share/doc/sed-4.9
install -m644 doc/sed.html /usr/share/doc/sed-4.9
finish

# 8.33. Psmisc-23.7
begin psmisc-23.7 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.34. Gettext-1.0
begin gettext-1.0 tar.xz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-1.0
make
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
finish

# 8.35. Bison-3.8.2
begin bison-3.8.2 tar.xz
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make
make install
finish

# 8.36. Grep-3.12
begin grep-3.12 tar.xz
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make
make install
finish

# 8.37. Bash-5.3
begin bash-5.3 tar.gz
./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            --docdir=/usr/share/doc/bash-5.3
make
make install
finish

# 8.38. Libtool-2.5.4
begin libtool-2.5.4 tar.xz
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libltdl.a
finish

# 8.39. GDBM-1.26
begin gdbm-1.26 tar.gz
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make
make install
finish

# 8.40. Gperf-3.3
begin gperf-3.3 tar.gz
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
make
make install
finish

# 8.41. Expat-2.7.4
begin expat-2.7.4 tar.xz
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.7.4
make
make install
install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.7.4
finish

# 8.42. Inetutils-2.7
begin inetutils-2.7 tar.gz
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
make
make install
mv -v /usr/{,s}bin/ifconfig
finish

# 8.43. Less-692
begin less-692 tar.gz
./configure --prefix=/usr --sysconfdir=/etc
make
make install
finish

# 8.44. Perl-5.42.0
begin perl-5.42.0 tar.xz
export BUILD_ZLIB=False
export BUILD_BZIP2=0
sh Configure -des                                          \
             -D prefix=/usr                                \
             -D vendorprefix=/usr                          \
             -D privlib=/usr/lib/perl5/5.42/core_perl      \
             -D archlib=/usr/lib/perl5/5.42/core_perl      \
             -D sitelib=/usr/lib/perl5/5.42/site_perl      \
             -D sitearch=/usr/lib/perl5/5.42/site_perl     \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl  \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl \
             -D man1dir=/usr/share/man/man1                \
             -D man3dir=/usr/share/man/man3                \
             -D pager="/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads
make
make install
unset BUILD_ZLIB BUILD_BZIP2
finish

# 8.45. XML::Parser-2.47
begin XML-Parser-2.47 tar.gz
perl Makefile.PL
make
make install
finish

# 8.46. Intltool-0.51.0
begin intltool-0.51.0 tar.gz
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
make
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
finish

# 8.47. Autoconf-2.72
begin autoconf-2.72 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.48. Automake-1.18.1
begin automake-1.18.1 tar.xz
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
make
make install
finish

# 8.49. OpenSSL-3.6.1
begin openssl-3.6.1 tar.gz
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.6.1
cp -vfr doc/* /usr/share/doc/openssl-3.6.1
finish

# 8.50. Libelf from Elfutils-0.194
begin elfutils-0.194 tar.bz2
./configure --prefix=/usr        \
            --disable-debuginfod \
            --enable-libdebuginfod=dummy
make -C lib
make -C libelf
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
finish

# 8.51. Libffi-3.5.2
begin libffi-3.5.2 tar.gz
./configure --prefix=/usr    \
            --disable-static \
            --with-gcc-arch=native
make
make install
finish

# 8.52. Sqlite-3510200
begin sqlite-autoconf-3510200 tar.gz
tar -xf ../sqlite-doc-3510200.tar.xz
./configure --prefix=/usr     \
            --disable-static  \
            --enable-fts{4,5} \
            CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                      -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                      -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                      -D SQLITE_SECURE_DELETE=1"
make LDFLAGS.rpath=""
make install
install -v -m755 -d /usr/share/doc/sqlite-3.51.2
cp -v -R sqlite-doc-3510200/* /usr/share/doc/sqlite-3.51.2
finish

# 8.53. Python-3.14.3
begin Python-3.14.3 tar.xz
./configure --prefix=/usr          \
            --enable-shared        \
            --with-system-expat    \
            --enable-optimizations \
            --without-static-libpython
# Book command is plain "make". With --enable-optimizations, Python 3.14 runs a
# PGO profiling pass. On some hosts, test_generators.SignalAndYieldFromTest.
# test_raise_and_yield_from fails *only* under the -fprofile-generate build
# (it passes normally), a known upstream CPython 3.14 PGO bug, and aborts make.
# We exclude just that one test module from the profiling task. No compiler
# flags change; the resulting optimized python is functionally identical.
make PROFILE_TASK="-m test --pgo -x test_generators"
make install
cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
install -v -dm755 /usr/share/doc/python-3.14.3/html

tar --strip-components=1  \
    --no-same-owner       \
    --no-same-permissions \
    -C /usr/share/doc/python-3.14.3/html \
    -xvf ../python-3.14.3-docs-html.tar.bz2
finish

# 8.54. Flit-Core-3.12.0
begin flit_core-3.12.0 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist flit_core
finish

# 8.55. Packaging-26.0
begin packaging-26.0 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist packaging
finish

# 8.56. Wheel-0.46.3
begin wheel-0.46.3 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist wheel
finish

# 8.57. Setuptools-82.0.0
begin setuptools-82.0.0 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist setuptools
finish

# 8.58. Ninja-1.13.2
begin ninja-1.13.2 tar.gz
sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
python3 configure.py --bootstrap --verbose
install -vm755 ninja /usr/bin/
install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
finish

# 8.59. Meson-1.10.1
begin meson-1.10.1 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist meson
install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
finish

# 8.60. Kmod-34.2
begin kmod-34.2 tar.xz
mkdir -p build
cd       build
meson setup --prefix=/usr ..    \
            --buildtype=release \
            -D manpages=false
ninja
ninja install
finish

# 8.61. Coreutils-9.10
begin coreutils-9.10 tar.xz
patch -Np1 -i ../coreutils-9.10-i18n-1.patch
autoreconf -fv
automake -af
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr
make
make install
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
finish

# 8.62. Diffutils-3.12
begin diffutils-3.12 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.63. Gawk-5.3.2
begin gawk-5.3.2 tar.xz
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make
rm -f /usr/bin/gawk-5.3.2
make install
ln -sv gawk.1 /usr/share/man/man1/awk.1
install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.3.2
finish

# 8.64. Findutils-4.10.0
begin findutils-4.10.0 tar.xz
./configure --prefix=/usr --localstatedir=/var/lib/locate
make
make install
finish

# 8.65. Groff-1.23.0
begin groff-1.23.0 tar.gz
PAGE=A4 ./configure --prefix=/usr
make
make install
finish

# 8.66. GRUB-2.14
begin grub-2.14 tar.xz
unset {C,CPP,CXX,LD}FLAGS
sed 's/--image-base/--nonexist-linker-option/' -i configure
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-efiemu  \
            --disable-werror
make
make install
finish

# 8.67. Gzip-1.14
begin gzip-1.14 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.68. IPRoute2-6.18.0
begin iproute2-6.18.0 tar.xz
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin install
install -vDm644 COPYING README* -t /usr/share/doc/iproute2-6.18.0
finish

# 8.69. Kbd-2.9.0
begin kbd-2.9.0 tar.xz
patch -Np1 -i ../kbd-2.9.0-backspace-1.patch
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock
make
make install
cp -R -v docs/doc -T /usr/share/doc/kbd-2.9.0
finish

# 8.70. Libpipeline-1.5.8
begin libpipeline-1.5.8 tar.gz
./configure --prefix=/usr
make
make install
finish

# 8.71. Make-4.4.1
begin make-4.4.1 tar.gz
./configure --prefix=/usr
make
make install
finish

# 8.72. Patch-2.8
begin patch-2.8 tar.xz
./configure --prefix=/usr
make
make install
finish

# 8.73. Tar-1.35
begin tar-1.35 tar.xz
FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=/usr
make
make install
make -C doc install-html docdir=/usr/share/doc/tar-1.35
finish

# 8.74. Texinfo-7.2
begin texinfo-7.2 tar.xz
sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm
./configure --prefix=/usr
make
make install
make TEXMF=/usr/share/texmf install-tex
pushd /usr/share/info
  rm -v dir
  for f in *
    do install-info $f dir 2>/dev/null
  done
popd
finish

# 8.75. Vim-9.2.0078
begin vim-9.2.0078 tar.gz
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make
make install
ln -sv vim /usr/bin/vi
for L in  /usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1
done
ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.0078
cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
finish

# 8.76. MarkupSafe-3.0.3
begin markupsafe-3.0.3 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Markupsafe
finish

# 8.77. Jinja2-3.1.6
begin jinja2-3.1.6 tar.gz
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Jinja2
finish

# 8.78. Systemd-259.1
begin systemd-259.1 tar.gz
sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //'               \
    -i rules.d/50-udev-default.rules.in
mkdir -p build
cd       build
meson setup ..                \
      --prefix=/usr           \
      --buildtype=release     \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D install-tests=false  \
      -D ldconfig=false       \
      -D sysusers=false       \
      -D rpmmacrosdir=no      \
      -D homed=disabled       \
      -D man=disabled         \
      -D mode=release         \
      -D pamconfdir=no        \
      -D dev-kvm-mode=0660    \
      -D nobody-group=nogroup \
      -D sysupdate=disabled   \
      -D ukify=disabled       \
      -D docdir=/usr/share/doc/systemd-259.1
ninja
ninja install
tar -xf ../../systemd-man-pages-259.1.tar.xz \
    --no-same-owner --strip-components=1     \
    -C /usr/share/man
systemd-machine-id-setup
systemctl preset-all
finish

# 8.79. D-Bus-1.16.2
begin dbus-1.16.2 tar.xz
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
ninja
ninja install
ln -sfv /etc/machine-id /var/lib/dbus
finish

# 8.80. Man-DB-2.13.1
begin man-db-2.13.1 tar.xz
./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db-2.13.1 \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap
make
make install
finish

# 8.81. Procps-ng-4.0.6
begin procps-ng-4.0.6 tar.xz
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.6 \
            --disable-static                        \
            --disable-kill                          \
            --enable-watch8bit                      \
            --with-systemd
make
make install
finish

# 8.82. Util-linux-2.41.3
begin util-linux-2.41.3 tar.xz
./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.3
make
make install
finish

# 8.83. E2fsprogs-1.47.3
begin e2fsprogs-1.47.3 tar.gz
mkdir -v build
cd       build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fsck
make
make install
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
sed 's/metadata_csum_seed,//' -i /etc/mke2fs.conf
finish

# 8.85. Stripping
save_usrlib="$(cd /usr/lib; ls ld-linux*[^g])
             libc.so.6
             libthread_db.so.1
             libquadmath.so.0.0.0
             libstdc++.so.6.0.34
             libitm.so.1.0.0
             libatomic.so.1.2.0"

cd /usr/lib

for LIB in $save_usrlib; do
    objcopy --only-keep-debug --compress-debug-sections=zstd $LIB $LIB.dbg
    cp $LIB /tmp/$LIB
    strip --strip-debug /tmp/$LIB
    objcopy --add-gnu-debuglink=$LIB.dbg /tmp/$LIB
    install -vm755 /tmp/$LIB /usr/lib
    rm /tmp/$LIB
done

online_usrbin="bash find strip"
online_usrlib="libbfd-2.46.0.20260210.so
               libsframe.so.3.0.0
               libhistory.so.8.3
               libncursesw.so.6.6
               libm.so.6
               libreadline.so.8.3
               libz.so.1.3.2
               libzstd.so.1.5.7
               $(cd /usr/lib; find libnss*.so* -type f)"

for BIN in $online_usrbin; do
    cp /usr/bin/$BIN /tmp/$BIN
    strip --strip-debug /tmp/$BIN
    install -vm755 /tmp/$BIN /usr/bin
    rm /tmp/$BIN
done

for LIB in $online_usrlib; do
    cp /usr/lib/$LIB /tmp/$LIB
    strip --strip-debug /tmp/$LIB
    install -vm755 /tmp/$LIB /usr/lib
    rm /tmp/$LIB
done

for i in $(find /usr/lib -type f -name \*.so* ! -name \*dbg) \
         $(find /usr/lib -type f -name \*.a)                 \
         $(find /usr/{bin,sbin,libexec} -type f); do
    case "$online_usrbin $online_usrlib $save_usrlib" in
        *$(basename $i)* )
            ;;
        * ) strip --strip-debug $i
            ;;
    esac
done

unset BIN LIB save_usrlib online_usrbin online_usrlib

# 8.86. Cleaning Up
rm -rf /tmp/{*,.*}
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
userdel -r tester

cd /sources
