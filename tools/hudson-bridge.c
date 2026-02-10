// hudson-bridge - GDB RSP to HudsonBug protocol bridge for Sharp X68000
//
// Connects to DB.X (standalone debugger) over serial or TCP and translates
// GDB Remote Serial Protocol packets to HudsonBug text commands.
//
// Usage:
//   hudson-bridge /dev/ttyS0              # serial, default GDB port 2345
//   hudson-bridge -p 2345 localhost:1234  # TCP (MAME null_modem)
//
// Then:
//   m68k-human68k-gdb hello.x -ex "target remote :2345"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <arpa/inet.h>

#define NUM_REGS       18
#define RSP_BUFSIZE    4096
#define TARGET_BUFSIZE 4096
#define MAX_BREAKPOINTS 10

// DB.X prompt character (standalone DB.X uses '-', ROM debugger uses '+')
static char promptChar = '-';

static int targetFd = -1;
static int gdbFd = -1;
static int listenFd = -1;
static int verbose = 0;

static uint32_t regs[NUM_REGS];
static int regsValid = 0;

// Breakpoint slot tracking (DB.X uses numbered slots 0-9, not addresses)
static struct
{
    uint32_t addr;
    int active;
} bpTable[MAX_BREAKPOINTS];

// Register names matching GDB m68k order: D0-D7, A0-A7, SR, PC
static const char* regNames[NUM_REGS] =
{
    "d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7",
    "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
    "sr", "pc"
};

// ---------------------------------------------------------------------------
// Hex helpers
// ---------------------------------------------------------------------------

static int hexVal(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void hexEncode(char* dst, const uint8_t* src, int len)
{
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < len; i++)
    {
        *dst++ = hex[src[i] >> 4];
        *dst++ = hex[src[i] & 0x0f];
    }
    *dst = '\0';
}

static int hexDecode(uint8_t* dst, const char* src, int maxLen)
{
    int n = 0;
    while (src[0] && src[1] && n < maxLen)
    {
        int hi = hexVal(src[0]);
        int lo = hexVal(src[1]);
        if (hi < 0 || lo < 0) break;
        dst[n++] = (hi << 4) | lo;
        src += 2;
    }
    return n;
}

static uint32_t hexToU32(const char* s)
{
    uint32_t val = 0;
    while (*s)
    {
        int h = hexVal(*s);
        if (h < 0) break;
        val = (val << 4) | h;
        s++;
    }
    return val;
}

// ---------------------------------------------------------------------------
// Target (HudsonBug) I/O
// ---------------------------------------------------------------------------

static int targetOpenSerial(const char* device)
{
    int fd = open(device, O_RDWR | O_NOCTTY);
    if (fd < 0)
    {
        perror(device);
        return -1;
    }

    struct termios tty;
    tcgetattr(fd, &tty);
    cfsetispeed(&tty, B9600);
    cfsetospeed(&tty, B9600);
    tty.c_cflag = CS8 | CREAD | CLOCAL;
    tty.c_iflag = IGNPAR;
    tty.c_oflag = 0;
    tty.c_lflag = 0;
    tty.c_cc[VMIN] = 1;
    tty.c_cc[VTIME] = 0;
    tcsetattr(fd, TCSANOW, &tty);
    tcflush(fd, TCIOFLUSH);

    return fd;
}

static int targetOpenTcp(const char* host, const char* port)
{
    struct addrinfo hints = { .ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM };
    struct addrinfo* res;

    int err = getaddrinfo(host, port, &hints, &res);
    if (err)
    {
        fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(err));
        return -1;
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0)
    {
        perror("socket");
        freeaddrinfo(res);
        return -1;
    }

    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0)
    {
        perror("connect");
        close(fd);
        freeaddrinfo(res);
        return -1;
    }

    freeaddrinfo(res);

    int flag = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
    return fd;
}

