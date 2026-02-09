# human68k-gcc

GCC cross-compiler for the Sharp X68000 / Human68k, based on
[amiga-gcc](https://codeberg.org/bebbo/amiga-gcc) by Stefan "Bebbo" Franke.

Builds a complete `m68k-human68k` toolchain: GCC 6.5.0, binutils 2.39,
newlib 3.0, plus the `elf2x68k` ELF-to-X-file converter and the `run68`
Human68k emulator for testing.

## Quick start

```sh
make min                # builds binutils, gcc, newlib, libgcc, tools
make check              # runs human68k tests + GCC torture suite
```

Default install prefix is `/opt/human68k`. Override with `PREFIX=/path make min`.

## Build pipeline

```
source.c --> m68k-human68k-gcc --> ELF (.elf) --> elf2x68k --> X-file (.x)
```

The toolchain compiles and links to standard ELF, then `elf2x68k` converts
to the Human68k X-file executable format with delta-encoded relocations and
optional symbol tables.

## IOCS / DOS calls

System calls are provided as library functions via hand-written assembly stubs
in newlib (219 IOCS + 187 DOS):

- **IOCS** (I/O Controller Supervisor): `trap #15` with function number in d0.
  Called as `_iocs_xxx()` from C, declared in `<iocs.h>`.
- **DOS** (Disk Operating System): Inline `.short 0xFFxx` opcodes with args on stack.
  Called as `_dos_xxx()` from C, declared in `<dos.h>`.

## Comparison with other X68000 cross-compilers

Four cross-compiler projects exist for the X68000. All target the MC68000 and
produce Human68k X-file executables, but they differ significantly in approach.

### Overview

|                      | [lydux][lydux] (2012)  | human68k-gcc (this)    | [xdev68k][xdev68k]     | [elf2x68k][elf2x68k]   |
|----------------------|------------------------|------------------------|------------------------|------------------------|
| **Status**           | Inactive since 2014    | Active                 | Active                 | Active                 |
| **GCC**              | 4.6.2                  | 6.5.0                  | 13.4.0                 | 13.4.0                 |
| **Binutils**         | 2.22                   | 2.39                   | 2.44                   | 2.44                   |
| **Newlib**           | 1.19.0                 | 3.0                    | --                     | 4.5.0                  |
| **GDB**              | 7.4 (ROM monitor)      | --                     | --                     | 16.3 (gdbserver)       |
| **Target triple**    | `human68k`             | `m68k-human68k`        | `m68k-elf`             | `m68k-xelf`            |
| **Languages**        | C                      | C, C++                 | C, C++                 | C, C++                 |
| **C library**        | Newlib only            | Newlib only            | Native XC/LIBC         | Newlib or native XC    |
| **Emulator**         | --                     | run68                  | run68                  | run68                  |

### Pipeline

|                      | lydux                  | human68k-gcc           | xdev68k                | yunkya2/elf2x68k       |
|----------------------|------------------------|------------------------|------------------------|------------------------|
| **Assembler**        | GAS (patched)          | GAS (patched)          | GAS -> HAS060.X        | GAS (unmodified)       |
| **Linker**           | LD (patched)           | LD (patched)           | hlk301.x (native)      | LD (unmodified)        |
| **Object format**    | ELF (internal)         | ELF (internal)         | Native X68k            | ELF (internal)         |
| **X-file conversion**| `objcopy -O xfile`     | `elf2x68k`             | Native linker output   | `m68k-xelf-elf2x68k`  |
| **GCC/binutils patches** | Yes (deep)         | Yes (deep)             | No (unmodified)        | No (specs file only)   |

### Approach details

**lydux** -- Patched GCC, binutils, and newlib with native
Human68k target support. Added an X-file BFD backend to `objcopy` for
format conversion. Included a GDB port with HudsonBug ROM monitor backend
for on-hardware debugging over serial. Also implemented an `iocscall` GCC
attribute for declaring IOCS trap calls directly in C, though it was never
used in practice (all projects use assembly stubs instead). Development
stopped in 2014.

**human68k-gcc** (this project) -- Direct successor to lydux's work. Upgrades
to GCC 6.5.0 / binutils 2.39 / newlib 3.0 by rebasing onto the amiga-gcc
fork, which provides m68k enhancements (regparm support, 68000 cost model,
C++ support, bebbo's RTL optimizer). Replaces the BFD X-file backend with a
standalone `elf2x68k` converter. The newlib Human68k syscall layer, IOCS/DOS
stubs, crt0, and linker scripts carry forward from lydux with fixes.

**xdev68k** -- Takes a completely different approach: uses an unmodified
`m68k-elf` GCC toolchain and converts GAS assembly output to Motorola syntax
via a Perl script (`x68k_gas2has.pl`), then assembles and links with the
original Sharp tools (HAS060.X, hlk301.x) running under the run68 emulator.
This means it can use native X68k libraries directly (XC, LIBC) without any
newlib port, but depends on the GAS-to-HAS conversion handling all edge cases.
Uses `-fcall-used-d2 -fcall-used-a2` for XC ABI compatibility.

**yunkya2/elf2x68k** -- Despite the repo name, this is a full toolchain
(GCC 13.4.0, binutils 2.44, newlib 4.5.0, GDB 16.3). Uses an unmodified
`m68k-elf` toolchain with a custom specs file that transparently invokes
an ELF-to-X-file converter at link time. Closest to our approach but avoids
patching GCC/binutils entirely. Can use either newlib (based on lydux's port)
or native XC libraries via an `x68k2elf` object converter. Provides remote
debugging via `gdbserver-x68k`. Uses `-fcall-used-d2 -fcall-used-a2` for
XC ABI compatibility.

### IOCS / DOS access

|                      | lydux                  | human68k-gcc           | xdev68k                | yunkya2/elf2x68k       |
|----------------------|------------------------|------------------------|------------------------|------------------------|
| **IOCS calls**       | Assembly stubs (219)   | Assembly stubs (219)   | Native XC headers      | Assembly stubs (219)   |
| **DOS calls**        | Assembly stubs (187)   | Assembly stubs (187)   | Native XC headers      | Assembly stubs (187)   |
| **iocscall attribute** | Implemented, unused  | Removed                | No                     | No                     |
| **Headers**          | `<iocs.h>` `<dos.h>`  | `<iocs.h>` `<dos.h>`  | XC `<iocslib.h>`       | `<x68k/iocs.h>` `<x68k/dos.h>` |

### Key trade-offs

**Patched vs unmodified toolchain**: lydux, human68k-gcc patch GCC/binutils
to add `m68k-human68k` as a proper target. xdev68k and yunkya2 use standard
`m68k-elf` and work around it externally. Patching gives a cleaner target
definition and native linker script support, but requires maintaining patches
across GCC upgrades. The unmodified approach makes version upgrades trivial.

**Native XC library support**: xdev68k and yunkya2 can link against original
Sharp XC/LIBC libraries. lydux and human68k-gcc use newlib exclusively.
For new code this rarely matters, but it enables reusing existing X68k
library code without recompilation.

**ABI compatibility**: xdev68k and yunkya2 use `-fcall-used-d2 -fcall-used-a2`
to match the XC calling convention where d0-d2/a0-a2 are caller-saved.
Standard GCC m68k ABI only caller-saves d0-d1/a0-a1.

## Credits

- **Lyderic Maillet** ([lydux][lydux]) -- Original Human68k cross-compiler (GCC 4.6.2, 2012)
- **Stefan Franke** ([bebbo](https://codeberg.org/bebbo/amiga-gcc)) -- amiga-gcc fork with m68k enhancements
- **TcbnErik** ([kg68k](https://github.com/kg68k/run68x)) -- run68x Human68k emulator

[lydux]: https://github.com/Lydux/gcc-4.6.2-human68k
[xdev68k]: https://github.com/yosshin4004/xdev68k
[elf2x68k]: https://github.com/yunkya2/elf2x68k
