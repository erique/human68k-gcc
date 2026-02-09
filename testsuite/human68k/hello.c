// Basic printf and puts test
#include <stdio.h>

int main(void)
{
    puts("hello from puts");
    printf("printf: %d %s %c\n", 42, "world", '!');
    printf("hex: 0x%08x\n", 0xDEADBEEF);
    return 0;
}
