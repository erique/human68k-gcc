#!/bin/sh
# Wrapper for DejaGNU: convert ELF to X-file and run with run68
# Usage: run68-sim.sh <elf-binary> [args...]

PREFIX=/opt/human68k
ELF2X68K="${PREFIX}/bin/elf2x68k"
RUN68="${PREFIX}/bin/run68"

ELF="$1"
shift

if [ ! -f "$ELF" ]; then
    echo "run68-sim: $ELF: not found" >&2
    exit 1
fi

XFILE="${ELF}.x"
"$ELF2X68K" "$ELF" "$XFILE" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "run68-sim: elf2x68k conversion failed" >&2
    exit 1
fi

"$RUN68" "$XFILE" "$@"
RC=$?
rm -f "$XFILE"
exit $RC
