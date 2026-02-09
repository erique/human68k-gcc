// Test struct passing, returning, and layout
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

struct Point
{
    int x;
    int y;
};

struct Small
{
    char a;
    char b;
};

struct Mixed
{
    char tag;
    int value;
    char name[8];
};

static struct Point make_point(int x, int y)
{
    struct Point p;
    p.x = x;
    p.y = y;
    return p;
}

static int point_sum(struct Point p)
{
    return p.x + p.y;
}

static struct Small swap_small(struct Small s)
{
    struct Small r;
    r.a = s.b;
    r.b = s.a;
    return r;
}

int main(void)
{
    // struct return
    struct Point p = make_point(10, 20);
    check("struct return .x", p.x == 10);
    check("struct return .y", p.y == 20);

    // struct pass by value
    check("struct pass by value", point_sum(p) == 30);

    // small struct
    struct Small s = { 'A', 'Z' };
    struct Small r = swap_small(s);
    check("small struct swap .a", r.a == 'Z');
    check("small struct swap .b", r.b == 'A');

    // struct with mixed types
    struct Mixed m;
    m.tag = 'T';
    m.value = 42;
    strcpy(m.name, "test");
    check("mixed struct .tag", m.tag == 'T');
    check("mixed struct .value", m.value == 42);
    check("mixed struct .name", strcmp(m.name, "test") == 0);

    // array of structs
    struct Point pts[3] = { {1, 2}, {3, 4}, {5, 6} };
    int sum = 0;
    for (int i = 0; i < 3; i++)
        sum += pts[i].x + pts[i].y;
    check("array of structs sum", sum == 21);

    if (failures)
    {
        printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    printf("all tests passed\n");
    return 0;
}