// Listen on a TCP port and accept one incoming connection (for MAME bitbanger)
static int targetListenTcp(int port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        perror("socket");
        return -1;
    }

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
    {
        perror("bind");
        close(fd);
        return -1;
    }

    if (listen(fd, 1) < 0)
    {
        perror("listen");
        close(fd);
        return -1;
    }

    fprintf(stderr, "Waiting for target connection on port %d...\n", port);

    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);
    int clientFd = accept(fd, (struct sockaddr*)&clientAddr, &addrLen);
    close(fd);

    if (clientFd < 0)
    {
        perror("accept");
        return -1;
    }

    int flag = 1;
    setsockopt(clientFd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

    fprintf(stderr, "Target connected from %s:%d\n",
            inet_ntoa(clientAddr.sin_addr), ntohs(clientAddr.sin_port));
    return clientFd;
}

static int targetOpen(const char* target)
{
    // If target contains ':', treat as host:port TCP connection
    char* colon = strrchr(target, ':');
    if (colon && colon != target)
    {
        char host[256];
        int len = colon - target;
        if (len >= (int)sizeof(host)) len = sizeof(host) - 1;
        memcpy(host, target, len);
        host[len] = '\0';
        return targetOpenTcp(host, colon + 1);
    }

    return targetOpenSerial(target);
}

static void targetSend(const char* fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (verbose)
    {
        fprintf(stderr, "-> target: ");
        for (int i = 0; i < len; i++)
        {
            if (buf[i] < 0x20)
                fprintf(stderr, "\\x%02x", (unsigned char)buf[i]);
            else
                fputc(buf[i], stderr);
        }
        fputc('\n', stderr);
    }

    int written = 0;
    while (written < len)
    {
        int n = write(targetFd, buf + written, len - written);
        if (n <= 0)
        {
            perror("target write");
            return;
        }
        written += n;
    }
}

// Read from target until we see the prompt character at start of line.
// Stores everything before the prompt into buf.
static int targetWaitPrompt(char* buf, int bufSize)
{
    int pos = 0;
    int atLineStart = 1;

    while (pos < bufSize - 1)
    {
        char c;
        int n = read(targetFd, &c, 1);
        if (n <= 0)
        {
            if (n < 0 && errno == EINTR) continue;
            fprintf(stderr, "target read error\n");
            return -1;
        }

        if (verbose)
        {
            if (c >= 0x20 || c == '\n')
                fputc(c, stderr);
            else if (c == '\r')
                {} // skip CR in verbose output
            else
                fprintf(stderr, "\\x%02x", (unsigned char)c);
        }

        if (c == promptChar && atLineStart)
        {
            buf[pos] = '\0';
            return pos;
        }

        buf[pos++] = c;
        atLineStart = (c == '\n');
    }

    buf[pos] = '\0';
    return pos;
}

// Read from target until we see delim, storing into buf
static int targetWaitDelim(char* buf, int bufSize, char delim)
{
    int pos = 0;
    while (pos < bufSize - 1)
    {
        char c;
        int n = read(targetFd, &c, 1);
        if (n <= 0)
        {
            if (n < 0 && errno == EINTR) continue;
            return -1;
        }

        if (verbose && c >= 0x20)
            fputc(c, stderr);

        if (c == delim)
        {
            buf[pos] = '\0';
            return pos;
        }
        buf[pos++] = c;
    }
    buf[pos] = '\0';
    return pos;
}

// ---------------------------------------------------------------------------
// HudsonBug commands
// ---------------------------------------------------------------------------

