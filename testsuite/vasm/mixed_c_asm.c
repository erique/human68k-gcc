// mixed_c_asm.c — test calling vasm function from C
extern int add_asm(int a, int b);

void _dos_exit2(int) __attribute__((__noreturn__));

void _start(void)
{
    int result = add_asm(17, 25);
    _dos_exit2(result == 42 ? 0 : 1);
}
