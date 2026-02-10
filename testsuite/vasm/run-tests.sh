#!/bin/sh
# Run vasm assembly tests
# Tests:
#   - standalone .S files: assemble, link, convert, run
#   - mixed .S + .c pairs: assemble .S with vasm, compile .c with gcc, link, run

PREFIX=/opt/human68k
VASM="${PREFIX}/bin/vasmm68k_mot"
CC="${PREFIX}/bin/m68k-human68k-gcc"
ELF2X68K="${PREFIX}/bin/elf2x68k"
RUN68="${PREFIX}/bin/run68"
READELF="${PREFIX}/bin/m68k-human68k-readelf"
GDB="${PREFIX}/bin/m68k-human68k-gdb"
ASM_INC="${PREFIX}/m68k-human68k/include/asm"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR="${TMPDIR:-/tmp}"

pass=0
fail=0
error=0

run_standalone()
{
    src="$1"
    name="$(basename "$src" .S)"
    obj="${TMPDIR}/${name}.o"
    elf="${TMPDIR}/${name}.elf"
    xfile="${TMPDIR}/${name}.x"

    printf "%-30s " "${name}..."

    if ! "$VASM" -Felf -o "$obj" -I "$ASM_INC" "$src" >/dev/null 2>"${TMPDIR}/${name}.err"; then
        printf "ASSEMBLE ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$obj" "${TMPDIR}/${name}.err"
        return
    fi

    if ! "$CC" -nostartfiles -o "$elf" "$obj" 2>>"${TMPDIR}/${name}.err"; then
        printf "LINK ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    if ! "$ELF2X68K" "$elf" "$xfile" 2>/dev/null; then
        printf "ELF2X68K ERROR\n"
        error=$((error + 1))
        rm -f "$obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"
        return
    fi

    output=$("$RUN68" "$xfile" 2>&1)
    rc=$?
    rm -f "$obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"

    if [ $rc -eq 0 ]; then
        printf "PASS\n"
        pass=$((pass + 1))
    else
        printf "FAIL (exit %d)\n" "$rc"
        echo "$output" | sed 's/^/  /'
        fail=$((fail + 1))
    fi
}

run_mixed()
{
    asm_src="$1"
    c_src="$2"
    name="$(basename "$asm_src" .S)"
    asm_obj="${TMPDIR}/${name}_asm.o"
    elf="${TMPDIR}/${name}.elf"
    xfile="${TMPDIR}/${name}.x"

    printf "%-30s " "${name} (mixed)..."

    if ! "$VASM" -Felf -o "$asm_obj" -I "$ASM_INC" "$asm_src" >/dev/null 2>"${TMPDIR}/${name}.err"; then
        printf "ASSEMBLE ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$asm_obj" "${TMPDIR}/${name}.err"
        return
    fi

    if ! "$CC" -O2 -nostartfiles -o "$elf" "$c_src" "$asm_obj" 2>>"${TMPDIR}/${name}.err"; then
        printf "LINK ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$asm_obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    if ! "$ELF2X68K" "$elf" "$xfile" 2>/dev/null; then
        printf "ELF2X68K ERROR\n"
        error=$((error + 1))
        rm -f "$asm_obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"
        return
    fi

    output=$("$RUN68" "$xfile" 2>&1)
    rc=$?
    rm -f "$asm_obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"

    if [ $rc -eq 0 ]; then
        printf "PASS\n"
        pass=$((pass + 1))
    else
        printf "FAIL (exit %d)\n" "$rc"
        echo "$output" | sed 's/^/  /'
        fail=$((fail + 1))
    fi
}

run_debug_standalone()
{
    src="$1"
    name="$(basename "$src" .S)"
    obj="${TMPDIR}/${name}.o"
    elf="${TMPDIR}/${name}.elf"
    xfile="${TMPDIR}/${name}.x"

    printf "%-30s " "${name} (debug)..."

    # Assemble with DWARF2 debug info
    if ! "$VASM" -Felf -dwarf=2 -o "$obj" -I "$ASM_INC" "$src" >/dev/null 2>"${TMPDIR}/${name}.err"; then
        printf "ASSEMBLE ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$obj" "${TMPDIR}/${name}.err"
        return
    fi

    if ! "$CC" -nostartfiles -o "$elf" "$obj" 2>>"${TMPDIR}/${name}.err"; then
        printf "LINK ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    # Verify DWARF sections survive linking
    sections=$("$READELF" -S "$elf" 2>/dev/null)
    ok=true
    for sect in .debug_info .debug_line .debug_abbrev; do
        if ! echo "$sections" | grep -q "$sect"; then
            printf "FAIL (missing %s)\n" "$sect"
            fail=$((fail + 1))
            ok=false
            break
        fi
    done

    if $ok; then
        # Verify GDB can read source file name from debug info
        gdb_out=$("$GDB" -batch -ex "file $elf" -ex "info sources" 2>&1)
        if echo "$gdb_out" | grep -q "$(basename "$src")"; then
            # Verify GDB can decode line numbers
            gdb_lines=$("$GDB" -batch -ex "file $elf" -ex "info line _start" 2>&1)
            if echo "$gdb_lines" | grep -q "starts at address"; then
                # Also verify it runs correctly
                if ! "$ELF2X68K" "$elf" "$xfile" 2>/dev/null; then
                    printf "ELF2X68K ERROR\n"
                    error=$((error + 1))
                    ok=false
                else
                    output=$("$RUN68" "$xfile" 2>&1)
                    rc=$?
                    if [ $rc -eq 0 ]; then
                        printf "PASS\n"
                        pass=$((pass + 1))
                    else
                        printf "FAIL (exit %d)\n" "$rc"
                        echo "$output" | sed 's/^/  /'
                        fail=$((fail + 1))
                    fi
                fi
            else
                printf "FAIL (GDB can't decode line numbers)\n"
                fail=$((fail + 1))
            fi
        else
            printf "FAIL (GDB can't find source file)\n"
            fail=$((fail + 1))
        fi
    fi

    rm -f "$obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"
}