// Parse register dump from "x\r" command
// Format:
//   PC=00FF0D3C USP=00000000 SSP=00001FFC SR=2000 X:0  N:0  Z:0  V:0  C:0
//   D  00000000 FFFF9470 00000007 00000009  00000001 00001206 00FF00E0 00004AB9
//   A  00000CB0 00000000 00FF00E1 000012AD  00001120 00001206 00001000 00001FFC
static int hudsonFetchRegs(void)
{
    char buf[TARGET_BUFSIZE];
    targetSend("x\r");

    int len = targetWaitPrompt(buf, sizeof(buf));
    if (len < 0) return -1;

    if (verbose)
        fprintf(stderr, "\nreg dump: [%s]\n", buf);

    // DB.X 3.00 format uses "PC:" and "SR:" (colon, not equals)
    // Also handle "PC=" for ROM debugger compatibility
    char* p = strtok(buf, " \r\n");
    while (p)
    {
        if (strncmp(p, "PC:", 3) == 0 || strncmp(p, "PC=", 3) == 0)
        {
            regs[17] = hexToU32(p + 3);
        }
        else if (strncmp(p, "SR:", 3) == 0 || strncmp(p, "SR=", 3) == 0)
        {
            regs[16] = hexToU32(p + 3);
        }
        else if (p[0] == 'D' && (p[1] == ' ' || p[1] == '\0'))
        {
            for (int i = 0; i < 8; i++)
            {
                p = strtok(NULL, " \r\n");
                if (p) regs[i] = hexToU32(p);
            }
        }
        else if (p[0] == 'A' && (p[1] == ' ' || p[1] == '\0'))
        {
            for (int i = 0; i < 8; i++)
            {
                p = strtok(NULL, " \r\n");
                if (p) regs[8 + i] = hexToU32(p);
            }
        }
        p = strtok(NULL, " \r\n");
    }

    regsValid = 1;
    return 0;
}

// Set register: DB.X uses interactive mode
// Send "x REGNAME\r", wait for '=' prompt, then send value
static int hudsonStoreReg(int regNum, uint32_t val)
{
    char buf[TARGET_BUFSIZE];
    targetSend("x %s\r", regNames[regNum]);
    targetWaitDelim(buf, sizeof(buf), '=');
    targetSend("%x\r", val);
    targetWaitPrompt(buf, sizeof(buf));
    regs[regNum] = val;
    return 0;
}

// Read memory: "d START END\r" with inclusive end address
// Response: space-separated hex bytes
static int hudsonReadMem(uint32_t addr, uint8_t* data, int len)
{
    if (len == 0) return 0;

    char buf[TARGET_BUFSIZE];
    uint32_t endAddr = addr + len - 1;
    targetSend("d %x %x\r", addr, endAddr);

    int n = targetWaitPrompt(buf, sizeof(buf));
    if (n < 0) return -1;

    if (verbose)
        fprintf(stderr, "\nmem dump: [%s]\n", buf);

    // DB.X dump format:
    //   d 0 f\r\n                                         (echoed command)
    //   00000000  00FF 0540 01FF 0540 0003 B30A ...       (addr + hex words + ASCII)
    // Parse line by line, skip echo, extract 4-char hex words after address
    int pos = 0;
    char* lineSave = NULL;
    char* line = strtok_r(buf, "\r\n", &lineSave);
    while (line && pos < len)
    {
        // Skip the echoed command line (starts with "d " or "d\t")
        if (line[0] == 'd' && (line[1] == ' ' || line[1] == '\t'))
        {
            line = strtok_r(NULL, "\r\n", &lineSave);
            continue;
        }

        // Data line: "XXXXXXXX  XXXX XXXX XXXX ...  ASCII"
        // Find the first 8-char hex address, skip it, then parse 4-char words
        char* lp = line;

        // Skip leading whitespace
        while (*lp == ' ') lp++;

        // Skip 8-char address
        int addrLen = 0;
        while (hexVal(lp[addrLen]) >= 0) addrLen++;
        if (addrLen >= 6)
            lp += addrLen;

        // Parse 4-char hex words from the rest of the line
        // Stop at ASCII section (non-hex chars after the data)
        char* wordSave = NULL;
        char* wp = strtok_r(lp, " \t", &wordSave);
        while (wp && pos < len)
        {
            int wlen = strlen(wp);

            // Validate all chars are hex
            int allHex = 1;
            for (int j = 0; j < wlen; j++)
            {
                if (hexVal(wp[j]) < 0) { allHex = 0; break; }
            }

            // Only accept 4-char hex words (DB.X dumps 16-bit words)
            if (allHex && wlen == 4)
            {
                uint32_t val = hexToU32(wp);
                if (pos + 1 < len)
                {
                    data[pos++] = (val >> 8) & 0xff;
                    data[pos++] = val & 0xff;
                }
                else
                {
                    data[pos++] = (val >> 8) & 0xff;
                }
            }
            else if (!allHex)
            {
                // Hit ASCII section, stop parsing this line
                break;
            }

            wp = strtok_r(NULL, " \t", &wordSave);
        }

        line = strtok_r(NULL, "\r\n", &lineSave);
    }

    return pos;
}

