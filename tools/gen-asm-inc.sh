#!/bin/bash
# gen-asm-inc.sh — Generate dos.inc and iocs.inc from newlib .S wrappers
#
# Usage: gen-asm-inc.sh <human68k-sysdir> <output-dir>
#   human68k-sysdir: path to projects/newlib/newlib/libc/sys/human68k
#   output-dir:      where to write dos.inc and iocs.inc

set -e

SYSDIR="$1"
OUTDIR="$2"

if [ -z "$SYSDIR" ] || [ -z "$OUTDIR" ]; then
    echo "Usage: $0 <human68k-sysdir> <output-dir>" >&2
    exit 1
fi

DOSDIR="$SYSDIR/libdos"
IOCSDIR="$SYSDIR/libiocs"

if [ ! -d "$DOSDIR" ] || [ ! -d "$IOCSDIR" ]; then
    echo "Error: $DOSDIR or $IOCSDIR not found" >&2
    exit 1
fi

mkdir -p "$OUTDIR"

# =========================================================
# dos.inc — Human68k DOS call macros
# =========================================================
generate_dos()
{
    cat <<'HEADER'
; dos.inc — Human68k DOS call macros (auto-generated from newlib)
;
; Three layers:
;   1. EQU constants:  _DOS_EXIT equ $FF00
;   2. Generic macro:  DOS _DOS_EXIT      (emits dc.w)
;   3. Convenience:    EXIT / PRINT / ... (full calling convention)
;
; DOS calling convention: push args on stack, dc.w $FFxx, clean stack.
; Return value in D0.

; =========================================================
; Generic DOS dispatcher macro
; =========================================================
DOS	macro
	dc.w	\1
	endm

; =========================================================
; EQU constants for all DOS calls
; =========================================================
HEADER

    for f in "$DOSDIR"/*.S; do
        [ -f "$f" ] || continue
        # Derive function name from filename: exit.S → _DOS_EXIT
        base=$(basename "$f" .S)
        equ_name="_DOS_$(echo "$base" | tr '[:lower:]' '[:upper:]')"
        # Extract trap number from .short 0xff..
        trapnum=$(grep '\.short' "$f" | head -1 | sed 's/.*\.short[[:space:]]*//' | tr -d '[:space:]')
        [ -z "$trapnum" ] && continue
        # Convert 0xffxx to $FFxx
        equ_val=$(echo "$trapnum" | sed 's/0x/\$/' | tr '[:lower:]' '[:upper:]')
        printf "%-20s equ\t%s\n" "$equ_name" "$equ_val"
    done | sort -t'$' -k2

    cat <<'FOOTER'

; =========================================================
; Convenience macros for common DOS calls
; =========================================================

; _dos_exit — terminate program (no args)
EXIT	macro
	dc.w	_DOS_EXIT
	endm

; _dos_getchar — read character with echo (no args, result in D0)
GETCHAR	macro
	dc.w	_DOS_GETCHAR
	endm

; _dos_putchar — output character
;   \1 = character (word value or register)
PUTCHAR	macro
	move.w	\1,-(sp)
	dc.w	_DOS_PUTCHAR
	addq.l	#2,sp
	endm

; _dos_print — print string
;   \1 = string address
PRINT	macro
	pea	\1
	dc.w	_DOS_PRINT
	addq.l	#4,sp
	endm

; _dos_create — create file
;   \1 = filename address, \2 = mode (word)
CREATE	macro
	move.w	\2,-(sp)
	pea	\1
	dc.w	_DOS_CREATE
	addq.l	#6,sp
	endm

; _dos_open — open file
;   \1 = filename address, \2 = mode (word)
OPEN	macro
	move.w	\2,-(sp)
	pea	\1
	dc.w	_DOS_OPEN
	addq.l	#6,sp
	endm

; _dos_close — close file
;   \1 = file handle (word)
CLOSE	macro
	move.w	\1,-(sp)
	dc.w	_DOS_CLOSE
	addq.l	#2,sp
	endm

; _dos_read — read from file
;   \1 = handle (word), \2 = buffer address, \3 = length (long)
READ	macro
	move.l	\3,-(sp)
	pea	\2
	move.w	\1,-(sp)
	dc.w	_DOS_READ
	lea	10(sp),sp
	endm

; _dos_write — write to file
;   \1 = handle (word), \2 = buffer address, \3 = length (long)
WRITE	macro
	move.l	\3,-(sp)
	pea	\2
	move.w	\1,-(sp)
	dc.w	_DOS_WRITE
	lea	10(sp),sp
	endm

; _dos_seek — seek in file
;   \1 = handle (word), \2 = offset (long), \3 = whence (word)
SEEK	macro
	move.w	\3,-(sp)
	move.l	\2,-(sp)
	move.w	\1,-(sp)
	dc.w	_DOS_SEEK
	addq.l	#8,sp
	endm

; _dos_malloc — allocate memory
;   \1 = size (long)
MALLOC	macro
	move.l	\1,-(sp)
	dc.w	_DOS_MALLOC
	addq.l	#4,sp
	endm

; _dos_mfree — free memory
;   \1 = pointer
MFREE	macro
	pea	\1
	dc.w	_DOS_MFREE
	addq.l	#4,sp
	endm

; _dos_chdir — change directory
;   \1 = path address
CHDIR	macro
	pea	\1
	dc.w	_DOS_CHDIR
	addq.l	#4,sp
	endm

; _dos_delete — delete file
;   \1 = filename address
DELETE	macro
	pea	\1
	dc.w	_DOS_DELETE
	addq.l	#4,sp
	endm

; _dos_mkdir — create directory
;   \1 = path address
MKDIR	macro
	pea	\1
	dc.w	_DOS_MKDIR
	addq.l	#4,sp
	endm

; _dos_rmdir — remove directory
;   \1 = path address
RMDIR	macro
	pea	\1
	dc.w	_DOS_RMDIR
	addq.l	#4,sp
	endm

; _dos_chmod — get/set file attributes
;   \1 = filename address, \2 = mode (word)
CHMOD	macro
	move.w	\2,-(sp)
	pea	\1
	dc.w	_DOS_CHMOD
	addq.l	#6,sp
	endm

; _dos_exit2 — terminate with return code
;   \1 = return code (word)
EXIT2	macro
	move.w	\1,-(sp)
	dc.w	_DOS_EXIT2
	endm

; _dos_c_print — console print string
;   \1 = string address
C_PRINT	macro
	pea	\1
	dc.w	_DOS_C_PRINT
	addq.l	#4,sp
	endm

; _dos_c_putc — console put character
;   \1 = character (word)
C_PUTC	macro
	move.w	\1,-(sp)
	dc.w	_DOS_C_PUTC
	addq.l	#2,sp
	endm

; _dos_c_locate — set cursor position
;   \1 = x (word), \2 = y (word)
C_LOCATE	macro
	move.w	\2,-(sp)
	move.w	\1,-(sp)
	dc.w	_DOS_C_LOCATE
	addq.l	#4,sp
	endm

; _dos_c_color — set text color
;   \1 = color (word)
C_COLOR	macro
	move.w	\1,-(sp)
	dc.w	_DOS_C_COLOR
	addq.l	#2,sp
	endm

; _dos_super — enter/exit supervisor mode
;   \1 = stack pointer (long, 0=enter, saved_sp=exit)
SUPER	macro
	move.l	\1,-(sp)
	dc.w	_DOS_SUPER
	addq.l	#4,sp
	endm

; _dos_keeppr — terminate and stay resident
;   \1 = size (long), \2 = exit code (word)
KEEPPR	macro
	move.w	\2,-(sp)
	move.l	\1,-(sp)
	dc.w	_DOS_KEEPPR
	endm

; _dos_inkey — non-blocking key input (no args, result in D0)
INKEY	macro
	dc.w	_DOS_INKEY
	endm

; _dos_vernum — get DOS version number (no args, result in D0)
VERNUM	macro
	dc.w	_DOS_VERNUM
	endm

; _dos_curdrv — get current drive (no args, result in D0)
CURDRV	macro
	dc.w	_DOS_CURDRV
	endm

; _dos_filedate — get/set file date
;   \1 = handle (word), \2 = date (long, 0=get)
FILEDATE	macro
	move.l	\2,-(sp)
	move.w	\1,-(sp)
	dc.w	_DOS_FILEDATE
	addq.l	#6,sp
	endm
FOOTER
}