run_debug_mixed()
{
    asm_src="$1"
    c_src="$2"
    name="$(basename "$asm_src" .S)"
    asm_obj="${TMPDIR}/${name}_asm.o"
    elf="${TMPDIR}/${name}.elf"
    xfile="${TMPDIR}/${name}.x"

    printf "%-30s " "${name} (debug mixed)..."

    # Assemble with DWARF2 debug info
    if ! "$VASM" -Felf -dwarf=2 -o "$asm_obj" -I "$ASM_INC" "$asm_src" >/dev/null 2>"${TMPDIR}/${name}.err"; then
        printf "ASSEMBLE ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$asm_obj" "${TMPDIR}/${name}.err"
        return
    fi

    # Compile C with -g for debug info
    if ! "$CC" -g -O2 -nostartfiles -o "$elf" "$c_src" "$asm_obj" 2>>"${TMPDIR}/${name}.err"; then
        printf "LINK ERROR\n"
        cat "${TMPDIR}/${name}.err"
        error=$((error + 1))
        rm -f "$asm_obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    # Verify both compilation units appear in GDB
    gdb_out=$("$GDB" -batch -ex "file $elf" -ex "info sources" 2>&1)
    asm_base="$(basename "$asm_src")"
    c_base="$(basename "$c_src")"
    if ! echo "$gdb_out" | grep -q "$asm_base"; then
        printf "FAIL (GDB missing asm source %s)\n" "$asm_base"
        fail=$((fail + 1))
        rm -f "$asm_obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi
    if ! echo "$gdb_out" | grep -q "$c_base"; then
        printf "FAIL (GDB missing C source %s)\n" "$c_base"
        fail=$((fail + 1))
        rm -f "$asm_obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    # Verify GDB can list source from both CUs
    gdb_list=$("$GDB" -batch -ex "file $elf" -ex "list _start" 2>&1)
    if ! echo "$gdb_list" | grep -q "_start"; then
        printf "FAIL (GDB can't list C source)\n"
        fail=$((fail + 1))
        rm -f "$asm_obj" "$elf" "${TMPDIR}/${name}.err"
        return
    fi

    # Verify it runs correctly
    if ! "$ELF2X68K" "$elf" "$xfile" 2>/dev/null; then
        printf "ELF2X68K ERROR\n"
        error=$((error + 1))
        rm -f "$asm_obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"
        return
    fi

    output=$("$RUN68" "$xfile" 2>&1)
    rc=$?
    rm -f "$asm_obj" "$elf" "$xfile" "${TMPDIR}/${name}.err"

    if [ $rc -eq 0 ]; then
        printf "PASS\n"
        pass=$((pass + 1))
    else
        printf "FAIL (exit %d)\n" "$rc"
        echo "$output" | sed 's/^/  /'
        fail=$((fail + 1))
    fi
}

echo "=== vasm assembly tests ==="

# Standalone .S tests (no matching .c file)
for src in "${DIR}"/*.S; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .S)"
    if [ -f "${DIR}/${name}.c" ]; then
        continue
    fi
    run_standalone "$src"
done

# Mixed .S + .c tests (matching filenames)
for src in "${DIR}"/*.S; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .S)"
    if [ -f "${DIR}/${name}.c" ]; then
        run_mixed "$src" "${DIR}/${name}.c"
    fi
done

# Debug standalone tests (debug_*.S without matching .c)
for src in "${DIR}"/debug_*.S; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .S)"
    if [ -f "${DIR}/${name}.c" ]; then
        continue
    fi
    run_debug_standalone "$src"
done

# Debug mixed tests (debug_*.S with matching .c)
for src in "${DIR}"/debug_*.S; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .S)"
    if [ -f "${DIR}/${name}.c" ]; then
        run_debug_mixed "$src" "${DIR}/${name}.c"
    fi
done

total=$((pass + fail + error))
printf "\n%d tests: %d pass, %d fail, %d error\n" "$total" "$pass" "$fail" "$error"

[ $fail -eq 0 ] && [ $error -eq 0 ]