// Write memory using DB.X 3.00 "ME" (memory edit) command
// Format: mel addr data  (size suffix S/W/L concatenated, no dot)
static int hudsonWriteMem(uint32_t addr, const uint8_t* data, int len)
{
    if (len == 0) return 0;

    char buf[TARGET_BUFSIZE];
    int pos = 0;

    // Handle initial odd byte to get word-aligned
    // DB.X size suffixes: S=byte, W=word, L=long (concatenated, no dot)
    if ((addr & 1) && pos < len)
    {
        targetSend("mes %x %02x\r", addr + pos, data[pos]);
        targetWaitPrompt(buf, sizeof(buf));
        pos++;
    }

    // Handle initial word to get long-aligned
    if (((addr + pos) & 2) && pos + 1 < len)
    {
        uint16_t w = ((uint16_t)data[pos] << 8) | data[pos + 1];
        targetSend("mew %x %04x\r", addr + pos, w);
        targetWaitPrompt(buf, sizeof(buf));
        pos += 2;
    }

    // Write longwords (4 bytes at a time)
    while (pos + 3 < len)
    {
        uint32_t l = ((uint32_t)data[pos] << 24) | ((uint32_t)data[pos + 1] << 16) |
                     ((uint32_t)data[pos + 2] << 8) | data[pos + 3];
        targetSend("mel %x %08x\r", addr + pos, l);
        targetWaitPrompt(buf, sizeof(buf));
        pos += 4;
    }

    // Handle remaining word
    if (pos + 1 < len)
    {
        uint16_t w = ((uint16_t)data[pos] << 8) | data[pos + 1];
        targetSend("mew %x %04x\r", addr + pos, w);
        targetWaitPrompt(buf, sizeof(buf));
        pos += 2;
    }

    // Handle remaining byte
    if (pos < len)
    {
        targetSend("mes %x %02x\r", addr + pos, data[pos]);
        targetWaitPrompt(buf, sizeof(buf));
        pos++;
    }

    return 0;
}

// Continue: DB.X "g=addr" to run from address
// Bare "g" gives "no process" without a loaded program, so always use g=PC
static int hudsonContinue(uint32_t addr)
{
    char buf[TARGET_BUFSIZE];
    regsValid = 0;
    targetSend("g=%x\r", addr);
    targetWaitPrompt(buf, sizeof(buf));
    return 0;
}

// Step: DB.X "t=addr" to trace from address
static int hudsonStep(uint32_t addr)
{
    char buf[TARGET_BUFSIZE];
    regsValid = 0;
    targetSend("t=%x\r", addr);
    targetWaitPrompt(buf, sizeof(buf));
    return 0;
}

// Set breakpoint: DB.X uses "B<slot> addr" with numbered slots 0-9
static int hudsonSetBreakpoint(uint32_t addr)
{
    // Find free slot
    int slot = -1;
    for (int i = 0; i < MAX_BREAKPOINTS; i++)
    {
        if (!bpTable[i].active)
        {
            slot = i;
            break;
        }
    }
    if (slot < 0)
    {
        fprintf(stderr, "No free breakpoint slots\n");
        return -1;
    }

    char buf[TARGET_BUFSIZE];
    targetSend("b%d %x\r", slot, addr);
    targetWaitPrompt(buf, sizeof(buf));
    bpTable[slot].addr = addr;
    bpTable[slot].active = 1;
    return 0;
}

// Clear breakpoint: DB.X uses "BC <slot>" (by number, not address)
static int hudsonClearBreakpoint(uint32_t addr)
{
    for (int i = 0; i < MAX_BREAKPOINTS; i++)
    {
        if (bpTable[i].active && bpTable[i].addr == addr)
        {
            char buf[TARGET_BUFSIZE];
            targetSend("bc %d\r", i);
            targetWaitPrompt(buf, sizeof(buf));
            bpTable[i].active = 0;
            return 0;
        }
    }
    fprintf(stderr, "Breakpoint at %x not found\n", addr);
    return -1;
}

