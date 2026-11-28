/*
 * Model of the 1888 Sfcx filesystem code that calls the engine, transcribed
 * from the retail/checked kernel (function names and addresses are the
 * retail ones). Only the parts that matter for flash placement are here:
 * update transactions, the unit writer and its retry loop, whole-file
 * writes, deletes and the read paths. The engine entry points are called
 * exactly where the asm hooks call them on the console.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "nandsim.h"
#include "fs1888.h"

u8 *dx;

static u8 *fat_of(void) { return (u8 *)ldptr(dx + DX_FATBUF); }
static u8 *dir_of(void) { return (u8 *)ldptr(dx + DX_DIRBUF); }

/* 1888 sets free units back in its bitmap itself in a few places */
static void k_free_bit(u32 u)
{
    u8 *w = dx + DX_FREEMAP + (u >> 5) * 4;
    st32(w, ld32(w) | (1u << (31 - (u & 31))));
    st16(dx + DX_FREECOUNT, ld16(dx + DX_FREECOUNT) + 1);
}

void fs_init(void)
{
    /* every mount is a fresh boot: new device extension, no engine context */
    dx = (u8 *)mmap32(DX_SIZE + 64);
    st32(dx + DX_BBMODE, 1);
    st16(dx + DX_TOTAL, 0x400);
    st16(dx + DX_USABLE, 0x400);
    st32(dx + DX_VOLSIZE, 0x400 << 14);
    stptr(dx + DX_FCBS_RO, dx + DX_FCBS_RO);
    stptr(dx + DX_FCBS_RO + 4, dx + DX_FCBS_RO);
    stptr(dx + DX_FCBS_WO, dx + DX_FCBS_WO);
    stptr(dx + DX_FCBS_WO + 4, dx + DX_FCBS_WO);
}

s32 fs_mount(void)
{
    fs_init();
    return bb_mount(dx);
}

/* SfcxReadRootDirectoryFlashBlock (0x80072DA0) into dir/fat */
static s32 read_root(u8 *dir, u8 *fat)
{
    u32 phys = bb_xlate(dx, ld16(dx + DX_FILETAB + FT_UNIT)); /* SfcxTranslateLogicalFlashBlock hook */
    u32 i;
    u8 sp[16];
    for (i = 0; i < 31; i++) {
        u8 *dst = (i & 1) ? dir + (i >> 1) * 512 : fat + (i >> 1) * 512;
        s32 r = plat_read(dx, (phys << 14) + i * 512, dst, sp, 1);
        if (r)
            return ST_IO_ERROR;
    }
    for (i = 0; i < ld16(dx + DX_USABLE); i++)
        st16(fat + i * 2, ld16(fat + i * 2) & 0x1FFF);
    return ST_OK;
}

/* SfcxBeginUpdateTransaction (0x800734A8), then the bb_begin_post hook */
s32 fs_begin(void)
{
    u32 depth = ld32(dx + DX_TXDEPTH);
    s32 r;
    u8 *buf;
    if (depth) {
        st32(dx + DX_TXDEPTH, depth + 1);
        return bb_begin_post(dx, ST_OK);
    }
    if (!ld32(dx + DX_FILETAB + FT_SEQ))
        return (s32)0xC000014F; /* no root */
    st8(dx + DX_CANCELLED, 0);
    st8(dx + DX_DIRTY, 0);
    buf = (u8 *)mmap32(0x8000);
    stptr(dx + DX_DIRBUF, buf);
    stptr(dx + DX_FATBUF, buf + 0x2000);
    stptr(dx + DX_DATABUF, buf + 0x4000);
    st32(dx + DX_TXDEPTH, 1);
    r = read_root(buf, buf + 0x2000);
    if (r >= 0) {
        u32 root = ld16(dx + DX_FILETAB + FT_UNIT);
        st16(dx + DX_CURSOR, root);
        st16(buf + 0x2000 + root * 2, FAT_DEAD);
    } else {
        stptr(dx + DX_DIRBUF, 0);
        stptr(dx + DX_FATBUF, 0);
        stptr(dx + DX_DATABUF, 0);
        st32(dx + DX_TXDEPTH, 0);
    }
    return bb_begin_post(dx, r);
}

