# TODO

## Binary Comparison: GCC 6.5.0 vs Original X68k (Sharp XC)

Comparison of TCPPACKB sample programs built from same source code with the
original 1995 Sharp XC compiler vs our GCC 6.5.0 cross-compiler.

### File Size

| Program   | Original | New    | Ratio |
|-----------|----------|--------|-------|
| arp       | 35834    | 89764  | 2.5x  |
| ifconfig  | 34194    | 85142  | 2.5x  |
| inetdconf | 34966    | 86006  | 2.5x  |
| netstat   | 37614    | 91752  | 2.4x  |
| ping      | 39112    | 92370  | 2.4x  |

### Text Section (code + rodata)

New text is ~3x larger. Breakdown of arp (84KB text):

| Category              | Bytes | Share |
|-----------------------|-------|-------|
| Printf/Scanf/IO      | 54057 | 64%   |
| Other newlib          | 10393 | 12%   |
| Soft-float (libgcc)   | 5168  | 6%    |
| App logic             | 5174  | 6%    |
| String/Mem functions  | 2970  | 4%    |
| CRT startup           | 1254  | 1%    |
| Malloc/Sbrk           | 1126  | 1%    |

Printf/scanf cluster alone (54KB) accounts for 78% of the text size difference.
Application logic is roughly the same size in both (~5KB).

### BSS Section

| Program   | Original | New |
|-----------|----------|-----|
| arp       | 29918    | 520 |
| ifconfig  | 29894    | 504 |

Original BSS is ~30KB, dominated by `_fddb` (file descriptor database table).
New BSS is ~520 bytes (small globals, mutexes, 128-byte hostname buffer).
Our newlib doesn't pre-allocate a massive fd table -- BSS is 58x smaller.

### Data Section

Roughly similar size (~1700 bytes original, ~2500 bytes new). The difference is
newlib's `impure_data` struct (1058 bytes) and `global_locale` (360 bytes), which
the original libc doesn't have.

### Entry Point

Original binaries have a non-zero entry point (e.g. 0x62e for arp) that skips
past RCS `$Id$` version strings embedded at the start of the text section.
New binaries have entry=0 -- our crt0.S is first, with a `bra` past the X68000
LIBC magic string.

### Symbol Table

Original binaries include a full symbol table (~4KB, ~140 symbols).
New binaries have no symbols by default. `elf2x68k -s` adds symbols (~9KB, 526).

### Relocations

New binaries have ~2x more relocations (proportional to the larger text).
Both use the same X68k delta-encoded word format.

### CRT0

Original (XC libc): sets SP to a hardcoded address, calls `__main`, runs ctors.
New (our crt0.S): parses PSP memory block, sets up heap/stack dynamically with
weak symbols (`__stack_size`, `__heap_size`) overridable at link time.

### Source Compatibility (patches required)

The original SDK source was written for Sharp's XC compiler and its libc. Building
with GCC + newlib required the following categories of patches:

**DOS call inlining (`__DOS_INLINE__` / `DOS SUPER_JSR`):**
The XC toolchain supported `#define __DOS_INLINE__` before `#include <sys/dos.h>`
to emit DOS calls as inline `trap #15` instructions with a `DOS` assembler pseudo-op
(e.g. `DOS SUPER_JSR`). GCC's assembler doesn't understand the `DOS` pseudo-op.
Patched to use explicit `move.w #0xFF2A,-(sp); trap #15` sequences instead.
Our `<sys/dos.h>` declares `_dos_*` as extern functions (in libdos.a), not inlines.

**XC-specific headers:**
`<conio.h>` (console I/O), `<sys/scsi.h>` (SCSI), `<iocslib.h>` (with
`__IOCS_INLINE__` for inline IOCS calls) -- not available in our toolchain.
Patched to remove or replace with our equivalents (`<sys/iocs.h>`).

**struct name differences:**
XC libc used `struct _psp` / `struct _mep`. Our `<sys/dos.h>` uses
`struct dos_psp` / `struct dos_mep`. Patched in search_ti_entry.c.

