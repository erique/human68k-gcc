#!/bin/bash

# ( Based on https://www.target-earth.net/wiki/doku.php?id=blog:x68_devtools )

# apt-get update -y
# apt-get install -y bison texinfo flex expect build-essential git wget libncurses-dev

PREFIX=/opt/toolchains/x68k
TRIPLET=--build=unknown-unknown-linux

mkdir -p gcc_x68k
cd gcc_x68k

git clone https://github.com/erique/binutils-2.22-human68k.git &
git clone https://github.com/erique/gcc-4.6.2-human68k.git &
git clone https://github.com/erique/gdb-7.4-human68k.git &
git clone https://github.com/erique/newlib-1.19.0-human68k.git &

wait

set -xe

printf 'diff --git a/gcc-4.6.2-human68k/gcc/ira-int.h.bak b/gcc-4.6.2-human68k/gcc/ira-int.h\nindex 049a07f..ddf1200 100644\n--- a/gcc-4.6.2-human68k/gcc/ira-int.h\n+++ b/gcc-4.6.2-human68k/gcc/ira-int.h\n@@ -1123,8 +1123,13 @@ static inline bool\n ira_allocno_object_iter_cond (ira_allocno_object_iterator *i, ira_allocno_t a,\n \t\t\t      ira_object_t *o)\n {\n-  *o = ALLOCNO_OBJECT (a, i->n);\n-  return i->n++ < ALLOCNO_NUM_OBJECTS (a);\n+   int n = i->n++;\n+   if (n < ALLOCNO_NUM_OBJECTS (a))\n+   {\n+      *o = ALLOCNO_OBJECT (a, n);\n+      return true;\n+   }\n+   return false;\n }\n \n /* Loop over all objects associated with allocno A.  In each\n' | patch -p1
cd gcc-4.6.2-human68k && ./contrib/download_prerequisites && cd -

build() {
  mkdir -p $1-build
  pushd $1-build
  ../$1/configure --prefix=$PREFIX --target=human68k $2 $TRIPLET
  sed -i 's/MAKEINFO = makeinfo/MAKEINFO = true/g' Makefile
  make -j
  make install
  popd
}

build binutils-2.22-human68k "--disable-nls --disable-werror"
build gcc-4.6.2-human68k "--disable-nls --disable-libssp --with-newlib --without-headers --enable-languages=c --disable-werror"
build gdb-7.4-human68k "--disable-werror"

export PATH=$PATH:$PREFIX/bin
ln -s $PREFIX/bin/human68k-gcc /usr/bin/human68k-cc
build newlib-1.19.0-human68k "--disable-werror"

# Patch dos.h (see https://nfggames.com/forum2/index.php?topic=6002.msg41392#msg41392 )
cd /
cat << EOF | patch -p0
--- /opt/toolchains/x68k/human68k/include/dos.h	2025-06-03 21:27:08.000000000 +0000
+++ /opt/toolchains/x68k/human68k/include/dos.h	2025-06-03 21:37:04.032412295 +0000
@@ -235,7 +235,7 @@
 	struct dos_dpbptr *next;
 	unsigned short	dirfat;
 	char		dirbuf[64];
-} __attribute__((__packed__));
+} __attribute__((__packed__)) __attribute__((aligned (2)));
 
 struct dos_filbuf {
 	unsigned char	searchatr;
@@ -250,7 +250,7 @@
 	unsigned short	date;
 	unsigned int	filelen;
 	char		name[23];
-} __attribute__((__packed__));
+} __attribute__((__packed__)) __attribute__((aligned (2)));
 
 struct dos_exfilbuf {
 	unsigned char	searchatr;
@@ -268,7 +268,7 @@
 	char		drive[2];
 	char		path[65];
 	char		unused[21];
-} __attribute__((__packed__));
+} __attribute__((__packed__)) __attribute__((aligned (2)));
 
 struct dos_dregs {
 	int	d0;
EOF