typedef s32 (*unit_cb)(u8 *dx, u8 *irp, u32 unit, u32 phys);

/* SfcxFindAvailableLogicalFlashBlock: the allocator hook, then 0x1FFD */
static s32 find_logical(u32 hint)
{
    s32 u = bb_alloc_unit(dx, hint);
    if (u != -1)
        st16(fat_of() + u * 2, FAT_ALLOC);
    return u;
}

/* SfcxWriteLogicalFlashBlock (0x80072C50) */
static s32 write_logical(u32 hint, unit_cb cb, s32 *out)
{
    u8 *fat = fat_of();
    s32 u = find_logical(hint), r = ST_DISK_FULL;
    for (*out = u; u != -1; *out = u) {
        u8 phys[4];
        r = bb_erase_unit(dx, 0, (u32)u, phys); /* SfcxEraseLogicalFlashBlock hook */
        if (r >= 0) {
            r = cb(dx, 0, (u32)u, ld32(phys));
            if (r >= 0)
                break;
        }
        if (r == ST_BAD_BLOCK) {
            st16(fat + u * 2, FAT_FREE);
            k_free_bit((u32)u);
        } else if (r != (s32)0xC0051101) {
            st16(fat + u * 2, FAT_FREE);
            k_free_bit((u32)u);
            break;
        } else {
            st16(fat + u * 2, 0x1FFC);
        }
        u = find_logical(hint);
    }
    if (u == -1)
        return ST_DISK_FULL;
    return r;
}

/* SfcxEndUpdateTransaction (0x80073310), then the bb_end_post hook */
s32 fs_end(void)
{
    u32 depth = ld32(dx + DX_TXDEPTH) - 1, u;
    s32 r;
    u8 *fat;
    st32(dx + DX_TXDEPTH, depth);
    if (depth)
        return bb_end_post(dx, ST_OK);
    fat = fat_of();
    if (ld8(dx + DX_CANCELLED)) {
        r = (s32)0xC0000120;
        goto rollback;
    }
    if (ld8(dx + DX_DIRTY)) {
        s32 root;
        r = write_logical(ld16(dx + DX_CURSOR), bb_write_root, &root);
        if (r >= 0) {
            for (u = 0; u < ld16(dx + DX_TOTAL); u++)
                if (ld16(fat + u * 2) == FAT_DEAD)
                    k_free_bit(u);
            goto done;
        }
        goto rollback;
    }
    r = ST_OK;
    goto done;
rollback:
    for (u = 0; u < ld16(dx + DX_TOTAL); u++) {
        u32 e = ld16(fat + u * 2);
        if ((e & 0x8000) && e != FAT_DEAD)
            k_free_bit(u);
    }
done:
    munmap(ldptr(dx + DX_DIRBUF), 0x8000);
    stptr(dx + DX_DIRBUF, 0);
    stptr(dx + DX_FATBUF, 0);
    stptr(dx + DX_DATABUF, 0);
    return bb_end_post(dx, r);
}

/* SfcxFreeFileAllocationTableChain (0x800735E0) */
static void free_chain(u32 u)
{
    u8 *fat = fat_of();
    while (u != FAT_END && u <= ld16(dx + DX_USABLE)) {
        u32 e = ld16(fat + u * 2), nv;
        if (e & 0x8000) {
            nv = FAT_FREE;
            k_free_bit(u);
        } else {
            nv = FAT_DEAD;
        }
        st16(fat + u * 2, nv);
        u = e & 0x1FFF;
    }
}

