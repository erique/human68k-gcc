# human68k-gcc

GCC cross-compiler for the Sharp X68000 / Human68k.

Forward-ports [Lyderic Maillet's][lydux] original Human68k cross-compiler
(GCC 4.6.2, 2012) onto [Stefan "Bebbo" Franke's amiga-gcc][amiga-gcc] fork,
which provides GCC 6.5.0 with significant m68k-specific optimizations.

Builds a complete `m68k-human68k` toolchain: GCC 6.5.0, binutils 2.39,
newlib 3.0, plus:

- **elf2x68k** -- ELF-to-X-file converter
- **run68** -- Human68k CLI emulator for testing
- **vasm** -- m68k assembler with Motorola syntax
- **hudson-bridge** -- GDB RSP to DB.X protocol bridge for on-hardware debugging

## Quick start

```sh
make min                # builds binutils, gcc, newlib, libgcc, tools
make vasm               # builds vasm assembler + DOS/IOCS include files
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

For hand-written assembly, vasm can produce ELF (for linking with GCC) or
X-files directly:

```
source.S --> vasmm68k_mot -Felf --> .o --> gcc link --> elf2x68k --> .x
source.S --> vasmm68k_mot -Fxfile --> .x
```

## IOCS / DOS calls

System calls are provided as library functions via hand-written assembly stubs
in newlib (219 IOCS + 187 DOS):

- **IOCS** (I/O Controller Supervisor): `trap #15` with function number in d0.
  Called as `_iocs_xxx()` from C, declared in `<iocs.h>`.
- **DOS** (Disk Operating System): Inline `.short 0xFFxx` opcodes with args on stack.
  Called as `_dos_xxx()` from C, declared in `<dos.h>`.

For assembly programming, `make vasm` installs `dos.inc` and `iocs.inc` with
EQU constants, generic dispatcher macros, and convenience macros for common calls.

## Debugging

**hudson-bridge** bridges GDB's Remote Serial Protocol to the DB.X 3.00
text-based debugger running on real X68000 hardware (or MAME). Connect GDB
to the bridge, which translates commands to/from DB.X over a serial link.

Supports: registers, memory read/write, software breakpoints, single-step,
continue, and binary load (X protocol).

```
m68k-human68k-gdb program.elf --> hudson-bridge --> serial --> DB.X on X68000
```

## Comparison with other X68000 cross-compilers

Several cross-compiler projects exist for the X68000. All target the MC68000
and produce Human68k X-file executables, but they differ significantly in
approach.

### Overview

|                      | [lydux][lydux] (2012)  | human68k-gcc (this)    | [xdev68k][xdev68k]     | [elf2x68k][elf2x68k]   |
|----------------------|------------------------|------------------------|------------------------|------------------------|
| **Status**           | Inactive since 2014    | Active                 | Active                 | Active                 |
| **GCC**              | 4.6.2                  | 6.5.0                  | 13.4.0                 | 13.4.0                 |
| **Binutils**         | 2.22                   | 2.39                   | 2.44                   | 2.44                   |
| **Newlib**           | 1.19.0                 | 3.0                    | --                     | 4.5.0                  |
| **GDB**              | 7.4 (ROM monitor)      | 13.0 (DB.X bridge)     | --                     | 16.3 (gdbserver)       |
| **Target triple**    | `human68k`             | `m68k-human68k`        | `m68k-elf`             | `m68k-xelf`            |
| **Languages**        | C                      | C, C++                 | C, C++                 | C, C++                 |
| **C library**        | Newlib only            | Newlib only            | Native XC/LIBC         | Newlib or native XC    |
| **Assembler**        | GAS (patched)          | GAS + vasm             | GAS -> HAS060.X        | GAS (unmodified)       |
| **Emulator**         | --                     | run68                  | run68                  | run68                  |

### Pipeline

|                      | lydux                  | human68k-gcc           | xdev68k                | yunkya2/elf2x68k       |
|----------------------|------------------------|------------------------|------------------------|------------------------|
| **Assembler**        | GAS (patched)          | GAS (patched) + vasm   | GAS -> HAS060.X        | GAS (unmodified)       |
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

**human68k-gcc** (this project) -- Forward-ports lydux's Human68k target onto
[amiga-gcc][amiga-gcc], gaining GCC 6.5.0 with bebbo's m68k optimizations
(see below), C++ support, binutils 2.39, and newlib 3.0. Replaces the BFD
X-file backend with a standalone `elf2x68k` converter. Replaces lydux's GDB
ROM monitor stub with `hudson-bridge`, a GDB RSP to DB.X 3.00 protocol bridge.
The newlib Human68k syscall layer, IOCS/DOS stubs, crt0, and linker scripts
carry forward from lydux with fixes.

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
| **vasm includes**    | --                     | `dos.inc` `iocs.inc`   | --                     | --                     |

### Key trade-offs

**Patched vs unmodified toolchain**: lydux and human68k-gcc patch GCC/binutils
to add `m68k-human68k` as a proper target. xdev68k and yunkya2 use standard
`m68k-elf` and work around it externally. Patching gives a cleaner target
definition and native linker script support, but requires maintaining patches
across GCC upgrades. The unmodified approach makes version upgrades trivial.

**Optimizations**: human68k-gcc inherits amiga-gcc's m68k-specific optimization
pass (`bbb-opts.c`, ~7000 lines) not available in stock GCC at any version:
register renaming, move propagation out of loops, stack frame shrinking,
add merging, shift reduction, auto-increment addressing mode conversion, and
`__attribute__((regparm))` for passing parameters in registers. Also includes
68000-specific instruction cost tables (from the MC68000 User's Manual) for
scheduling and register allocation, replacing stock GCC's generic m68k costs.

**Native XC library support**: xdev68k and yunkya2 can link against original
Sharp XC/LIBC libraries. lydux and human68k-gcc use newlib exclusively.
For new code this rarely matters, but it enables reusing existing X68k
library code without recompilation.

**ABI compatibility**: xdev68k and yunkya2 use `-fcall-used-d2 -fcall-used-a2`
to match the XC calling convention where d0-d2/a0-a2 are caller-saved.
Standard GCC m68k ABI only caller-saves d0-d1/a0-a1. human68k-gcc does not
need this flag because its newlib IOCS wrappers save/restore d2 and a2
internally before calling `trap #15`. The flag is only required when linking
against original XC libraries that assume the Sharp calling convention.

## Credits

- **Lyderic Maillet** ([lydux][lydux]) -- Original Human68k cross-compiler (GCC 4.6.2, 2012)
- **Stefan "Bebbo" Franke** ([amiga-gcc][amiga-gcc]) -- amiga-gcc fork with m68k optimizations
- **TcbnErik** ([kg68k](https://github.com/kg68k/run68x)) -- run68x Human68k emulator

[lydux]: https://github.com/Lydux/gcc-4.6.2-human68k
[amiga-gcc]: https://codeberg.org/bebbo/amiga-gcc
[xdev68k]: https://github.com/yosshin4004/xdev68k
[elf2x68k]: https://github.com/yunkya2/elf2x68k
