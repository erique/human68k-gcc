// Test integer and soft-float math (exercises lb1sf68.S)
#include <stdio.h>

static int failures = 0;

static void check(const char* name, int condition)
{
    if (!condition)
    {
        printf("FAIL: %s\n", name);
        failures++;
    }
}

// prevent constant folding
volatile int vi = 7;
volatile int vj = 13;
volatile long vl = 100000L;

int main(void)
{
    // integer multiply (uses __mulsi3 on 68000)
    int product = vi * vj;
    check("7 * 13 = 91", product == 91);

    // integer divide (uses __divsi3)
    int quotient = 91 / vi;
    check("91 / 7 = 13", quotient == 13);

    // integer modulo (uses __modsi3)
    int remainder = vj % vi;
    check("13 % 7 = 6", remainder == 6);

    // unsigned divide (uses __udivsi3)
    unsigned u = 1000000U;
    unsigned ud = u / (unsigned)vi;
    check("1000000 / 7 = 142857", ud == 142857);

    // 64-bit arithmetic (exercises addx/subx)
    long long a = (long long)vl * (long long)vl;
    check("100000 * 100000 = 10^10", a == 10000000000LL);

    long long b = a - 9999999999LL;
    check("10^10 - (10^10-1) = 1", b == 1);

    // soft-float double (uses __muldf3, __adddf3, etc.)
    volatile double x = 3.14159;
    volatile double y = 2.0;
    double z = x * y;
    // check approximate equality
    check("pi * 2 ~ 6.283", z > 6.28 && z < 6.29);

    double w = 1.0 / (double)vi;
    check("1/7 ~ 0.142857", w > 0.1428 && w < 0.1429);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
