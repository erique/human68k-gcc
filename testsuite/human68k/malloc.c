// Test malloc, calloc, realloc, free
#include <stdio.h>
#include <stdlib.h>
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
    // basic malloc + free
    char* p = malloc(64);
    check("malloc returns non-null", p != NULL);
    strcpy(p, "hello");
    check("malloc memory writable", strcmp(p, "hello") == 0);
    free(p);

    // calloc zeroes memory
    int* arr = calloc(10, sizeof(int));
    check("calloc returns non-null", arr != NULL);
    int all_zero = 1;
    for (int i = 0; i < 10; i++)
    {
        if (arr[i] != 0)
            all_zero = 0;
    }
    check("calloc zeroes memory", all_zero);

    // write and verify
    for (int i = 0; i < 10; i++)
        arr[i] = i * i;
    check("calloc[3] = 9", arr[3] == 9);
    check("calloc[7] = 49", arr[7] == 49);

    // realloc
    arr = realloc(arr, 20 * sizeof(int));
    check("realloc returns non-null", arr != NULL);
    check("realloc preserves data", arr[3] == 9 && arr[7] == 49);
    free(arr);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
