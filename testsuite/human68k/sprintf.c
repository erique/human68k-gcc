// Test sprintf and string formatting
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check(const char* name, int condition)
{
    if (!condition)
    {
        printf("FAIL: %s\n", name);
        failures++;
    }
}

int main(void)
{
    char buf[128];

    sprintf(buf, "%d", 12345);
    check("sprintf decimal", strcmp(buf, "12345") == 0);

    sprintf(buf, "%x", 0xCAFE);
    check("sprintf hex", strcmp(buf, "cafe") == 0);

    sprintf(buf, "%-10s|", "left");
    check("sprintf left-align", strcmp(buf, "left      |") == 0);

    sprintf(buf, "%05d", 42);
    check("sprintf zero-pad", strcmp(buf, "00042") == 0);

    snprintf(buf, 8, "truncated string");
    check("snprintf truncates", strlen(buf) == 7);

    sprintf(buf, "%ld", 100000L);
    check("sprintf long", strcmp(buf, "100000") == 0);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
