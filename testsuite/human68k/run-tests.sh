#!/bin/sh
# Run human68k-specific tests
# Usage: run-tests.sh [test.c|test.cc ...]
# If no arguments, runs all .c and .cc files in this directory.

PREFIX="${HUMAN68K_PREFIX:-/opt/human68k}"
CC="${PREFIX}/bin/m68k-human68k-gcc"
CXX="${PREFIX}/bin/m68k-human68k-g++"
ELF2X68K="${PREFIX}/bin/elf2x68k"
RUN68="${PREFIX}/bin/run68"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR="${TMPDIR:-/tmp}"

pass=0
fail=0
error=0

run_one()
{
    src="$1"
    ext="${src##*.}"
    name="$(basename "$src")"
    name="${name%.*}"
    elf="${TMPDIR}/${name}.elf"
    xfile="${TMPDIR}/${name}.x"

    # pick compiler
    if [ "$ext" = "cc" ] || [ "$ext" = "cpp" ]; then
        compiler="$CXX"
    else
        compiler="$CC"
    fi

    printf "%-30s " "${name}..."

    # compile
    if ! "$compiler" -O2 "$src" -o "$elf" 2>"${TMPDIR}/${name}.err"; then
        printf "COMPILE ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    # convert
    if ! "$ELF2X68K" "$elf" "$xfile" 2>/dev/null; then
        printf "ELF2X68K ERROR\n"
        error=$((error + 1))
        rm -f "$elf" "$xfile" "${TMPDIR}/${name}.err"
        return
    fi

    # run
    output=$("$RUN68" "$xfile" 2>&1)
    rc=$?
    rm -f "$elf" "$xfile" "${TMPDIR}/${name}.err"

    if [ $rc -eq 0 ]; then
        printf "PASS\n"
        pass=$((pass + 1))
    else
        printf "FAIL (exit %d)\n" "$rc"
        echo "$output" | sed 's/^/  /'
        fail=$((fail + 1))
    fi
}

# collect test files
if [ $# -gt 0 ]; then
    tests="$@"
else
    tests=$(ls "${DIR}"/*.c "${DIR}"/*.cc 2>/dev/null | sort)
fi

for src in $tests; do
    [ -f "$src" ] && run_one "$src"
done

total=$((pass + fail + error))
printf "\n%d tests: %d pass, %d fail, %d error\n" "$total" "$pass" "$fail" "$error"

[ $fail -eq 0 ] && [ $error -eq 0 ]