static int hudsonClearAllBreakpoints(void)
{
    char buf[TARGET_BUFSIZE];
    for (int i = 0; i < MAX_BREAKPOINTS; i++)
    {
        if (bpTable[i].active)
        {
            targetSend("bc %d\r", i);
            targetWaitPrompt(buf, sizeof(buf));
            bpTable[i].active = 0;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// GDB RSP framing
// ---------------------------------------------------------------------------

static int rspGetPacket(char* buf, int bufSize)
{
    // Read until we get '$'
    char c;
    for (;;)
    {
        int n = read(gdbFd, &c, 1);
        if (n <= 0) return -1;
        if (c == '$') break;
        if (c == 0x03)
        {
            // Ctrl-C interrupt
            buf[0] = 0x03;
            buf[1] = '\0';
            return 1;
        }
    }

    // Read payload until '#'
    int pos = 0;
    uint8_t csum = 0;
    while (pos < bufSize - 1)
    {
        int n = read(gdbFd, &c, 1);
        if (n <= 0) return -1;
        if (c == '#') break;
        buf[pos++] = c;
        csum += (uint8_t)c;
    }
    buf[pos] = '\0';

    // Read 2 hex checksum chars
    char csumHex[2];
    if (read(gdbFd, &csumHex[0], 1) <= 0) return -1;
    if (read(gdbFd, &csumHex[1], 1) <= 0) return -1;

    uint8_t rxCsum = (hexVal(csumHex[0]) << 4) | hexVal(csumHex[1]);
    if (rxCsum != csum)
    {
        if (verbose)
            fprintf(stderr, "RSP checksum error: got %02x, expected %02x\n", rxCsum, csum);
        (void)!write(gdbFd, "-", 1);
        return -1;
    }

    (void)!write(gdbFd, "+", 1);

    if (verbose)
        fprintf(stderr, "<- GDB: $%s#%c%c\n", buf, csumHex[0], csumHex[1]);

    return pos;
}

static void rspPutPacket(const char* data)
{
    int len = strlen(data);
    uint8_t csum = 0;
    for (int i = 0; i < len; i++)
        csum += (uint8_t)data[i];

    char pkt[RSP_BUFSIZE + 4];
    int plen = snprintf(pkt, sizeof(pkt), "$%s#%02x", data, csum);

    if (verbose)
        fprintf(stderr, "-> GDB: %s\n", pkt);

    (void)!write(gdbFd, pkt, plen);
}

// ---------------------------------------------------------------------------
// RSP packet handlers
// ---------------------------------------------------------------------------

// 'g' - read all registers
static void handleReadRegs(void)
{
    if (!regsValid)
        hudsonFetchRegs();

    // 18 regs × 8 hex chars = 144
    char buf[256];
    char* p = buf;
    for (int i = 0; i < NUM_REGS; i++)
    {
        // GDB expects big-endian hex for m68k
        uint8_t bytes[4];
        bytes[0] = (regs[i] >> 24) & 0xff;
        bytes[1] = (regs[i] >> 16) & 0xff;
        bytes[2] = (regs[i] >> 8) & 0xff;
        bytes[3] = regs[i] & 0xff;
        hexEncode(p, bytes, 4);
        p += 8;
    }
    *p = '\0';
    rspPutPacket(buf);
}

// 'G XXXX...' - write all registers
static void handleWriteRegs(const char* data)
{
    if (!regsValid)
        hudsonFetchRegs();

    for (int i = 0; i < NUM_REGS; i++)
    {
        uint8_t bytes[4];
        hexDecode(bytes, data + i * 8, 4);
        uint32_t val = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                       ((uint32_t)bytes[2] << 8) | bytes[3];
        if (val != regs[i])
            hudsonStoreReg(i, val);
    }
    rspPutPacket("OK");
}

// 'p N' - read single register
static void handleReadReg(const char* data)
{
    unsigned int regNum = hexToU32(data);
    if (regNum >= NUM_REGS)
    {
        // FPU registers (18+): return zero rather than error
        rspPutPacket("00000000");
        return;
    }

    if (!regsValid)
        hudsonFetchRegs();

    char buf[16];
    uint8_t bytes[4];
    bytes[0] = (regs[regNum] >> 24) & 0xff;
    bytes[1] = (regs[regNum] >> 16) & 0xff;
    bytes[2] = (regs[regNum] >> 8) & 0xff;
    bytes[3] = regs[regNum] & 0xff;
    hexEncode(buf, bytes, 4);
    rspPutPacket(buf);
}

// 'P N=XXXX' - write single register
static void handleWriteReg(const char* data)
{
    char* eq = strchr(data, '=');
    if (!eq)
    {
        rspPutPacket("E01");
        return;
    }

    *eq = '\0';
    unsigned int regNum = hexToU32(data);
    if (regNum >= NUM_REGS)
    {
        rspPutPacket("E01");
        return;
    }

    uint8_t bytes[4];
    hexDecode(bytes, eq + 1, 4);
    uint32_t val = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                   ((uint32_t)bytes[2] << 8) | bytes[3];
    hudsonStoreReg(regNum, val);
    rspPutPacket("OK");
}

// 'm addr,len' - read memory
static void handleReadMem(const char* data)
{
    char* comma = strchr(data, ',');
    if (!comma)
    {
        rspPutPacket("E01");
        return;
    }

    uint32_t addr = hexToU32(data);
    uint32_t len = hexToU32(comma + 1);

    if (len > (RSP_BUFSIZE - 1) / 2)
        len = (RSP_BUFSIZE - 1) / 2;

    uint8_t memBuf[2048];
    if (len > sizeof(memBuf))
        len = sizeof(memBuf);

    int got = hudsonReadMem(addr, memBuf, len);
    if (got < 0)
    {
        rspPutPacket("E01");
        return;
    }

    char hexBuf[RSP_BUFSIZE];
    hexEncode(hexBuf, memBuf, got);
    rspPutPacket(hexBuf);
}

// 'M addr,len:XXXX' - write memory
static void handleWriteMem(const char* data)
{
    char* comma = strchr(data, ',');
    char* colon = strchr(data, ':');
    if (!comma || !colon)
    {
        rspPutPacket("E01");
        return;
    }

    uint32_t addr = hexToU32(data);
    uint32_t len = hexToU32(comma + 1);

    uint8_t memBuf[2048];
    if (len > sizeof(memBuf))
        len = sizeof(memBuf);

    hexDecode(memBuf, colon + 1, len);
    hudsonWriteMem(addr, memBuf, len);
    rspPutPacket("OK");
}

// 'c [addr]' - continue
static void handleContinue(const char* data)
{
    uint32_t addr;
    if (data[0])
    {
        addr = hexToU32(data);
    }
    else
    {
        // Use current PC
        if (!regsValid) hudsonFetchRegs();
        addr = regs[17];
    }
    hudsonContinue(addr);
    rspPutPacket("S05");
}

// 's [addr]' - single step
static void handleStep(const char* data)
{
    uint32_t addr;
    if (data[0])
    {
        addr = hexToU32(data);
    }
    else
    {
        if (!regsValid) hudsonFetchRegs();
        addr = regs[17];
    }
    hudsonStep(addr);
    rspPutPacket("S05");
}

// 'Z type,addr,kind' - set breakpoint
static void handleSetBreakpoint(const char* data)
{
    // Only support type 0 (software breakpoint)
    if (data[0] != '0')
    {
        rspPutPacket("");
        return;
    }

    char* comma1 = strchr(data, ',');
    if (!comma1)
    {
        rspPutPacket("E01");
        return;
    }

    uint32_t addr = hexToU32(comma1 + 1);
    hudsonSetBreakpoint(addr);
    rspPutPacket("OK");
}

// 'z type,addr,kind' - clear breakpoint
static void handleClearBreakpoint(const char* data)
{
    if (data[0] != '0')
    {
        rspPutPacket("");
        return;
    }

    char* comma1 = strchr(data, ',');
    if (!comma1)
    {
        rspPutPacket("E01");
        return;
    }

    uint32_t addr = hexToU32(comma1 + 1);
    hudsonClearBreakpoint(addr);
    rspPutPacket("OK");
}

// '?' - halt reason
static void handleHaltReason(void)
{
    rspPutPacket("S05");
}

// 'q...' - query packets
static void handleQuery(const char* data)
{
    if (strncmp(data, "Supported", 9) == 0)
    {
        rspPutPacket("PacketSize=4096");
    }
    else if (strcmp(data, "Attached") == 0)
    {
        rspPutPacket("1");
    }
    else if (strcmp(data, "fThreadInfo") == 0)
    {
        rspPutPacket("m1");
    }
    else if (strcmp(data, "sThreadInfo") == 0)
    {
        rspPutPacket("l");
    }
    else if (strcmp(data, "C") == 0)
    {
        rspPutPacket("QC1");
    }
    else if (strncmp(data, "Offsets", 7) == 0)
    {
        rspPutPacket("Text=0;Data=0;Bss=0");
    }
    else
    {
        rspPutPacket("");
    }
}

// 'H' - set thread (we only have one)
static void handleSetThread(const char* data)
{
    (void)data;
    rspPutPacket("OK");
}

// 'k' - kill
static void handleKill(void)
{
    hudsonClearAllBreakpoints();
}

// 'D' - detach
static void handleDetach(void)
{
    hudsonClearAllBreakpoints();
    rspPutPacket("OK");
}

// ---------------------------------------------------------------------------
// Main dispatch loop
// ---------------------------------------------------------------------------

static void dispatchLoop(void)
{
    char pkt[RSP_BUFSIZE];

    for (;;)
    {
        int len = rspGetPacket(pkt, sizeof(pkt));
        if (len < 0)
        {
            fprintf(stderr, "GDB disconnected\n");
            return;
        }

        if (len == 1 && pkt[0] == 0x03)
        {
            // Ctrl-C interrupt - target is already stopped in DB.X
            rspPutPacket("S05");
            continue;
        }

        char cmd = pkt[0];
        char* data = pkt + 1;

        switch (cmd)
        {
        case 'g': handleReadRegs(); break;
        case 'G': handleWriteRegs(data); break;
        case 'p': handleReadReg(data); break;
        case 'P': handleWriteReg(data); break;
        case 'm': handleReadMem(data); break;
        case 'M': handleWriteMem(data); break;
        case 'c': handleContinue(data); break;
        case 's': handleStep(data); break;
        case 'Z': handleSetBreakpoint(data); break;
        case 'z': handleClearBreakpoint(data); break;
        case '?': handleHaltReason(); break;
        case 'q': handleQuery(data); break;
        case 'H': handleSetThread(data); break;
        case 'k': handleKill(); return;
        case 'D': handleDetach(); return;
        default:
            // Unknown packet - empty response means unsupported
            rspPutPacket("");
            break;
        }
    }
}

// ---------------------------------------------------------------------------
// GDB listen socket
// ---------------------------------------------------------------------------

static int listenGdb(int port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        perror("socket");
        return -1;
    }

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
    {
        perror("bind");
        close(fd);
        return -1;
    }

    if (listen(fd, 1) < 0)
    {
        perror("listen");
        close(fd);
        return -1;
    }

    return fd;
}

// ---------------------------------------------------------------------------
// Usage and main
// ---------------------------------------------------------------------------

static void usage(const char* prog)
{
    fprintf(stderr, "Usage: %s [options] <target>\n", prog);
    fprintf(stderr, "       %s [options] -l PORT\n", prog);
    fprintf(stderr, "\n");
    fprintf(stderr, "  <target>  Serial device (/dev/ttyS0) or TCP host:port (localhost:1234)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -l PORT   Listen for target connection (for MAME -bitb socket.localhost:PORT)\n");
    fprintf(stderr, "  -p PORT   GDB listen port (default 2345)\n");
    fprintf(stderr, "  -P CHAR   Prompt character: '-' for DB.X (default), '+' for ROM debugger\n");
    fprintf(stderr, "  -v        Verbose (show protocol traffic on stderr)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s -l 1234 -p 2345         # listen for MAME on 1234, GDB on 2345\n", prog);
    fprintf(stderr, "  %s -p 2345 localhost:1234   # connect to target on 1234\n", prog);
    fprintf(stderr, "  %s /dev/ttyS0              # serial port, GDB on default 2345\n", prog);
    fprintf(stderr, "\n");
    fprintf(stderr, "Then: m68k-human68k-gdb hello.x -ex 'target remote :2345'\n");
}

static volatile int running = 1;

static void sigHandler(int sig)
{
    (void)sig;
    running = 0;
}

int main(int argc, char** argv)
{
    int gdbPort = 2345;
    int targetListenPort = 0;
    const char* target = NULL;

    // Parse arguments
    int i = 1;
    while (i < argc)
    {
        if (strcmp(argv[i], "-l") == 0 && i + 1 < argc)
        {
            targetListenPort = atoi(argv[++i]);
        }
        else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc)
        {
            gdbPort = atoi(argv[++i]);
        }
        else if (strcmp(argv[i], "-P") == 0 && i + 1 < argc)
        {
            promptChar = argv[++i][0];
        }
        else if (strcmp(argv[i], "-v") == 0)
        {
            verbose = 1;
        }
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)
        {
            usage(argv[0]);
            return 0;
        }
        else if (argv[i][0] != '-')
        {
            target = argv[i];
        }
        else
        {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            usage(argv[0]);
            return 1;
        }
        i++;
    }

    if (!target && !targetListenPort)
    {
        usage(argv[0]);
        return 1;
    }

    signal(SIGINT, sigHandler);
    signal(SIGPIPE, SIG_IGN);

    // Connect to target (DB.X)
    if (targetListenPort)
    {
        targetFd = targetListenTcp(targetListenPort);
    }
    else
    {
        fprintf(stderr, "Connecting to target: %s\n", target);
        targetFd = targetOpen(target);
    }
    if (targetFd < 0)
        return 1;
    fprintf(stderr, "Connected to target\n");

    // Sync with DB.X: send CR and wait for prompt, retrying until it responds
    fprintf(stderr, "Waiting for DB.X prompt '%c'...\n", promptChar);
    char buf[TARGET_BUFSIZE];
    for (;;)
    {
        targetSend("\r");

        // Use select() with 3-second timeout to avoid blocking forever
        fd_set fds;
        struct timeval tv = { .tv_sec = 3, .tv_usec = 0 };
        FD_ZERO(&fds);
        FD_SET(targetFd, &fds);
        int ready = select(targetFd + 1, &fds, NULL, NULL, &tv);
        if (ready > 0)
        {
            targetWaitPrompt(buf, sizeof(buf));
            break;
        }
        fprintf(stderr, "  (no response, retrying...)\n");
    }
    fprintf(stderr, "Got prompt, DB.X is ready\n");

    // Listen for GDB connections
    listenFd = listenGdb(gdbPort);
    if (listenFd < 0)
    {
        close(targetFd);
        return 1;
    }
    fprintf(stderr, "Listening for GDB on port %d\n", gdbPort);

    // Accept GDB connections in a loop
    while (running)
    {
        struct sockaddr_in clientAddr;
        socklen_t addrLen = sizeof(clientAddr);
        gdbFd = accept(listenFd, (struct sockaddr*)&clientAddr, &addrLen);
        if (gdbFd < 0)
        {
            if (errno == EINTR) continue;
            perror("accept");
            break;
        }

        int flag = 1;
        setsockopt(gdbFd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

        fprintf(stderr, "GDB connected from %s:%d\n",
                inet_ntoa(clientAddr.sin_addr), ntohs(clientAddr.sin_port));

        regsValid = 0;
        dispatchLoop();

        close(gdbFd);
        gdbFd = -1;
        fprintf(stderr, "GDB disconnected, waiting for new connection...\n");
    }

    close(listenFd);
    close(targetFd);
    fprintf(stderr, "Exiting\n");
    return 0;
}
