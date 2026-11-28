/*
 * Host NAND simulator for the big block engine tests.
 *
 * 64MB system area, 128KB blocks, 2KB pages, 528-byte sectors. It enforces
 * the rules real large page NAND needs: program only erased sectors,
 * program pages of a block in ascending order, at most 4 partial programs
 * per 2KB page. ECC is computed on program like the SFC driver does and
 * checked on read. Erase/program failures and power cuts can be injected.
 */
#define _GNU_SOURCE
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "nandsim.h"

#define NBLK 512
#define SPB 256
#define SECT 528

u8 *nand;
static u8 hipage[NBLK];     /* 1 + highest programmed 2KB page */
static u8 nop[NBLK * 64];   /* partial programs per page */
static u8 prog[NBLK * SPB]; /* sector programmed since erase */
static u8 failerase[NBLK], failprog[NBLK];
long sim_ops, sim_cut_at = -1, sim_violations, sim_erases, sim_programs;
jmp_buf sim_cut_jmp;

void *mmap32(size_t n)
{
    void *p = mmap(0, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
    if (p == MAP_FAILED) {
        perror("mmap32");
        exit(1);
    }
    memset(p, 0, n);
    return p;
}

void *plat_alloc(u32 size)
{
    size_t *p = (size_t *)mmap32(size + 16);
    p[0] = size + 16;
    return p + 2;
}

void plat_free(void *q)
{
    size_t *p = (size_t *)q - 2;
    munmap(p, p[0]);
}

u32 sim_invalidations;
void plat_invalidate(u8 *dx, u32 offset, u32 length)
{
    (void)dx;
    (void)offset;
    (void)length;
    sim_invalidations++;
}

/* port of SfcxEncodeECC (retail 0x80072498) */
void ecc_encode(const u8 *data, u8 *spare)
{
    u8 buf[528];
    u32 lfsr = 0, word = 0, p = 0, bit, ecc;
    memcpy(buf, data, 512);
    memcpy(buf + 512, spare, 16);
    for (bit = 0; bit < 0x1066; bit++) {
        if ((bit & 31) == 0) {
            if (bit == 0x1000)
                p = 512;
            word = ~(buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16) | ((u32)buf[p + 3] << 24));
            p += 4;
        }
        lfsr ^= word & 1;
        word >>= 1;
        if (lfsr & 1)
            lfsr ^= 0x06954559;
        lfsr >>= 1;
    }
    ecc = ~lfsr;
    spare[12] = (u8)(((ecc << 6) & 0xC0) | (spare[12] & 0x3F));
    spare[13] = (u8)(ecc >> 2);
    spare[14] = (u8)(ecc >> 10);
    spare[15] = (u8)(ecc >> 18);
}

static void violation(const char *what, u32 sect)
{
    sim_violations++;
    fprintf(stderr, "NAND VIOLATION: %s at block %x sector %u\n", what, sect / SPB, sect % SPB);
}

void sim_load(const char *path)
{
    FILE *f = fopen(path, "rb");
    size_t n;
    if (!nand)
        nand = (u8 *)malloc((size_t)NBLK * SPB * SECT);
    memset(nand, 0xFF, (size_t)NBLK * SPB * SECT);
    if (!f) {
        perror(path);
        exit(1);
    }
    n = fread(nand, 1, (size_t)NBLK * SPB * SECT, f);
    fclose(f);
    if (n != (size_t)NBLK * SPB * SECT) {
        fprintf(stderr, "%s: expected a 64MB+spare image\n", path);
        exit(1);
    }
    sim_reset_state();
}

/* derive program state from the image: a sector counts as programmed
   unless it reads all 0xFF */
void sim_reset_state(void)
{
    u32 s, b;
    memset(nop, 0, sizeof(nop));
    memset(hipage, 0, sizeof(hipage));
    for (s = 0; s < NBLK * SPB; s++) {
        const u8 *p = nand + (size_t)s * SECT;
        u32 i, erased = 1;
        for (i = 0; i < SECT; i++)
            if (p[i] != 0xFF) {
                erased = 0;
                break;
            }
        prog[s] = !erased;
        if (!erased) {
            b = s / SPB;
            nop[b * 64 + (s % SPB) / 4]++;
            if ((s % SPB) / 4 + 1 > hipage[b])
                hipage[b] = (u8)((s % SPB) / 4 + 1);
        }
    }
    memset(failerase, 0, sizeof(failerase));
    memset(failprog, 0, sizeof(failprog));
    sim_ops = 0;
    sim_cut_at = -1;
}

void sim_fail_erase(u32 blk) { failerase[blk] = 1; }
void sim_fail_program(u32 blk) { failprog[blk] = 1; }