**`bzero()` -> `memset()`:**
Original code used BSD `bzero()`. Patched to `memset(..., 0, ...)`.

**`sys/types.h` conflict:**
XC's `<sys/types.h>` defined all types directly. Our SDK headers now use
`#include_next <sys/types.h>` to redirect to newlib's version while keeping
the original include guard for compatibility.

**`snprintf()` reimplementation:**
Original used XC's internal `_doprnt()` with `struct _stdbuf`. Patched to use
standard `vsnprintf()` from newlib.

**`_EXTERN()` macro and `<cdecl.h>`:**
XC headers used `_EXTERN(int foo(void))` macro from `<cdecl.h>`. Replaced with
plain C prototypes.

## XC Source Compatibility

Existing X68k C code was written for Sharp's XC compiler and XLIBC. To minimize
patches needed when porting, we should improve compatibility with the XC API.

Reference implementations: yunkya2/elf2x68k and yosshin4004/xdev68k both download
XC 2.1 headers and libraries from http://retropc.net/x68000/software/sharp/xc21/.  

- **`__DOS_INLINE__` support**: Add inline DOS call path to `<sys/dos.h>`, same
  mechanism as IOCS inlining. When defined before include, emit `trap #15` with
  function number instead of calling libdos.a. Most existing X68k code uses this.
- **`__IOCS_INLINE__` naming**: Rename our IOCS inline define to match XC's
  `__IOCS_INLINE__` so existing `#define __IOCS_INLINE__` / `#include <iocslib.h>`
  works without changes.
- **XC struct names**: Rename `struct dos_psp` -> `struct _psp`,
  `struct dos_mep` -> `struct _mep`, etc. to match XC's `<sys/dos.h>`.
  Or provide both names via typedef/define.
- **`bzero()`**: Add to `<strings.h>` -- it's BSD/POSIX.1-2001, widely used in
  X68k code. Trivial: `#define bzero(s,n) memset(s,0,n)` or a real function.
- **`<sys/scsi.h>`**: Add SCSI interface header from XC.
- **`<conio.h>`**: Add console I/O header from XC.
- **`<iocslib.h>`**: Compatibility wrapper that includes `<sys/iocs.h>` with
  `__IOCS_INLINE__` semantics, matching XC's header name.
- **`_doprnt()` / `struct _stdbuf`**: Consider adding XC's internal printf
  interface for code that uses it directly (e.g. custom snprintf implementations).
- **`<cdecl.h>` / `_EXTERN()` macro**: Add a compatibility header so old code
  using `_EXTERN(int foo(void))` compiles without changes.

## Soft-Float vs Runtime FPU Dispatch

XC's float library uses runtime FPU detection: `_iscopro` checks for a
68881/68882 coprocessor at startup, then dispatches through `_fpu_*` (real FPU
instructions) or `_fe_*` (software emulation). A single binary runs on both
stock 68000 and 68000+68881 hardware, using the FPU when available.

Our libgcc (`lb1sf68.S`) is pure software float -- always emulates, never uses
the FPU even if one is present. Also includes extended precision (`xf`) routines
that XC doesn't have, adding ~1KB of bulk.

Note: most of the SDK programs don't actually use float at all. The soft-float
code gets pulled in because newlib's printf always links the float formatting
path. `--enable-newlib-nano-formatted-io` would eliminate this for non-float
programs entirely.

## Binary Size Reduction

Newlib's printf unconditionally pulls in dtoa (~54KB) even without `%f`.
This accounts for 78% of the 3x text bloat vs original XC binaries.

Options:
- `--enable-newlib-nano-formatted-io` -- drops dtoa but loses `%f` entirely
- **Replace printf/scanf family** with lightweight implementation that does
  float-to-string inline (no dtoa). Candidates: libnix's `__vfprintf_total_size.c`
  (~3KB with float), mpaland/printf (~600 lines). Rest of newlib stays as-is.
- `-ffunction-sections` + `--gc-sections` -- complementary, eliminates other dead code
