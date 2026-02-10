// debug_mixed.c — test debug info from both gcc (-g) and vasm (-dwarf)
extern int add_values(int a, int b);
extern int mul_values(int a, int b);
void _dos_exit2(int) __attribute__((__noreturn__));

void _start(void)
{
    int sum = add_values(10, 20);
    int prod = mul_values(3, 7);
    _dos_exit2((sum == 30 && prod == 21) ? 0 : 1);
}