void sim_save(const char *path)
{
    FILE *f = fopen(path, "wb");
    fwrite(nand, 1, (size_t)NBLK * SPB * SECT, f);
    fclose(f);
}

/* snapshot/restore for power-cut tests */
struct sim_snap {
    u8 *img;
    u8 hipage[NBLK], nop[NBLK * 64], prog[NBLK * SPB];
};

void *sim_snapshot(void)
{
    struct sim_snap *s = (struct sim_snap *)malloc(sizeof(*s));
    s->img = (u8 *)malloc((size_t)NBLK * SPB * SECT);
    memcpy(s->img, nand, (size_t)NBLK * SPB * SECT);
    memcpy(s->hipage, hipage, sizeof(hipage));
    memcpy(s->nop, nop, sizeof(nop));
    memcpy(s->prog, prog, sizeof(prog));
    return s;
}

void sim_restore(void *v)
{
    struct sim_snap *s = (struct sim_snap *)v;
    memcpy(nand, s->img, (size_t)NBLK * SPB * SECT);
    memcpy(hipage, s->hipage, sizeof(hipage));
    memcpy(nop, s->nop, sizeof(nop));
    memcpy(prog, s->prog, sizeof(prog));
}

void sim_snap_free(void *v)
{
    struct sim_snap *s = (struct sim_snap *)v;
    free(s->img);
    free(s);
}

static void tick(void)
{
    sim_ops++;
    if (sim_cut_at >= 0 && sim_ops >= sim_cut_at) {
        sim_cut_at = -1;
        longjmp(sim_cut_jmp, 1);
    }
}

static int check_req(u32 addr, u32 nsect)
{
    if (addr & 511) {
        fprintf(stderr, "unaligned flash address %x\n", addr);
        abort();
    }
    if ((addr >> 9) + nsect > NBLK * SPB) {
        fprintf(stderr, "flash address %x out of range\n", addr);
        abort();
    }
    /* SfcxFsdDeviceControl: a DMA request must stay inside one 16KB unit */
    if (nsect > 1 && ((addr ^ (addr + nsect * 512 - 1)) & ~0x3FFFu)) {
        fprintf(stderr, "request %x+%u crosses a 16KB unit\n", addr, nsect);
        abort();
    }
    return 0;
}

s32 plat_read(u8 *dx, u32 addr, void *data, void *spare, u32 nsect)
{
    u32 i;
    s32 r = PLAT_OK;
    (void)dx;
    if (!data && nsect != 1)
        abort();
    if (nsect > 16)
        abort();
    check_req(addr, nsect);
    tick();
    for (i = 0; i < nsect; i++) {
        u32 s = (addr >> 9) + i;
        const u8 *p = nand + (size_t)s * SECT;
        if (data)
            memcpy((u8 *)data + i * 512, p, 512);
        if (spare)
            memcpy((u8 *)spare + i * 16, p + 512, 16);
        if (prog[s]) {
            u8 sp[16];
            memcpy(sp, p + 512, 16);
            ecc_encode(p, sp);
            if (memcmp(sp + 12, p + 512 + 12, 4))
                r = PLAT_ECC;
        }
    }
    return r;
}

s32 plat_write(u8 *dx, u32 addr, const void *data, const void *spare, u32 nsect)
{
    u32 i;
    (void)dx;
    if (nsect > 16 || !data || !spare)
        abort();
    check_req(addr, nsect);
    for (i = 0; i < nsect; i++) {
        u32 s = (addr >> 9) + i, b = s / SPB, pg = (s % SPB) / 4;
        u8 *p = nand + (size_t)s * SECT;
        tick();
        if (failprog[b])
            return PLAT_WRERR;
        if (prog[s])
            violation("program of a programmed sector", s);
        if (pg + 1 < hipage[b])
            violation("out of order page program", s);
        if (++nop[b * 64 + pg] > 4)
            violation("more than 4 partial programs in a page", s);
        memcpy(p, (const u8 *)data + i * 512, 512);
        memcpy(p + 512, (const u8 *)spare + i * 16, 16);
        ecc_encode(p, p + 512);
        prog[s] = 1;
        if (pg + 1 > hipage[b])
            hipage[b] = (u8)(pg + 1);
        sim_programs++;
    }
    return PLAT_OK;
}

s32 plat_erase(u8 *dx, u32 addr)
{
    u32 b = addr >> 17;
    (void)dx;
    if (addr & 0x1FFFF)
        abort();
    tick();
    if (failerase[b])
        return PLAT_WRERR;
    memset(nand + (size_t)b * SPB * SECT, 0xFF, (size_t)SPB * SECT);
    memset(prog + b * SPB, 0, SPB);
    memset(nop + b * 64, 0, 64);
    hipage[b] = 0;
    sim_erases++;
    return PLAT_OK;
}