static u8 *find_entry(u8 *dir, const char *name)
{
    u32 off;
    for (off = 0; off < 15 * 512; off += 32) {
        if (dir[off] == 0)
            break;
        if (dir[off] == 5)
            continue;
        if (!strncmp((const char *)dir + off, name, 22))
            return dir + off;
    }
    return 0;
}

static u8 *new_entry(u8 *dir, const char *name)
{
    u32 off;
    for (off = 0; off < 15 * 512; off += 32)
        if (dir[off] == 0 || dir[off] == 5) {
            memset(dir + off, 0, 32);
            strncpy((char *)dir + off, name, 22);
            st16(dir + off + 22, FAT_END);
            return dir + off;
        }
    return 0;
}

/* create or replace a file: CreateWriteOnlyAccessFile + the FsdWrite
   append path (0x80074BD8) for every 16KB, then cleanup -> End */
s32 fs_write_file(const char *name, const u8 *data, u32 len)
{
    s32 r = fs_begin();
    u8 *dir, *fat, *ent;
    u32 off, prev = FAT_END;
    if (r < 0)
        return r;
    dir = dir_of();
    fat = fat_of();
    ent = find_entry(dir, name);
    if (ent) {
        free_chain(ld16(ent + 22));
        st16(ent + 22, FAT_END);
        st32(ent + 24, 0);
    } else if (!(ent = new_entry(dir, name))) {
        st8(dx + DX_CANCELLED, 1);
        fs_end();
        return ST_DISK_FULL;
    }
    st8(dx + DX_DIRTY, 1);
    for (off = 0; off < len; off += 0x4000) {
        u32 n = len - off > 0x4000 ? 0x4000 : len - off;
        u8 *db = (u8 *)ldptr(dx + DX_DATABUF);
        s32 nu;
        memcpy(db, data + off, n);
        memset(db + n, 0, 0x4000 - n);
        r = write_logical(ld16(dx + DX_CURSOR), bb_write_data, &nu);
        if (r < 0) {
            st8(dx + DX_CANCELLED, 1);
            fs_end();
            return r;
        }
        if (ld16(fat + nu * 2) != FAT_ALLOC) {
            fprintf(stderr, "FsdWrite trap: unit %x not 0x1FFD\n", nu);
            abort();
        }
        st16(fat + nu * 2, FAT_END | FAT_NEW);
        if (prev == FAT_END)
            st16(ent + 22, (u32)nu);
        else
            st16(fat + prev * 2, (ld16(fat + prev * 2) & 0xE000) | (u32)nu);
        prev = (u32)nu;
        st32(ent + 24, off + n);
    }
    return fs_end();
}

s32 fs_delete_file(const char *name)
{
    s32 r = fs_begin();
    u8 *ent;
    if (r < 0)
        return r;
    ent = find_entry(dir_of(), name);
    if (ent) {
        free_chain(ld16(ent + 22));
        ent[0] = 5;
        st8(dx + DX_DIRTY, 1);
    }
    return fs_end();
}

/* committed state, read the way FsdRead does: root through the cache,
   units through SfcxTranslateLogicalFlashBlock */
static u8 rd_dir[0x2000], rd_fat[0x2000];

s32 fs_load_root(void)
{
    if (!ld32(dx + DX_FILETAB + FT_SEQ))
        return (s32)0xC000014F;
    return read_root(rd_dir, rd_fat);
}

int fs_list(char names[][23], u32 *sizes, int max)
{
    u32 off;
    int n = 0;
    for (off = 0; off < 15 * 512 && n < max; off += 32) {
        if (rd_dir[off] == 0)
            break;
        if (rd_dir[off] == 5)
            continue;
        memcpy(names[n], rd_dir + off, 22);
        names[n][22] = 0;
        sizes[n] = ld32(rd_dir + off + 24);
        n++;
    }
    return n;
}

