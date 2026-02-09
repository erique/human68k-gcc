// Test string and memory functions
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

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
    check("strlen empty", strlen("") == 0);
    check("strlen hello", strlen("hello") == 5);

    char buf[64];
    strcpy(buf, "abc");
    check("strcpy", strcmp(buf, "abc") == 0);

    strcat(buf, "def");
    check("strcat", strcmp(buf, "abcdef") == 0);

    check("strcmp equal", strcmp("foo", "foo") == 0);
    check("strcmp less", strcmp("abc", "abd") < 0);
    check("strcmp greater", strcmp("abd", "abc") > 0);

    strncpy(buf, "hello world", 5);
    buf[5] = '\0';
    check("strncpy", strcmp(buf, "hello") == 0);

    check("strchr found", strchr("abcdef", 'd') != NULL);
    check("strchr value", *strchr("abcdef", 'd') == 'd');
    check("strchr null", strchr("abcdef", 'z') == NULL);

    check("strrchr", *strrchr("abcabc", 'b') == 'b');
    check("strrchr pos", strrchr("abcabc", 'b') - "abcabc" == 4);

    char m[16];
    memset(m, 0x42, 8);
    m[8] = '\0';
    check("memset", m[0] == 0x42 && m[7] == 0x42);

    memcpy(m, "ABCD", 4);
    check("memcpy", m[0] == 'A' && m[3] == 'D' && m[4] == 0x42);

    check("memcmp equal", memcmp("abc", "abc", 3) == 0);
    check("memcmp differ", memcmp("abc", "abd", 3) < 0);

    char* dup = strdup("duplicate");
    check("strdup", dup != NULL && strcmp(dup, "duplicate") == 0);
    free(dup);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
