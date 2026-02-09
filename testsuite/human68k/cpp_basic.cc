// Basic C++ test: classes, new/delete, virtual functions
#include <cstdio>
#include <cstring>

static int failures = 0;
static int dtor_count = 0;

static void check(const char* name, int condition)
{
    if (!condition)
    {
        std::printf("FAIL: %s\n", name);
        failures++;
    }
}

class Base
{
public:
    int value;
    Base(int v) : value(v) {}
    virtual ~Base() { dtor_count++; }
    virtual int get() { return value; }
};

class Derived : public Base
{
public:
    int extra;
    Derived(int v, int e) : Base(v), extra(e) {}
    ~Derived() override { dtor_count++; }
    int get() override { return value + extra; }
};

template<typename T>
T add(T a, T b)
{
    return a + b;
}

int main()
{
    // new/delete
    int* p = new int(99);
    check("new int", *p == 99);
    delete p;

    // new[] / delete[]
    char* arr = new char[16];
    std::strcpy(arr, "C++ works");
    check("new[] string", std::strcmp(arr, "C++ works") == 0);
    delete[] arr;

    // virtual dispatch
    Base* b = new Derived(10, 5);
    check("virtual get()", b->get() == 15);

    dtor_count = 0;
    delete b;
    check("virtual dtor chain", dtor_count == 2);

    // templates
    check("template<int>", add(3, 4) == 7);
    check("template<long>", add(100000L, 200000L) == 300000L);

    if (failures)
    {
        std::printf("FAILED: %d test(s)\n", failures);
        return 1;
    }
    std::printf("all tests passed\n");
    return 0;
}