# =========================================================
# iocs.inc — Human68k IOCS call macros
# =========================================================
generate_iocs()
{
    cat <<'HEADER'
; iocs.inc — Human68k IOCS call macros (auto-generated from newlib)
;
; Three layers:
;   1. EQU constants:  _IOCS_B_KEYINP equ $00
;   2. Generic macro:  IOCS _IOCS_B_KEYINP  (emits moveq+trap)
;   3. Convenience:    B_KEYINP / CRTMOD / ... (load regs + trap)
;
; IOCS calling convention: function number in D0, args in D1-D5/A1-A2.
; trap #15. Return value in D0.

; =========================================================
; Generic IOCS dispatcher macro
; =========================================================
IOCS	macro
	moveq	#\1,d0
	trap	#15
	endm

; =========================================================
; EQU constants for all IOCS calls
; =========================================================
HEADER

    for f in "$IOCSDIR"/*.S; do
        [ -f "$f" ] || continue
        # Derive function name from filename: b_keyinp.S → _IOCS_B_KEYINP
        base=$(basename "$f" .S)
        equ_name="_IOCS_$(echo "$base" | tr '[:lower:]' '[:upper:]')"
        # Extract function number from moveq #0xXX, %d0
        funcnum=$(grep 'moveq' "$f" | head -1 | sed 's/.*moveq[[:space:]]*#//' | sed 's/,.*//' | tr -d '[:space:]')
        [ -z "$funcnum" ] && continue
        # Convert to vasm hex format
        if echo "$funcnum" | grep -q '^0xffffff'; then
            # Negative value (sign-extended byte)
            byte=$(echo "$funcnum" | sed 's/0xffffff//')
            equ_val=$(echo "\$FFFFFF${byte}" | tr '[:lower:]' '[:upper:]')
        elif echo "$funcnum" | grep -q '^0x'; then
            equ_val=$(echo "$funcnum" | sed 's/0x/\$/' | tr '[:lower:]' '[:upper:]')
        else
            # Plain decimal
            equ_val="$funcnum"
        fi
        printf "%-20s equ\t%s\n" "$equ_name" "$equ_val"
    done | sort

    cat <<'FOOTER'

; =========================================================
; Convenience macros for common IOCS calls
; =========================================================

; _iocs_b_keyinp — keyboard input (no args, result in D0)
B_KEYINP	macro
	moveq	#_IOCS_B_KEYINP,d0
	trap	#15
	endm

; _iocs_b_keysns — keyboard sense (no args, result in D0)
B_KEYSNS	macro
	moveq	#_IOCS_B_KEYSNS,d0
	trap	#15
	endm

; _iocs_b_putc — put character
;   \1 = character (loaded into D1)
B_PUTC	macro
	move.l	\1,d1
	moveq	#_IOCS_B_PUTC,d0
	trap	#15
	endm

; _iocs_b_print — print string
;   \1 = string address (loaded into A1)
B_PRINT	macro
	lea	\1,a1
	moveq	#_IOCS_B_PRINT,d0
	trap	#15
	endm

; _iocs_b_color — set text color
;   \1 = color (loaded into D1)
B_COLOR	macro
	move.l	\1,d1
	moveq	#_IOCS_B_COLOR,d0
	trap	#15
	endm

; _iocs_b_locate — set cursor position
;   \1 = x (loaded into D1), \2 = y (loaded into D2)
B_LOCATE	macro
	move.l	\1,d1
	move.l	\2,d2
	moveq	#_IOCS_B_LOCATE,d0
	trap	#15
	endm

; _iocs_crtmod — set CRT display mode
;   \1 = mode (loaded into D1)
CRTMOD	macro
	move.l	\1,d1
	moveq	#_IOCS_CRTMOD,d0
	trap	#15
	endm

; _iocs_contrast — set contrast
;   \1 = contrast (loaded into D1)
CONTRAST	macro
	move.l	\1,d1
	moveq	#_IOCS_CONTRAST,d0
	trap	#15
	endm

; _iocs_joyget — read joystick
;   \1 = joystick number (loaded into D1)
JOYGET	macro
	move.l	\1,d1
	moveq	#_IOCS_JOYGET,d0
	trap	#15
	endm

; _iocs_bitsns — key matrix sense
;   \1 = group number (loaded into D1)
BITSNS	macro
	move.l	\1,d1
	moveq	#_IOCS_BITSNS,d0
	trap	#15
	endm

; _iocs_set232c — set RS-232C parameters
;   \1 = parameters (loaded into D1)
SET232C	macro
	move.l	\1,d1
	moveq	#_IOCS_SET232C,d0
	trap	#15
	endm

; _iocs_inp232c — read RS-232C (no args, result in D0)
INP232C	macro
	moveq	#_IOCS_INP232C,d0
	trap	#15
	endm

; _iocs_out232c — write RS-232C
;   \1 = character (loaded into D1)
OUT232C	macro
	move.l	\1,d1
	moveq	#_IOCS_OUT232C,d0
	trap	#15
	endm

; _iocs_gpalet — set graphics palette
;   \1 = palette number (loaded into D1), \2 = color (loaded into D2)
GPALET	macro
	move.l	\1,d1
	move.l	\2,d2
	moveq	#_IOCS_GPALET,d0
	trap	#15
	endm

; _iocs_tpalet — set text palette
;   \1 = palette number (loaded into D1), \2 = color (loaded into D2)
TPALET	macro
	move.l	\1,d1
	move.l	\2,d2
	moveq	#_IOCS_TPALET,d0
	trap	#15
	endm

; _iocs_apage — set graphics active page
;   \1 = page (loaded into D1)
APAGE	macro
	move.l	\1,d1
	moveq	#_IOCS_APAGE,d0
	trap	#15
	endm

; _iocs_vpage — set graphics visible page
;   \1 = page (loaded into D1)
VPAGE	macro
	move.l	\1,d1
	moveq	#_IOCS_VPAGE,d0
	trap	#15
	endm

; _iocs_g_clr_on — clear and enable graphics (no args)
G_CLR_ON	macro
	moveq	#_IOCS_G_CLR_ON,d0
	trap	#15
	endm

; _iocs_ms_init — initialize mouse (no args)
MS_INIT	macro
	moveq	#_IOCS_MS_INIT,d0
	trap	#15
	endm

; _iocs_ms_curon — show mouse cursor (no args)
MS_CURON	macro
	moveq	#_IOCS_MS_CURON,d0
	trap	#15
	endm

; _iocs_ms_curof — hide mouse cursor (no args)
MS_CUROF	macro
	moveq	#_IOCS_MS_CUROF,d0
	trap	#15
	endm

; _iocs_ms_getdt — get mouse data (no args, result in D0)
MS_GETDT	macro
	moveq	#_IOCS_MS_GETDT,d0
	trap	#15
	endm

; _iocs_sp_init — initialize sprites (no args)
SP_INIT	macro
	moveq	#_IOCS_SP_INIT,d0
	trap	#15
	endm

; _iocs_sp_on — enable sprite display (no args)
SP_ON	macro
	moveq	#_IOCS_SP_ON,d0
	trap	#15
	endm

; _iocs_sp_off — disable sprite display (no args)
SP_OFF	macro
	moveq	#_IOCS_SP_OFF,d0
	trap	#15
	endm

; _iocs_b_clr_al — clear entire screen (no args)
B_CLR_AL	macro
	moveq	#_IOCS_B_CLR_AL,d0
	trap	#15
	endm

; _iocs_b_curon — show text cursor (no args)
B_CURON	macro
	moveq	#_IOCS_B_CURON,d0
	trap	#15
	endm

; _iocs_b_curoff — hide text cursor (no args)
B_CUROFF	macro
	moveq	#_IOCS_B_CUROFF,d0
	trap	#15
	endm

; _iocs_defchr — define character pattern
;   \1 = font code (loaded into D1), \2 = size (loaded into D2), \3 = pattern addr (loaded into A1)
DEFCHR	macro
	move.l	\1,d1
	move.l	\2,d2
	lea	\3,a1
	moveq	#_IOCS_DEFCHR,d0
	trap	#15
	endm

; _iocs_timeget — get time (no args, result in D0)
TIMEGET	macro
	moveq	#_IOCS_TIMEGET,d0
	trap	#15
	endm

; _iocs_timeset — set time
;   \1 = time value (loaded into D1)
TIMESET	macro
	move.l	\1,d1
	moveq	#_IOCS_TIMESET,d0
	trap	#15
	endm

; _iocs_romver — get ROM version (no args, result in D0)
ROMVER	macro
	moveq	#_IOCS_ROMVER,d0
	trap	#15
	endm
FOOTER
}

# Generate both files
generate_dos > "$OUTDIR/dos.inc"
generate_iocs > "$OUTDIR/iocs.inc"

echo "Generated $OUTDIR/dos.inc and $OUTDIR/iocs.inc"
