# human68k-gcc (4.6.2)

Docker build script for [Lyderic Maillet's][lydux] GCC 4.6.2 cross-compiler
for the Sharp X68000 / Human68k (2012).   
Clones and builds the forks of the original toolchain components:

- [binutils 2.22][binutils]
- [GCC 4.6.2][gcc]
- [newlib 1.19.0][newlib]
- [GDB 7.4][gdb] (with HudsonBug ROM monitor stub)

Installs to `/opt/toolchains/x68k`, target triple is `human68k`.

[lydux]: https://github.com/Lydux/gcc-4.6.2-human68k
[binutils]: https://github.com/erique/binutils-2.22-human68k
[gcc]: https://github.com/erique/gcc-4.6.2-human68k
[newlib]: https://github.com/erique/newlib-1.19.0-human68k
[gdb]: https://github.com/erique/gdb-7.4-human68k
