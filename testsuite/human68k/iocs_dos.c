// Test IOCS and DOS library stubs
// Exercises: _dos_curdrv, _dos_write, _iocs_romver, _iocs_b_putc
#include <stdio.h>
#include <dos.h>
#include <iocs.h>

static int failures = 0;

static void check(const char* name, int condition)
{
    if (!condition)
    {
        printf("FAIL: %s\n", name);
        failures++;
    }
    else
    {
        printf("ok: %s\n", name);
    }
}

int main(void)
{
    // DOS: _dos_curdrv returns current drive (0=A, 1=B, ...)
    int drv = _dos_curdrv();
    check("dos_curdrv returns >= 0", drv >= 0);

    // DOS: _dos_write to stdout
    const char msg[] = "hello from dos_write\n";
    int written = _dos_write(1, msg, sizeof(msg) - 1);
    check("dos_write returns byte count", written == (int)(sizeof(msg) - 1));

    // IOCS: _iocs_romver returns ROM version
    int ver = _iocs_romver();
    check("iocs_romver returns nonzero", ver != 0);

    // IOCS: _iocs_b_putc writes a character
    // (no easy way to verify output, just check it doesn't crash)
    _iocs_b_putc('*');
    _iocs_b_putc('\n');
    check("iocs_b_putc did not crash", 1);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
