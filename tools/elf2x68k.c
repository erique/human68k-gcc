// elf2x68k - Convert m68k ELF (with relocations) to Human68k X-file format
//
// Usage: elf2x68k input.elf output.x
//
// The input ELF must have been linked with -q (--emit-relocs) to preserve
// R_68K_32 relocations. The linker script should place .text at 0x0 with
// .data immediately following.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <arpa/inet.h>

// ELF structures (big-endian 32-bit m68k)

#define EI_NIDENT 16

typedef struct
{
    unsigned char e_ident[EI_NIDENT];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} Elf32_Ehdr;

typedef struct
{
    uint32_t sh_name;
    uint32_t sh_type;
    uint32_t sh_flags;
    uint32_t sh_addr;
    uint32_t sh_offset;
    uint32_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint32_t sh_addralign;
    uint32_t sh_entsize;
} Elf32_Shdr;

typedef struct
{
    uint32_t r_offset;
    uint32_t r_info;
    int32_t r_addend;
} Elf32_Rela;

typedef struct
{
    uint32_t st_name;
    uint32_t st_value;
    uint32_t st_size;
    unsigned char st_info;
    unsigned char st_other;
    uint16_t st_shndx;
} Elf32_Sym;

// ELF constants
#define ELFMAG0 0x7f
#define ELFMAG1 'E'
#define ELFMAG2 'L'
#define ELFMAG3 'F'
#define ELFCLASS32 1
#define ELFDATA2MSB 2
#define EM_68K 4
#define SHT_RELA 4
#define SHT_SYMTAB 2
#define SHT_STRTAB 3
#define SHF_ALLOC 0x2
#define SHF_EXECINSTR 0x4
#define SHF_WRITE 0x1
#define SHT_NOBITS 8
#define R_68K_32 1
#define STB_LOCAL 0
#define STB_GLOBAL 1
#define SHN_ABS 0xFFF1

#define ELF32_R_TYPE(i) ((i) & 0xff)
#define ELF32_R_SYM(i) ((i) >> 8)
#define ELF32_ST_BIND(i) ((i) >> 4)
#define ELF32_ST_TYPE(i) ((i) & 0xf)

// X-file constants
#define X_MAGIC 0x4855  // "HU"
#define X_HEADER_SIZE 0x40

// X-file symbol entry
#define X_SYM_EXTERNAL 0x00
#define X_SYM_LOCAL 0x02
#define X_SEC_TEXT 0x01
#define X_SEC_DATA 0x02
#define X_SEC_BSS 0x03

// Big-endian helpers
static uint16_t be16(uint16_t v) { return htons(v); }
static uint32_t be32(uint32_t v) { return htonl(v); }

static uint16_t read_be16(const void* p)
{
    const uint8_t* b = p;
    return (b[0] << 8) | b[1];
}