s32 fs_read_file(const char *name, u8 *out, u32 *len)
{
    u8 *ent = find_entry(rd_dir, name);
    u32 size, u, off;
    u8 sp[8 * 16];
    if (!ent)
        return (s32)0xC0000034;
    size = ld32(ent + 24);
    u = ld16(ent + 22);
    for (off = 0; off < size; off += 0x4000) {
        u32 phys, i;
        if (u >= ld16(dx + DX_USABLE))
            return (s32)0xC0000032;
        phys = bb_xlate(dx, u);
        for (i = 0; i < 4; i++) {
            u8 tmp[4096];
            s32 r = plat_read(dx, (phys << 14) + i * 4096, tmp, sp, 8);
            u32 o = off + i * 4096, n;
            if (r)
                return ST_IO_ERROR;
            if (o >= size)
                break;
            n = size - o > 4096 ? 4096 : size - o;
            memcpy(out + o, tmp, n);
        }
        u = ld16(rd_fat + u * 2) & 0x1FFF;
    }
    *len = size;
    return ST_OK;
}

/* SfcxWriteMobileFile hook with a mobile FCB and an IRP */
s32 fs_mobile_write(u32 k, const u8 *data, u32 size)
{
    u8 *fcb = (u8 *)mmap32(64), *irp = (u8 *)mmap32(64), *ub = (u8 *)mmap32(0x4000);
    s32 r;
    st8(fcb + FCB_MOBILE, 1);
    st8(fcb + FCB_MOBIX, k);
    if (data)
        memcpy(ub, data, size & 0x7FFF);
    stptr(irp + IRP_UBUF, ub);
    r = bb_write_mobile(dx, irp, fcb, size);
    if (r >= 0 && ld32(irp + IRP_INFO) != (size & 0x7FFF)) {
        fprintf(stderr, "mobile write: IoStatus.Information wrong\n");
        abort();
    }
    munmap(fcb, 64);
    munmap(irp, 64);
    munmap(ub, 0x4000);
    return r;
}

/* mobile read like SfcxStartNextAsyncRead: unit + page from DX_FILETAB */
s32 fs_mobile_read(u32 k, u8 *out, u32 *size)
{
    u8 *e = dx + DX_FILETAB + k * FT_SIZEOF;
    u32 sz = ld16(e + FT_SIZE), page = ld8(e + FT_PAGE), phys, n, i;
    if (!ld32(e + FT_SEQ) || (sz & 0x8000))
        return (s32)0xC0000034;
    if (page * 512 + sz > 0x4000) {
        fprintf(stderr, "mobile %u crosses its 16KB unit (page %u size %x)\n", k, page, sz);
        abort();
    }
    phys = bb_xlate(dx, ld16(e + FT_UNIT));
    n = (sz + 511) >> 9;
    for (i = 0; i < n; i++) {
        u8 tmp[512], sp[16];
        if (plat_read(dx, (phys << 14) + (page + i) * 512, tmp, sp, 1))
            return ST_IO_ERROR;
        memcpy(out + i * 512, tmp, sz - i * 512 > 512 ? 512 : sz - i * 512);
    }
    *size = sz;
    return ST_OK;
}

/* first unit of a file in the committed directory (after fs_load_root) */
s32 fs_entry_start(const char *name)
{
    u8 *ent = find_entry(rd_dir, name);
    return ent ? (s32)ld16(ent + 22) : -1;
}

/* open a read FCB on a file (CreateReadOnlyAccessFile) */
u8 *fs_open_ro(const char *name)
{
    u8 *ent = find_entry(rd_dir, name), *fcb, *h = dx + DX_FCBS_RO;
    if (!ent)
        return 0;
    fcb = (u8 *)mmap32(64);
    st32(fcb + FCB_SIZE, ld32(ent + 24));
    st16(fcb + FCB_FIRST, ld16(ent + 22));
    stptr(fcb + 4, h);
    stptr(fcb, ldptr(h));
    stptr((u8 *)ldptr(h) + 4, fcb);
    stptr(h, fcb);
    return fcb;
}