static uint32_t read_be32(const void* p)
{
    const uint8_t* b = p;
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

// Section info collected from ELF
struct SectionInfo
{
    uint32_t offset;    // file offset
    uint32_t addr;      // virtual address
    uint32_t size;      // section size
    int shndx;          // section header index
};

// Relocation entry
struct Reloc
{
    uint32_t offset;    // absolute offset in image (text_base=0)
};

static int relocCmp(const void* a, const void* b)
{
    const struct Reloc* ra = a;
    const struct Reloc* rb = b;
    if (ra->offset < rb->offset)
        return -1;
    if (ra->offset > rb->offset)
        return 1;
    return 0;
}

// Symbol entry for X-file
struct XSym
{
    uint8_t location;   // X_SYM_EXTERNAL or X_SYM_LOCAL
    uint8_t section;    // X_SEC_TEXT, X_SEC_DATA, X_SEC_BSS
    uint32_t value;     // absolute position
    const char* name;
};

static int xsymCmp(const void* a, const void* b)
{
    const struct XSym* sa = a;
    const struct XSym* sb = b;
    // sort by section, then by value
    if (sa->section != sb->section)
        return sa->section - sb->section;
    if (sa->value < sb->value)
        return -1;
    if (sa->value > sb->value)
        return 1;
    return 0;
}

int main(int argc, char* argv[])
{
    if (argc < 3)
    {
        fprintf(stderr, "Usage: %s [-s] input.elf output.x\n", argv[0]);
        fprintf(stderr, "  -s  Include symbol table\n");
        return 1;
    }

    int includeSymbols = 0;
    int argIdx = 1;

    while (argIdx < argc && argv[argIdx][0] == '-')
    {
        if (strcmp(argv[argIdx], "-s") == 0)
            includeSymbols = 1;
        else
        {
            fprintf(stderr, "Unknown option: %s\n", argv[argIdx]);
            return 1;
        }
        argIdx++;
    }

    if (argc - argIdx < 2)
    {
        fprintf(stderr, "Usage: %s [-s] input.elf output.x\n", argv[0]);
        return 1;
    }

    const char* inFile = argv[argIdx];
    const char* outFile = argv[argIdx + 1];

    // Read entire input file
    FILE* fin = fopen(inFile, "rb");
    if (!fin)
    {
        perror(inFile);
        return 1;
    }

    fseek(fin, 0, SEEK_END);
    long fileSize = ftell(fin);
    fseek(fin, 0, SEEK_SET);

    uint8_t* elf = malloc(fileSize);
    if (fread(elf, 1, fileSize, fin) != (size_t)fileSize)
    {
        fprintf(stderr, "Failed to read %s\n", inFile);
        fclose(fin);
        return 1;
    }
    fclose(fin);

    // Validate ELF header
    Elf32_Ehdr* ehdr = (Elf32_Ehdr*)elf;
    if (ehdr->e_ident[0] != ELFMAG0 || ehdr->e_ident[1] != ELFMAG1 ||
        ehdr->e_ident[2] != ELFMAG2 || ehdr->e_ident[3] != ELFMAG3)
    {
        fprintf(stderr, "Not an ELF file\n");
        return 1;
    }

    if (ehdr->e_ident[4] != ELFCLASS32 || ehdr->e_ident[5] != ELFDATA2MSB)
    {
        fprintf(stderr, "Not a 32-bit big-endian ELF\n");
        return 1;
    }

    uint16_t machine = read_be16(&ehdr->e_machine);
    if (machine != EM_68K)
    {
        fprintf(stderr, "Not an m68k ELF (machine=%u)\n", machine);
        return 1;
    }

    uint32_t entryPoint = read_be32(&ehdr->e_entry);
    uint32_t shoff = read_be32(&ehdr->e_shoff);
    uint16_t shentsize = read_be16(&ehdr->e_shentsize);
    uint16_t shnum = read_be16(&ehdr->e_shnum);
    uint16_t shstrndx = read_be16(&ehdr->e_shstrndx);

    if (shoff == 0 || shnum == 0)
    {
        fprintf(stderr, "No section headers\n");
        return 1;
    }

    // Get section header string table
    Elf32_Shdr* shdrs = (Elf32_Shdr*)(elf + shoff);
    Elf32_Shdr* shstrtab_hdr = (Elf32_Shdr*)((uint8_t*)shdrs + shstrndx * shentsize);
    const char* shstrtab = (const char*)(elf + read_be32(&shstrtab_hdr->sh_offset));

    // We need to find the combined text and data regions.
    // The linker script puts .text at address 0, .data right after.
    // We need to identify which sections are text, data, bss.

    // Strategy: scan all ALLOC sections, group by type:
    // - ALLOC+EXECINSTR = text
    // - ALLOC+WRITE (not NOBITS) = data
    // - ALLOC+NOBITS = bss

    uint32_t textStart = 0xFFFFFFFF, textEnd = 0;
    uint32_t dataStart = 0xFFFFFFFF, dataEnd = 0;
    uint32_t bssStart = 0xFFFFFFFF, bssEnd = 0;

    // Track which section indices belong to text vs data vs bss
    int* sectionType = calloc(shnum, sizeof(int));  // 0=none, 1=text, 2=data, 3=bss

    for (int i = 0; i < shnum; i++)
    {
        Elf32_Shdr* sh = (Elf32_Shdr*)((uint8_t*)shdrs + i * shentsize);
        uint32_t flags = read_be32(&sh->sh_flags);
        uint32_t type = read_be32(&sh->sh_type);
        uint32_t addr = read_be32(&sh->sh_addr);
        uint32_t size = read_be32(&sh->sh_size);
        const char* name = shstrtab + read_be32(&sh->sh_name);

        if (!(flags & SHF_ALLOC))
            continue;

        if (size == 0)
            continue;

        if (type == SHT_NOBITS)
        {
            // BSS
            sectionType[i] = 3;
            if (addr < bssStart) bssStart = addr;
            if (addr + size > bssEnd) bssEnd = addr + size;
        }
        else if (flags & SHF_EXECINSTR)
        {
            // Text
            sectionType[i] = 1;
            if (addr < textStart) textStart = addr;
            if (addr + size > textEnd) textEnd = addr + size;
        }
        else
        {
            // Data (including .rodata, .eh_frame, .ctors, .dtors, etc.)
            sectionType[i] = 2;
            if (addr < dataStart) dataStart = addr;
            if (addr + size > dataEnd) dataEnd = addr + size;
        }

        (void)name;  // for debugging
    }

    if (textStart == 0xFFFFFFFF)
    {
        fprintf(stderr, "No text section found\n");
        return 1;
    }

    uint32_t textSize = textEnd - textStart;
    uint32_t dataSize = (dataStart != 0xFFFFFFFF) ? (dataEnd - dataStart) : 0;
    uint32_t bssSize = (bssStart != 0xFFFFFFFF) ? (bssEnd - bssStart) : 0;

    fprintf(stderr, "Text: 0x%08x - 0x%08x (%u bytes)\n", textStart, textEnd, textSize);
    if (dataSize > 0)
        fprintf(stderr, "Data: 0x%08x - 0x%08x (%u bytes)\n", dataStart, dataEnd, dataSize);
    if (bssSize > 0)
        fprintf(stderr, "BSS:  0x%08x - 0x%08x (%u bytes)\n", bssStart, bssEnd, bssSize);
    fprintf(stderr, "Entry: 0x%08x\n", entryPoint);

    // Build combined text+data image
    uint32_t imageSize = textSize + dataSize;
    uint8_t* image = calloc(1, imageSize);

    for (int i = 0; i < shnum; i++)
    {
        Elf32_Shdr* sh = (Elf32_Shdr*)((uint8_t*)shdrs + i * shentsize);
        uint32_t type = read_be32(&sh->sh_type);

        if (sectionType[i] == 0 || type == SHT_NOBITS)
            continue;

        uint32_t addr = read_be32(&sh->sh_addr);
        uint32_t offset = read_be32(&sh->sh_offset);
        uint32_t size = read_be32(&sh->sh_size);

        // Place in image at the correct offset
        uint32_t imgOffset;
        if (sectionType[i] == 1)
            imgOffset = addr - textStart;
        else
            imgOffset = textSize + (addr - dataStart);

        if (imgOffset + size > imageSize)
        {
            fprintf(stderr, "Section at 0x%x size 0x%x exceeds image\n", addr, size);
            return 1;
        }

        memcpy(image + imgOffset, elf + offset, size);
    }

    // Collect R_68K_32 relocations from all RELA sections
    int numRelocs = 0;
    int maxRelocs = 1024;
    struct Reloc* relocs = malloc(maxRelocs * sizeof(struct Reloc));

    for (int i = 0; i < shnum; i++)
    {
        Elf32_Shdr* sh = (Elf32_Shdr*)((uint8_t*)shdrs + i * shentsize);
        uint32_t type = read_be32(&sh->sh_type);

        if (type != SHT_RELA)
            continue;

        uint32_t info = read_be32(&sh->sh_info);  // section this rela applies to
        if (info >= shnum)
            continue;

        // Only care about relocations in text and data sections
        int targetType = sectionType[info];
        if (targetType != 1 && targetType != 2)
            continue;

        uint32_t relaOffset = read_be32(&sh->sh_offset);
        uint32_t relaSize = read_be32(&sh->sh_size);
        uint32_t relaEntSize = read_be32(&sh->sh_entsize);

        if (relaEntSize == 0)
            relaEntSize = sizeof(Elf32_Rela);

        // Get linked symbol table for this RELA section
        uint32_t symtabIdx = read_be32(&sh->sh_link);
        Elf32_Shdr* symtabSh = NULL;
        uint32_t symOffset = 0;
        uint32_t symEntSize = sizeof(Elf32_Sym);
        if (symtabIdx < shnum)
        {
            symtabSh = (Elf32_Shdr*)((uint8_t*)shdrs + symtabIdx * shentsize);
            symOffset = read_be32(&symtabSh->sh_offset);
            uint32_t ent = read_be32(&symtabSh->sh_entsize);
            if (ent != 0)
                symEntSize = ent;
        }

        int numEntries = relaSize / relaEntSize;

        for (int j = 0; j < numEntries; j++)
        {
            Elf32_Rela* rela = (Elf32_Rela*)(elf + relaOffset + j * relaEntSize);
            uint32_t rInfo = read_be32(&rela->r_info);
            uint32_t rOffset = read_be32(&rela->r_offset);

            if (ELF32_R_TYPE(rInfo) != R_68K_32)
                continue;

            // Skip relocations referencing absolute symbols (e.g. __stack_size)
            if (symtabSh)
            {
                uint32_t symIdx = ELF32_R_SYM(rInfo);
                Elf32_Sym* sym = (Elf32_Sym*)(elf + symOffset + symIdx * symEntSize);
                uint16_t symShndx = read_be16(&sym->st_shndx);
                if (symShndx == SHN_ABS)
                    continue;
            }

            // Calculate absolute offset in the image
            uint32_t absOffset;
            if (targetType == 1)
                absOffset = rOffset;  // text section starts at 0 in image
            else
                absOffset = textSize + (rOffset - dataStart);

            if (numRelocs >= maxRelocs)
            {
                maxRelocs *= 2;
                relocs = realloc(relocs, maxRelocs * sizeof(struct Reloc));
            }
            relocs[numRelocs].offset = absOffset;
            numRelocs++;
        }
    }

    // Sort relocations by offset
    qsort(relocs, numRelocs, sizeof(struct Reloc), relocCmp);

    fprintf(stderr, "Relocations: %d\n", numRelocs);

    // Build delta-encoded relocation table
    // Max size: each reloc could be 4 bytes (long form)
    uint8_t* relBuf = malloc(numRelocs * 4 + 4);
    int relBufSize = 0;

    uint32_t lastOffset = 0;
    for (int i = 0; i < numRelocs; i++)
    {
        uint32_t delta = relocs[i].offset - lastOffset;

        if (delta == 0 && i > 0)
        {
            fprintf(stderr, "Warning: duplicate relocation at offset 0x%x\n", relocs[i].offset);
            continue;
        }

        if (delta > 0xFFFF || (delta & 0x10000))
        {
            // Long form: write as big-endian 32-bit
            // The high word will have bit 0 set (since delta > 0xFFFF,
            // the high word is >= 1, and we need bit 0 of high word set)
            // Actually: if delta fits in 32 bits and high word has bit 0 set,
            // it signals long form. We need to ensure the high word is odd.
            // Since deltas should be even (4-byte aligned relocations),
            // a delta >= 0x10000 will have the high word >= 1.
            // The original code just checks delta & 0x10000 and writes 32 bits.
            // The reader checks bit 0 of the 16-bit word to decide long/short.
            // For a 32-bit big-endian write of delta, the first 16 bits are delta>>16.
            // If delta >= 0x10000, delta>>16 >= 1. But is bit 0 of (delta>>16) set?
            // Not necessarily. E.g., delta = 0x20000 -> high word = 0x0002 (bit 0 = 0).
            // This looks like a bug in the original code. Let me re-examine...
            //
            // Actually, looking at the original more carefully:
            // Write: if (delta & 0x10000) -> PUT_LONG(delta)
            // Read:  read 16-bit word, if (word & 1) -> it's long, read another 16 bits
            //
            // For delta = 0x10000: high word = 0x0001, bit 0 = 1. OK.
            // For delta = 0x10002: high word = 0x0001, bit 0 = 1. OK.
            // For delta = 0x20000: high word = 0x0002, bit 0 = 0. BUG!
            //
            // But wait - the original code checks (delta & 0x10000), not (delta >= 0x10000).
            // If delta = 0x20000, (0x20000 & 0x10000) = 0, so it writes SHORT.
            // But 0x20000 doesn't fit in 16 bits! This would silently truncate.
            //
            // In practice, relocation deltas are rarely > 64K apart for small programs.
            // For correctness, we should use long form for any delta > 0xFFFE.
            // We'll use the 0x0001 prefix marker explicitly.

            // Use explicit long form: write 0x0001 marker + 32-bit absolute offset
            uint16_t marker = be16(0x0001);
            uint32_t absOff = be32(relocs[i].offset);
            memcpy(relBuf + relBufSize, &marker, 2);
            relBufSize += 2;
            memcpy(relBuf + relBufSize, &absOff, 4);
            relBufSize += 4;
        }
        else
        {
            // Short form: 16-bit delta (must be even, bit 0 = 0)
            uint16_t d = be16((uint16_t)delta);
            memcpy(relBuf + relBufSize, &d, 2);
            relBufSize += 2;
        }

        lastOffset = relocs[i].offset;
    }

    fprintf(stderr, "Relocation table: %d bytes\n", relBufSize);

    // Collect symbols if requested
    struct XSym* xsyms = NULL;
    int numXSyms = 0;
    int symBufSize = 0;

    if (includeSymbols)
    {
        // Find symbol table and string table
        Elf32_Shdr* symtabHdr = NULL;
        const char* strtab = NULL;

        for (int i = 0; i < shnum; i++)
        {
            Elf32_Shdr* sh = (Elf32_Shdr*)((uint8_t*)shdrs + i * shentsize);
            uint32_t type = read_be32(&sh->sh_type);

            if (type == SHT_SYMTAB)
            {
                symtabHdr = sh;
                // sh_link points to the string table
                uint32_t link = read_be32(&sh->sh_link);
                Elf32_Shdr* strHdr = (Elf32_Shdr*)((uint8_t*)shdrs + link * shentsize);
                strtab = (const char*)(elf + read_be32(&strHdr->sh_offset));
                break;
            }
        }

        if (symtabHdr && strtab)
        {
            uint32_t symOffset = read_be32(&symtabHdr->sh_offset);
            uint32_t symSize = read_be32(&symtabHdr->sh_size);
            uint32_t symEntSize = read_be32(&symtabHdr->sh_entsize);
            if (symEntSize == 0) symEntSize = sizeof(Elf32_Sym);

            int numElfSyms = symSize / symEntSize;
            xsyms = malloc(numElfSyms * sizeof(struct XSym));

            for (int i = 0; i < numElfSyms; i++)
            {
                Elf32_Sym* sym = (Elf32_Sym*)(elf + symOffset + i * symEntSize);
                uint32_t nameIdx = read_be32(&sym->st_name);
                uint32_t value = read_be32(&sym->st_value);
                uint16_t shndx = read_be16(&sym->st_shndx);
                uint8_t info = sym->st_info;

                // Skip null symbol, file symbols, section symbols
                if (nameIdx == 0)
                    continue;

                const char* name = strtab + nameIdx;
                if (name[0] == '\0')
                    continue;

                // Determine which X-file section this belongs to
                if (shndx == 0 || shndx >= shnum)
                    continue;

                int secType = sectionType[shndx];
                if (secType == 0)
                    continue;

                uint8_t bind = ELF32_ST_BIND(info);
                uint8_t type = ELF32_ST_TYPE(info);

                // Skip file and section symbols
                if (type == 4 || type == 3)  // STT_FILE, STT_SECTION
                    continue;

                xsyms[numXSyms].location = (bind == STB_GLOBAL) ? X_SYM_EXTERNAL : X_SYM_LOCAL;
                xsyms[numXSyms].section = secType;  // 1=text, 2=data, 3=bss maps directly
                xsyms[numXSyms].value = value;
                xsyms[numXSyms].name = name;
                numXSyms++;
            }

            // Sort symbols
            qsort(xsyms, numXSyms, sizeof(struct XSym), xsymCmp);

            // Calculate symbol table size
            for (int i = 0; i < numXSyms; i++)
            {
                // 2 bytes (location + section) + 4 bytes (value) + name + padding
                int nameLen = strlen(xsyms[i].name);
                int paddedLen = (nameLen + 2) & ~1;  // round up to even, with NUL
                symBufSize += 6 + paddedLen;
            }

            fprintf(stderr, "Symbols: %d (%d bytes)\n", numXSyms, symBufSize);
        }
    }

    // Write X-file
    FILE* fout = fopen(outFile, "wb");
    if (!fout)
    {
        perror(outFile);
        return 1;
    }

    // Write header (0x40 bytes)
    uint8_t header[X_HEADER_SIZE];
    memset(header, 0, X_HEADER_SIZE);

    // Magic "HU"
    header[0] = 0x48;
    header[1] = 0x55;
    // reserved1 = 0
    // loadmode = 0
    // base = 0
    // entry point
    uint32_t tmp;
    tmp = be32(entryPoint);
    memcpy(header + 8, &tmp, 4);
    // text size
    tmp = be32(textSize);
    memcpy(header + 12, &tmp, 4);
    // data size
    tmp = be32(dataSize);
    memcpy(header + 16, &tmp, 4);
    // bss size
    tmp = be32(bssSize);
    memcpy(header + 20, &tmp, 4);
    // relocation table size
    tmp = be32(relBufSize);
    memcpy(header + 24, &tmp, 4);
    // symbol table size
    tmp = be32(symBufSize);
    memcpy(header + 28, &tmp, 4);

    fwrite(header, 1, X_HEADER_SIZE, fout);

    // Write text segment
    fwrite(image, 1, textSize, fout);

    // Write data segment
    if (dataSize > 0)
        fwrite(image + textSize, 1, dataSize, fout);

    // Write relocation table
    if (relBufSize > 0)
        fwrite(relBuf, 1, relBufSize, fout);

    // Write symbol table
    if (includeSymbols && numXSyms > 0)
    {
        for (int i = 0; i < numXSyms; i++)
        {
            uint8_t symEntry[6];
            symEntry[0] = xsyms[i].location;
            symEntry[1] = xsyms[i].section;
            uint32_t val = be32(xsyms[i].value);
            memcpy(symEntry + 2, &val, 4);
            fwrite(symEntry, 1, 6, fout);

            int nameLen = strlen(xsyms[i].name);
            fwrite(xsyms[i].name, 1, nameLen, fout);

            // Pad to even boundary with NUL bytes
            int paddedLen = (nameLen + 2) & ~1;
            int padding = paddedLen - nameLen;
            uint8_t zeros[2] = {0, 0};
            fwrite(zeros, 1, padding, fout);
        }
    }

    fclose(fout);

    long outSize = X_HEADER_SIZE + imageSize + relBufSize + symBufSize;
    fprintf(stderr, "Written %s: %ld bytes (header=%d text=%u data=%u relocs=%d syms=%d)\n",
            outFile, outSize, X_HEADER_SIZE, textSize, dataSize, relBufSize, symBufSize);

    free(elf);
    free(image);
    free(relocs);
    free(relBuf);
    free(xsyms);
    free(sectionType);

    return 0;
}
