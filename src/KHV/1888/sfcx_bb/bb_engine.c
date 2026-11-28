/*
 * 1888 big block flash support: filesystem placement engine.
 *
 * 1888's Sfcx filesystem code (directory, FAT, update transactions) is
 * reused unchanged. This file decides where things live on a big block
 * part so the flash keeps the stock xeBuild/17559 layout:
 *
 *   - FS unit u lives in 128KB block base + u/8, 16KB slot u%8
 *   - new units are appended to a freshly erased block, front to back
 *   - a block is erased only when none of its units is referenced by the
 *     committed root (1888's free bitmap), so a power cut always leaves
 *     the previous root intact
 *   - the root is written last in a transaction as a type 0x2C slot with
 *     sequence + 1; mount picks the newest complete one
 *   - mobile files are an append log in one shared block, every version on
 *     a 2KB page boundary; a full log is compacted into a fresh block
 *   - fragmented blocks are coalesced at the start of a transaction
 *
 * Everything runs at PASSIVE_LEVEL with the volume lock held, except
 * bb_xlate, whose asm twin is used from the read path.
 */
#include "bb.h"

/* ---------------------------------------------------------------------- */
/* small helpers                                                           */
/* ---------------------------------------------------------------------- */
static void bb_memset(void *d, u32 v, u32 n)
{
    u8 *p = (u8 *)d;
    while (n--)
        *p++ = (u8)v;
}

static void bb_memcpy(void *d, const void *s, u32 n)
{
    u8 *p = (u8 *)d;
    const u8 *q = (const u8 *)s;
    while (n--)
        *p++ = *q++;
}

static struct bb_ctx *ctx_of(u8 *dx) { return (struct bb_ctx *)ldptr(dx + DX_CTX); }

static u32 unit_phys(const struct bb_ctx *c, u32 unit)
{
    return ((u32)c->remap[c->base + (unit >> 3)] << 3) | (unit & 7);
}

u32 bb_xlate(u8 *dx, u32 unit)
{
    struct bb_ctx *c = ctx_of(dx);
    if (!c)
        return unit;
    return unit_phys(c, unit);
}

static u32 unit_lblk(const struct bb_ctx *c, u32 unit) { return c->base + (unit >> 3); }

static int is_bad(const struct bb_ctx *c, u32 pb) { return (c->bad[pb >> 5] >> (pb & 31)) & 1; }
static void set_bad(struct bb_ctx *c, u32 pb) { c->bad[pb >> 5] |= 1u << (pb & 31); }
static int is_locked(const struct bb_ctx *c, u32 l) { return (c->locked[l >> 5] >> (l & 31)) & 1; }

/* 1888 free unit bitmap */
static int fm_test(u8 *dx, u32 u)
{
    return (ld32(dx + DX_FREEMAP + (u >> 5) * 4) >> (31 - (u & 31))) & 1;
}

static void fm_set(u8 *dx, u32 u)
{
    u8 *w = dx + DX_FREEMAP + (u >> 5) * 4;
    u32 m = 1u << (31 - (u & 31));
    if (!(ld32(w) & m)) {
        st32(w, ld32(w) | m);
        st16(dx + DX_FREECOUNT, ld16(dx + DX_FREECOUNT) + 1);
    }
}

static void fm_clear(u8 *dx, u32 u)
{
    u8 *w = dx + DX_FREEMAP + (u >> 5) * 4;
    u32 m = 1u << (31 - (u & 31));
    if (ld32(w) & m) {
        st32(w, ld32(w) & ~m);
        st16(dx + DX_FREECOUNT, ld16(dx + DX_FREECOUNT) - 1);
    }
}

static int block_free(u8 *dx, u32 b)
{
    u32 i;
    for (i = 0; i < BB_UNITS_PER_BLK; i++)
        if (!fm_test(dx, b * BB_UNITS_PER_BLK + i))
            return 0;
    return 1;
}

/* ---------------------------------------------------------------------- */
/* spare (meta type 2)                                                     */
/* ---------------------------------------------------------------------- */
static void sp_make(u8 *s, u32 lblk, u32 seq, u32 b7, u32 b8, u32 b9, u32 type)
{
    bb_memset(s, 0, 16);
    s[0] = 0xFF;
    s[1] = (u8)lblk;
    s[2] = (u8)((lblk >> 8) & 0x0F);
    s[5] = (u8)seq;
    s[3] = (u8)(seq >> 8);
    s[4] = (u8)(seq >> 16);
    s[6] = (u8)(seq >> 24);
    s[7] = (u8)b7;
    s[8] = (u8)b8;
    s[9] = (u8)b9;
    s[12] = (u8)(type & 0x3F);
}

static u32 sp_lba(const u8 *s) { return s[1] | ((u32)(s[2] & 0x0F) << 8); }
static u32 sp_seq(const u8 *s) { return s[5] | ((u32)s[3] << 8) | ((u32)s[4] << 16) | ((u32)s[6] << 24); }
static u32 sp_type(const u8 *s) { return s[12] & 0x3F; }

/* ---------------------------------------------------------------------- */
/* flash I/O                                                               */
/* ---------------------------------------------------------------------- */
static s32 rd_spare(u8 *dx, u32 addr, u8 *spare) { return plat_read(dx, addr, 0, spare, 1); }

/* nsect sectors into a 4KB aligned buffer, in 8 sector (4KB) requests */
static s32 rd_sectors(u8 *dx, u32 addr, u8 *dst, u32 nsect)
{
    u8 sp[8 * 16];
    while (nsect) {
        u32 n = nsect > 8 ? 8 : nsect;
        s32 r = plat_read(dx, addr, dst, sp, n);
        if (r)
            return r;
        addr += n * 512;
        dst += n * 512;
        nsect -= n;
    }
    return PLAT_OK;
}

/* nsect sectors that all get the same spare */
static s32 wr_sectors(u8 *dx, u32 addr, const u8 *src, const u8 *spare, u32 nsect)
{
    u8 sp[8 * 16];
    u32 i;
    for (i = 0; i < 8; i++)
        bb_memcpy(sp + i * 16, spare, 16);
    while (nsect) {
        u32 n = nsect > 8 ? 8 : nsect;
        s32 r = plat_write(dx, addr, src, sp, n);
        if (r)
            return r;
        addr += n * 512;
        src += n * 512;
        nsect -= n;
    }
    return PLAT_OK;
}

static s32 rd_unit(u8 *dx, struct bb_ctx *c, u32 unit, u8 *dst)
{
    return rd_sectors(dx, unit_phys(c, unit) << 14, dst, BB_SECT_PER_UNIT);
}

static s32 wr_unit(u8 *dx, struct bb_ctx *c, u32 unit, const u8 *src, u32 type, u32 seq)
{
    u8 sp[16];
    sp_make(sp, unit_lblk(c, unit), seq, c->geo7, c->geo8, c->geo9, type);
    return wr_sectors(dx, unit_phys(c, unit) << 14, src, sp, BB_SECT_PER_UNIT);
}

/* a program failure retires the whole 128KB block */
static void retire_block(struct bb_ctx *c, u32 lblk)
{
    set_bad(c, c->remap[lblk]);
    if (c->app_blk == lblk)
        c->app_blk = BB_NONE;
}

/* ---------------------------------------------------------------------- */
/* free block allocation                                                   */
/* ---------------------------------------------------------------------- */

/* Find a block none of whose units is in use, erase it and return its
   logical number. Blocks that fail to erase are retired. */
static u32 take_free_block(u8 *dx, struct bb_ctx *c)
{
    u32 i;
    for (i = 0; i < c->nblk; i++) {
        u32 b = (c->cursor + i) % c->nblk;
        u32 l = c->base + b;
        u32 pb = c->remap[l];
        if (l == c->mob_blk || l == c->app_blk || is_bad(c, pb))
            continue;
        if (!block_free(dx, b))
            continue;
        /* the file cache is keyed by FS offset; drop anything cached here */
        plat_invalidate(dx, b * BB_UNITS_PER_BLK * 0x4000, 0x20000);
        if (plat_erase(dx, pb << 17)) {
            set_bad(c, pb);
            continue;
        }
        c->cursor = (b + 1) % c->nblk;
        return l;
    }
    return BB_NONE;
}

/* blocks take_free_block could hand out, counting stops at max */
static u32 count_free_blocks(u8 *dx, struct bb_ctx *c, u32 max)
{
    u32 b, n = 0;
    for (b = 0; b < c->nblk && n < max; b++) {
        u32 l = c->base + b;
        if (l == c->mob_blk || l == c->app_blk || is_bad(c, c->remap[l]))
            continue;
        if (block_free(dx, b))
            n++;
    }
    return n;
}

/* erased slots left in the append block */
static u32 app_left(const struct bb_ctx *c)
{
    return c->app_blk == BB_NONE ? 0 : BB_UNITS_PER_BLK - c->app_slot;
}

/* SfcxFindAvailableFreeFlashBlock: next slot of the block this transaction
   is filling.

   Space works the way 17559 does it: every transaction writes into fresh
   blocks, starting with the live units of the block that holds the old root
   (bb_begin_post), so each commit frees that block and the volume keeps at
   least one free block at rest. No reserve is needed: a write that runs out
   of blocks fails, and its transaction is rolled back. */
s32 bb_alloc_unit(u8 *dx, u32 hint)
{
    struct bb_ctx *c = ctx_of(dx);
    u32 u;
    (void)hint;
    if (!c || !c->root_seq)
        return -1;
    if (!app_left(c)) {
        u32 l = take_free_block(dx, c);
        if (l == BB_NONE)
            return -1;
        c->app_blk = l;
        c->app_slot = 0;
    }
    u = (c->app_blk - c->base) * BB_UNITS_PER_BLK + c->app_slot++;
    if (c->app_slot >= BB_UNITS_PER_BLK)
        c->app_blk = BB_NONE; /* full: an ordinary block from now on */
    fm_clear(dx, u);
    st16(dx + DX_CURSOR, u);
    c->last_alloc = u;
    return (s32)u;
}

/* SfcxEraseLogicalFlashBlock: the slot just handed out is already erased.
   Anything else would erase a whole 128KB block, so refuse it. */
s32 bb_erase_unit(u8 *dx, u8 *irp, u32 unit, u8 *physout)
{
    struct bb_ctx *c = ctx_of(dx);
    (void)irp;
    if (!c || unit != c->last_alloc)
        return ST_WRITE_PROTECT;
    c->last_alloc = BB_NONE;
    if (physout)
        st32(physout, unit_phys(c, unit));
    return ST_OK;
}

static s32 write_result(struct bb_ctx *c, u32 unit, s32 r)
{
    if (r == PLAT_OK)
        return ST_OK;
    if (r == PLAT_WRERR) {
        retire_block(c, unit_lblk(c, unit));
        return ST_BAD_BLOCK;
    }
    return ST_IO_ERROR;
}

/* SfcxWriteFileDataFlashBlock: the 16KB in DX_DATABUF */
s32 bb_write_data(u8 *dx, u8 *irp, u32 unit, u32 phys)
{
    struct bb_ctx *c = ctx_of(dx);
    (void)irp;
    (void)phys;
    if (!c)
        return ST_IO_ERROR;
    return write_result(c, unit, wr_unit(dx, c, unit, (const u8 *)ldptr(dx + DX_DATABUF), BT_DATA, 0));
}

/* ---------------------------------------------------------------------- */
/* root directory                                                          */
/* ---------------------------------------------------------------------- */

/* Interleave FAT (even sectors) and directory (odd sectors) the way 1888
   and 17559 store the root. On flash the FAT carries no transaction flags
   and the last directory sector holds the 128KB bad block bitmap. */
static void build_root(u8 *dx, struct bb_ctx *c, u8 *img)
{
    const u8 *fat = (const u8 *)ldptr(dx + DX_FATBUF);
    const u8 *dir = (const u8 *)ldptr(dx + DX_DIRBUF);
    u32 i, j;
    for (i = 0; i < 16; i++) {
        u8 *fs = img + (2 * i) * 512;
        u8 *ds = fs + 512;
        for (j = 0; j < 256; j++) {
            u32 e = ld16(fat + (i * 256 + j) * 2);
            e = (e == FAT_DEAD) ? FAT_FREE : (e & 0x1FFF);
            st16(fs + j * 2, e);
        }
        if (i < 15) {
            bb_memcpy(ds, dir + i * 512, 512);
        } else {
            bb_memset(ds, 0, 512);
            for (j = 0; j < BB_BLOCKS / 32; j++)
                st32(ds + j * 4, c->bad[j]);
        }
    }
}

/* SfcxWriteRootDirectoryFlashBlock */
s32 bb_write_root(u8 *dx, u8 *irp, u32 unit, u32 phys)
{
    struct bb_ctx *c = ctx_of(dx);
    u32 seq;
    s32 r;
    (void)irp;
    (void)phys;
    if (!c)
        return ST_IO_ERROR;
    seq = c->root_seq + 1;
    build_root(dx, c, c->buf);
    r = write_result(c, unit, wr_unit(dx, c, unit, c->buf, BT_ROOT, seq));
    if (r == ST_OK) {
        c->root_unit = unit;
        c->root_seq = seq;
        st16(dx + DX_FILETAB + FT_UNIT, unit);
        st32(dx + DX_FILETAB + FT_SEQ, seq);
    }
    return r;
}

/* ---------------------------------------------------------------------- */
/* mobile file log                                                         */
/*                                                                         */
/* One block holds an append log of mobile file versions, each starting on */
/* a 2KB page; spare byte 9 of an entry claims how many pages are left in  */
/* the block after it. A full block is compacted into a fresh one with a   */
/* higher sequence, as in 17559 (SfcxCompactLargeMobileBlock): the latest  */
/* version of every existing file, the new entry last, all of them         */
/* claiming the fill level of the finished block. A compaction a power cut */
/* interrupts never reaches its claim, so it doesn't parse as complete and */
/* mount keeps the old block, which is released only afterwards.           */
/* ---------------------------------------------------------------------- */
static u32 mob_nsect(u32 size) { return (size == 0 || (size & 0x8000)) ? 1 : (size + 511) >> 9; }
static u32 mob_npages(u32 nsect) { return (nsect + 3) >> 2; }
static int mob_live(const struct bb_ctx *c, u32 t)
{
    return c->mob_page[t] != BB_NONE && !(c->mob_size[t] & 0x8000);
}

/* 2KB page an entry of nsect sectors would start at if appended at page p.
   Entries never cross a 16KB unit: 1888 reads a mobile file from one unit. */
static s32 mob_place(u32 p, u32 nsect)
{
    if (((p * 4) & 31) + nsect > 32)
        p = (p + 7) & ~7u;
    if (p + mob_npages(nsect) > BB_PAGES_PER_BLK)
        return -1;
    return (s32)p;
}

/* one entry; end = the page its fill claim points at (0: its own end) */
static s32 mob_put(u8 *dx, struct bb_ctx *c, u32 lblk, u32 seq, u32 page, u32 t, u32 size,
                   u32 nsect, const u8 *data, u32 end)
{
    u8 sp[16];
    if (!end)
        end = page + mob_npages(nsect);
    sp_make(sp, lblk, seq, size & 0xFF, (size >> 8) & 0xFF, BB_PAGES_PER_BLK - end, BT_MOBILE + t);
    return wr_sectors(dx, (c->remap[lblk] << 17) + page * 4 * 512, data, sp, nsect);
}

/* fill pages [from, to) with "deleted" entries of type padt */
static s32 mob_pad(u8 *dx, struct bb_ctx *c, u32 lblk, u32 seq, u32 from, u32 to, u32 padt, u32 end)
{
    while (from < to) {
        s32 r = mob_put(dx, c, lblk, seq, from, padt, 0x8000, 1, c->buf + 0x8000, end);
        if (r)
            return r;
        from++;
    }
    return PLAT_OK;
}

/* a type whose file doesn't exist, so a "deleted" entry for it changes
   nothing; -1 if every type exists */
static s32 mob_pad_type(const struct bb_ctx *c, u32 skip)
{
    s32 t;
    for (t = 9; t >= 1; t--)
        if ((u32)t != skip && !mob_live(c, (u32)t))
            return t;
    return -1;
}

static void mob_publish(u8 *dx, struct bb_ctx *c)
{
    u32 t;
    for (t = 1; t <= 9; t++) {
        u8 *e = dx + DX_FILETAB + t * FT_SIZEOF;
        bb_memset(e, 0, FT_SIZEOF);
        if (c->mob_page[t] == BB_NONE)
            continue;
        st16(e + FT_UNIT, (c->mob_blk - c->base) * BB_UNITS_PER_BLK + (c->mob_page[t] >> 5));
        st16(e + FT_SIZE, c->mob_size[t]);
        st32(e + FT_SEQ, c->mob_seq ? c->mob_seq : 1);
        st8(e + FT_PAGE, c->mob_page[t] & 31);
    }
}

/* take (1) or give back (0) the units of a log block in 1888's free map */
static void mob_reserve(u8 *dx, struct bb_ctx *c, u32 l, int take)
{
    u32 i;
    if (l == BB_NONE || is_bad(c, c->remap[l]))
        return;
    for (i = 0; i < BB_UNITS_PER_BLK; i++) {
        u32 u = (l - c->base) * BB_UNITS_PER_BLK + i;
        if (take)
            fm_clear(dx, u);
        else
            fm_set(dx, u);
    }
}

/* Compact into a fresh block: every existing file (in type order), then the
   new entry for type k. Pass 0 lays the block out and checks the old entries
   can be read, pass 1 writes it with every entry claiming the final fill. */
static s32 mob_compact(u8 *dx, struct bb_ctx *c, u32 k, u32 size, u32 nsect, const u8 *data)
{
    s32 padt = mob_pad_type(c, k);
    u8 gone[10];
    u32 tries;
    bb_memset(gone, 0, sizeof(gone));
    for (tries = 0; tries < 4; tries++) {
        u16 npage[10], nsize[10];
        u32 l = BB_NONE, seq = 0, end = 0, p = 0, t, pass;
        s32 r = PLAT_OK;
        for (t = 0; t < 10; t++)
            npage[t] = BB_NONE, nsize[t] = 0;
        for (pass = 0; pass < 2 && r == PLAT_OK; pass++) {
            if (pass) {
                end = p;
                l = take_free_block(dx, c);
                if (l == BB_NONE)
                    return ST_DISK_FULL;
                seq = ++c->mob_seq; /* unique even across failed attempts */
            }
            p = 0;
            for (t = 1; t <= 10 && r == PLAT_OK; t++) {
                u32 tt = t, sz = size, ns = nsect;
                const u8 *src = data;
                s32 pp;
                if (t == 10) {
                    tt = k;
                } else {
                    if (t == k || !mob_live(c, t))
                        continue;
                    sz = gone[t] ? 0x8000 : c->mob_size[t];
                    ns = mob_nsect(sz);
                    src = c->buf + 0x8000;
                    if (!gone[t]) {
                        if (!rd_sectors(dx, (c->remap[c->mob_blk] << 17) + c->mob_page[t] * 512, c->buf2, ns)) {
                            src = c->buf2;
                        } else if (pass) {
                            return ST_IO_ERROR;
                        } else {
                            gone[t] = 1; /* unreadable: it doesn't survive the compaction */
                            sz = 0x8000;
                            ns = 1;
                        }
                    }
                }
                pp = mob_place(p, ns);
                if (pp < 0 || ((u32)pp != p && padt < 0))
                    return ST_DISK_FULL;
                if (pass) {
                    if ((u32)pp != p)
                        r = mob_pad(dx, c, l, seq, p, (u32)pp, (u32)padt, end);
                    if (r == PLAT_OK)
                        r = mob_put(dx, c, l, seq, (u32)pp, tt, sz, ns, src, end);
                    npage[tt] = (u16)(pp * 4);
                    nsize[tt] = (u16)sz;
                }
                p = (u32)pp + mob_npages(ns);
            }
        }
        if (r == PLAT_WRERR) {
            set_bad(c, c->remap[l]);
            continue;
        }
        if (r != PLAT_OK)
            return ST_IO_ERROR;

        /* complete: switch to it, then release the old block */
        mob_reserve(dx, c, l, 1);
        mob_reserve(dx, c, c->mob_blk, 0);
        c->mob_blk = l;
        c->mob_next = p;
        for (t = 1; t <= 9; t++) {
            c->mob_page[t] = npage[t];
            c->mob_size[t] = nsize[t];
        }
        mob_publish(dx, c);
        return ST_OK;
    }
    return ST_DISK_FULL;
}

static s32 mob_append(u8 *dx, struct bb_ctx *c, u32 k, u32 size, u32 nsect, const u8 *data)
{
    if (c->mob_blk != BB_NONE) {
        s32 pp = mob_place(c->mob_next, nsect);
        s32 r = PLAT_OK, padt = mob_pad_type(c, k);
        if (pp >= 0 && ((u32)pp == c->mob_next || padt >= 0)) {
            if ((u32)pp != c->mob_next)
                r = mob_pad(dx, c, c->mob_blk, c->mob_seq, c->mob_next, (u32)pp, (u32)padt, 0);
            if (r == PLAT_OK)
                r = mob_put(dx, c, c->mob_blk, c->mob_seq, (u32)pp, k, size, nsect, data, 0);
            if (r == PLAT_OK) {
                c->mob_page[k] = (u16)(pp * 4);
                c->mob_size[k] = (u16)size;
                c->mob_next = (u32)pp + mob_npages(nsect);
                mob_publish(dx, c);
                return ST_OK;
            }
            if (r != PLAT_WRERR)
                return ST_IO_ERROR;
            /* program failure: the log moves to a new block; this one keeps
               its older entries until that compaction is complete */
            set_bad(c, c->remap[c->mob_blk]);
        }
    }
    return mob_compact(dx, c, k, size, nsect, data);
}

/* SfcxWriteMobileFile(dx, irp, fcb, size); size | 0x8000 = delete */
s32 bb_write_mobile(u8 *dx, u8 *irp, u8 *fcb, u32 size)
{
    struct bb_ctx *c = ctx_of(dx);
    u32 k = ld8(fcb + FCB_MOBIX);
    u32 nsect = mob_nsect(size);
    s32 r;
    if (!c || !c->root_seq || k < 1 || k > 9 || nsect > 32)
        return ST_INVALID;
    bb_memset(c->buf, 0, nsect * 512);
    if (!(size & 0x8000))
        bb_memcpy(c->buf, ldptr(irp + IRP_UBUF), size & 0x7FFF);
    r = mob_append(dx, c, k, size & 0xFFFF, nsect, c->buf);
    if (r < 0)
        return r;
    st32(irp + IRP_INFO, size & 0xFFFF7FFF);
    st32(fcb + FCB_SIZE, size);
    return ST_OK;
}

/* Port of SfcxInspectLargeMobileBlock: walk the log, keep the newest
   entry per type. Returns 1 if the block is a usable log. */
static int mob_parse(u8 *dx, u32 pb, const u8 *first, u16 *page, u16 *sizes, u32 *next)
{
    u8 sp[16];
    u32 blkseq = sp_seq(first), s = 0;
    u32 p = 0, span = 0, left = 0, t = 0, start = 0, size = 0;
    int ok = 0;
    bb_memcpy(sp, first, 16);
    for (;;) {
        s = sp_seq(sp);
        if (s == 0xFFFFFFFF)
            break;
        if (span == 0) {
            s32 sv = 4 * ((s32)BB_PAGES_PER_BLK - (s32)sp[9] - (s32)(p >> 2));
            if (sv <= 0 || (u32)sv > BB_SECT_PER_BLK - p)
                break;
            span = (u32)sv;
        }
        if (left == 0) {
            t = sp_type(sp);
            if (t < BT_MOBILE + 1 || t > BT_MOBILE + 9)
                break;
            start = p;
            size = sp[7] | ((u32)sp[8] << 8);
            left = mob_nsect(size);
            if (left > span)
                break;
        }
        if (s != blkseq || sp_type(sp) != t)
            break;
        left--;
        p++;
        span--;
        if (left == 0) {
            page[t - BT_MOBILE] = (u16)start;
            sizes[t - BT_MOBILE] = (u16)size;
            span &= ~3u;
            p = (p + 3) & ~3u;
        }
        if (span == 0)
            ok = 1;
        if (p >= BB_SECT_PER_BLK)
            break;
        if (rd_spare(dx, (pb << 17) + p * 512, sp))
            break;
    }
    *next = (s == 0xFFFFFFFF && span == 0) ? (p >> 2) : BB_PAGES_PER_BLK;
    return ok;
}

/* ---------------------------------------------------------------------- */
/* mount                                                                   */
/* ---------------------------------------------------------------------- */
static s32 ctx_create(u8 *dx)
{
    struct bb_ctx *c = ctx_of(dx);
    if (!c) {
        u8 *raw;
        c = (struct bb_ctx *)plat_alloc(sizeof(struct bb_ctx));
        if (!c)
            return ST_NO_MEMORY;
        bb_memset(c, 0, sizeof(*c));
        raw = (u8 *)plat_alloc(0xA000);
        if (!raw) {
            plat_free(c);
            return ST_NO_MEMORY;
        }
        c->raw = raw;
        /* buf (16KB) | buf2 (16KB) | zero page (4KB), 4KB aligned */
        c->buf = (u8 *)(((bbptr)raw + 0xFFF) & ~(bbptr)0xFFF);
        c->buf2 = c->buf + 0x4000;
        bb_memset(c->buf + 0x8000, 0, 0x1000);
        stptr(dx + DX_CTX, c);
    }
    return ST_OK;
}

/* all 32 sectors of a root slot must carry the same sequence and type */
static int root_slot_ok(u8 *dx, u32 addr, u32 seq)
{
    u8 sp[16];
    u32 i;
    for (i = 1; i < BB_SECT_PER_UNIT; i++) {
        if (rd_spare(dx, addr + i * 512, sp))
            return 0;
        if (sp_type(sp) != BT_ROOT || sp_seq(sp) != seq)
            return 0;
    }
    return 1;
}

static void dx_reset(u8 *dx)
{
    bb_memset(dx + DX_BADMAP, 0, 512);
    bb_memset(dx + DX_FREEMAP, 0, 512);
    bb_memset(dx + DX_REPLMAP, 0xFF, 256);
    bb_memset(dx + DX_FILETAB, 0, 10 * FT_SIZEOF);
    st16(dx + DX_FREECOUNT, 0);
    st16(dx + DX_CURSOR, 0);
}

/* SfcxMountVolume (the caller holds the volume lock) */
#define MAX_LOGS 16
s32 bb_mount(u8 *dx)
{
    struct bb_ctx *c;
    u8 *sp0, *fatimg;
    u32 pb, l, t, i, best = 0, have = 0, maxmob = 0, nlogs = 0;
    u32 rootl = 0, rootslot = 0;
    u8 geo[3] = { 0, 0, 0 };
    u16 log_l[MAX_LOGS];
    u32 log_seq[MAX_LOGS];
    s32 r = ctx_create(dx);
    if (r)
        return r;
    c = ctx_of(dx);
    c->root_seq = 0;
    c->mob_blk = BB_NONE;
    c->mob_seq = 0;
    c->mob_next = BB_PAGES_PER_BLK;
    c->app_blk = BB_NONE;
    c->app_slot = 0;
    c->last_alloc = BB_NONE;
    c->nfix = 0;
    for (t = 0; t < 10; t++) {
        c->mob_page[t] = BB_NONE;
        c->mob_size[t] = 0;
    }
    bb_memset(c->bad, 0, sizeof(c->bad));
    bb_memset(c->locked, 0, sizeof(c->locked));
    dx_reset(dx);

    sp0 = (u8 *)plat_alloc(BB_BLOCKS * 16);
    if (!sp0)
        return ST_NO_MEMORY;

    /* pass 1: first sector spare of every block, bad blocks */
    for (pb = 0; pb < BB_BLOCKS; pb++) {
        u8 *s = sp0 + pb * 16;
        if (rd_spare(dx, pb << 17, s))
            bb_memset(s, 0, 16); /* unreadable: not bad, but never a root/log */
        else if (s[0] != 0xFF)
            set_bad(c, pb);
    }

    /* replacement table: good blocks in the spare area stand in for the
       bad block named by their LBA (same as 17559 and the hardware) */
    for (l = 0; l < BB_BLOCKS; l++)
        c->remap[l] = (u16)l;
    for (l = 0; l < BB_USABLE; l++) {
        if (!is_bad(c, l))
            continue;
        for (pb = BB_USABLE; pb < BB_BLOCKS; pb++)
            if (!is_bad(c, pb) && sp_lba(sp0 + pb * 16) == l) {
                c->remap[l] = (u16)pb;
                break;
            }
    }

    /* pass 2: newest complete root; collect mobile logs */
    for (l = 0; l < BB_USABLE; l++) {
        u8 *s = sp0 + c->remap[l] * 16;
        u32 type = sp_type(s);
        pb = c->remap[l];
        if (is_bad(c, pb))
            continue;
        if (type == BT_DATA || type == BT_ROOT) {
            u32 slot;
            for (slot = 0; slot < BB_UNITS_PER_BLK; slot++) {
                u8 ss[16];
                u32 seq, cnt, ncfg, b7;
                s32 base;
                if (slot == 0)
                    bb_memcpy(ss, s, 16);
                else if (rd_spare(dx, (pb << 17) + (slot << 14), ss))
                    continue;
                if (sp_type(ss) != BT_ROOT)
                    continue;
                seq = sp_seq(ss);
                if (seq == 0 || seq == 0xFFFFFFFF || (have && seq < best))
                    continue;
                b7 = ss[7];
                cnt = 4 * (u32)ss[8];
                ncfg = ss[9];
                base = (s32)BB_USABLE - (s32)ncfg - (s32)cnt;
                if (!b7 || !cnt || b7 + cnt + ncfg > BB_USABLE || base < 0 || l < (u32)base ||
                    l >= (u32)base + cnt || cnt * BB_UNITS_PER_BLK > BB_MAX_UNITS)
                    continue;
                if (!root_slot_ok(dx, (pb << 17) + (slot << 14), seq))
                    continue;
                have = 1;
                best = seq;
                rootl = l;
                rootslot = slot;
                geo[0] = ss[7];
                geo[1] = ss[8];
                geo[2] = ss[9];
            }
        } else if (type > BT_MOBILE && type <= BT_MOBILE + 9) {
            u32 seq = sp_seq(s);
            if (seq == 0xFFFFFFFF)
                continue;
            if (seq > maxmob)
                maxmob = seq;
            if (nlogs < MAX_LOGS) {
                log_l[nlogs] = (u16)l;
                log_seq[nlogs] = seq;
                nlogs++;
            }
        }
    }
    if (!have) {
        plat_free(sp0);
        return ST_OK; /* no filesystem: 1888 sees a volume with no root */
    }

    c->geo7 = geo[0];
    c->geo8 = geo[1];
    c->geo9 = geo[2];
    c->nblk = (u16)(4 * (u32)geo[1]);
    c->base = (u16)(BB_USABLE - geo[2] - c->nblk);
    c->nunits = (u32)c->nblk * BB_UNITS_PER_BLK;
    c->root_unit = (rootl - c->base) * BB_UNITS_PER_BLK + rootslot;
    c->root_seq = best;
    c->cursor = 0;
    c->mob_seq = maxmob; /* new logs must outrank anything left on flash */

    /* mobile logs, newest first */
    for (i = 0; i < nlogs; i++) {
        u32 j, bi = i;
        for (j = i + 1; j < nlogs; j++)
            if (log_seq[j] > log_seq[bi])
                bi = j;
        if (bi != i) {
            u16 tl = log_l[i];
            u32 ts = log_seq[i];
            log_l[i] = log_l[bi];
            log_seq[i] = log_seq[bi];
            log_l[bi] = tl;
            log_seq[bi] = ts;
        }
    }
    /* the newest one that parses as complete, like 17559: an interrupted
       compaction never does, so the block it was copying from is used */
    for (i = 0; i < nlogs && c->mob_blk == BB_NONE; i++) {
        u16 tpage[10], tsize[10];
        u32 nx;
        l = log_l[i];
        if (l < c->base || l >= (u32)c->base + c->nblk)
            continue;
        for (t = 0; t < 10; t++)
            tpage[t] = BB_NONE, tsize[t] = 0;
        if (!mob_parse(dx, c->remap[l], sp0 + c->remap[l] * 16, tpage, tsize, &nx))
            continue;
        c->mob_blk = l;
        c->mob_next = nx;
        for (t = 0; t < 10; t++) {
            c->mob_page[t] = tpage[t];
            c->mob_size[t] = tsize[t];
        }
    }
    plat_free(sp0);

    /* the committed root: FAT for the free map, bad block bitmap */
    fatimg = c->buf;
    if (rd_unit(dx, c, c->root_unit, fatimg)) {
        c->root_seq = 0;
        return ST_OK;
    }
    for (t = 0; t < BB_BLOCKS / 32; t++)
        c->bad[t] |= ld32(fatimg + 31 * 512 + t * 4);

    st16(dx + DX_TOTAL, c->nunits);
    st16(dx + DX_RESERVED, 0);
    st16(dx + DX_USABLE, c->nunits);
    st32(dx + DX_VOLSIZE, c->nunits << 14);
    for (t = 0; t < c->nunits; t++) {
        u32 e = ld16(fatimg + (2 * (t >> 8)) * 512 + (t & 255) * 2) & 0x1FFF;
        u32 lb = unit_lblk(c, t);
        if (lb == c->mob_blk || is_bad(c, c->remap[lb]))
            continue;
        if (e == FAT_FREE || (e == FAT_ALLOC && t != c->root_unit))
            fm_set(dx, t);
    }
    st16(dx + DX_FILETAB + FT_UNIT, c->root_unit);
    st32(dx + DX_FILETAB + FT_SEQ, c->root_seq);
    mob_publish(dx, c);
    return ST_OK;
}

/* ---------------------------------------------------------------------- */
/* coalescing (start of an update transaction)                             */
/* ---------------------------------------------------------------------- */
static int fat_live(u32 e) { return e != FAT_FREE && e != FAT_DEAD; }

static u32 blk_live(const u8 *fat, u32 b)
{
    u32 i, n = 0;
    for (i = 0; i < BB_UNITS_PER_BLK; i++)
        if (fat_live(ld16(fat + (b * BB_UNITS_PER_BLK + i) * 2)))
            n++;
    return n;
}

static int name_is_locked(const u8 *ent)
{
    static const char pat[] = "sysupdate.xexp";
    u32 i;
    for (i = 0; i < 14; i++) {
        u32 ch = ent[i];
        if (ch >= 'A' && ch <= 'Z')
            ch += 32;
        if (ch != (u8)pat[i])
            return 0;
    }
    return ent[14] != 0 && ent[15] == 0; /* "sysupdate.xexp?" exactly */
}

/* 17559 never moves sysupdate.xexp? (bootloaders read it by position) */
static void mark_locked(struct bb_ctx *c, const u8 *fat, const u8 *dir)
{
    u32 off;
    bb_memset(c->locked, 0, sizeof(c->locked));
    for (off = 0; off < 15 * 512; off += 32) {
        u32 u, steps;
        if (dir[off] == 0)
            break;
        if (dir[off] == 5 || !name_is_locked(dir + off))
            continue;
        u = ld16(dir + off + 22);
        for (steps = 0; u < c->nunits && steps < c->nunits; steps++) {
            u32 l = unit_lblk(c, u);
            c->locked[l >> 5] |= 1u << (l & 31);
            u = ld16(fat + u * 2) & 0x1FFF;
        }
    }
}

static int move_unit(u8 *dx, struct bb_ctx *c, u8 *fat, u8 *dir, u32 u)
{
    u32 i, e, tries, off;
    s32 nu = -1, r = PLAT_IO;
    if (c->nfix >= BB_MAXFIX)
        return -1;
    if (rd_unit(dx, c, u, c->buf2))
        return -1; /* leave unreadable data where it is */
    for (tries = 0; tries < 4; tries++) {
        nu = bb_alloc_unit(dx, ~0u);
        if (nu < 0)
            return -1;
        c->last_alloc = BB_NONE;
        r = wr_unit(dx, c, (u32)nu, c->buf2, BT_DATA, 0);
        if (r == PLAT_OK)
            break;
        if (r != PLAT_WRERR)
            return -1;
        retire_block(c, unit_lblk(c, (u32)nu));
    }
    if (r != PLAT_OK)
        return -1;
    e = ld16(fat + u * 2);
    for (i = 0; i < c->nunits; i++) {
        u32 v = ld16(fat + i * 2);
        if ((v & 0x1FFF) == u && v != FAT_DEAD)
            st16(fat + i * 2, (v & 0xE000) | (u32)nu);
    }
    st16(fat + (u32)nu * 2, (e & 0x1FFF) | FAT_NEW);
    st16(fat + u * 2, FAT_DEAD);
    for (off = 0; off < 15 * 512; off += 32) {
        if (dir[off] == 0)
            break;
        if (dir[off] != 5 && ld16(dir + off + 22) == u)
            st16(dir + off + 22, (u32)nu);
    }
    c->fix_old[c->nfix] = (u16)u;
    c->fix_new[c->nfix] = (u16)nu;
    c->nfix++;
    return 0;
}

/* FCBs cache their first unit and one chain position; after a commit,
   point them at the units coalescing moved */
static void fix_fcbs(u8 *dx, struct bb_ctx *c, u32 head)
{
    u8 *h = dx + head;
    u8 *p = (u8 *)ldptr(h);
    u32 guard = 0;
    while (p && p != h && guard++ < 4096) {
        u32 i;
        for (i = 0; i < c->nfix; i++) {
            if (ld16(p + FCB_FIRST) == c->fix_old[i])
                st16(p + FCB_FIRST, c->fix_new[i]);
            if (ld16(p + FCB_CACHEU) == c->fix_old[i])
                st16(p + FCB_CACHEU, c->fix_new[i]);
        }
        p = (u8 *)ldptr(p + FCB_LINK);
    }
}

static void apply_fixups(u8 *dx, struct bb_ctx *c)
{
    if (c->nfix) {
        fix_fcbs(dx, c, DX_FCBS_RO);
        fix_fcbs(dx, c, DX_FCBS_WO);
    }
    c->nfix = 0;
}

/* move every live unit of block b into the block being filled */
static int move_block(u8 *dx, struct bb_ctx *c, u8 *fat, u8 *dir, u32 b)
{
    u32 i;
    for (i = 0; i < BB_UNITS_PER_BLK; i++) {
        u32 u = b * BB_UNITS_PER_BLK + i;
        if (!fat_live(ld16(fat + u * 2)))
            continue;
        if (move_unit(dx, c, fat, dir, u))
            return -1;
        st8(dx + DX_DIRTY, 1);
    }
    return 0;
}

/* SfcxCoalesceDataBlocks: emptiest block with a hole first, as long as its
   units fit with room left for this transaction's root. The blocks emptied
   are freed when the transaction commits. */
static void coalesce(u8 *dx, struct bb_ctx *c, u8 *fat, u8 *dir)
{
    for (;;) {
        u32 b, best = BB_NONE, bestn = BB_UNITS_PER_BLK;
        u32 cap = app_left(c) + BB_UNITS_PER_BLK * count_free_blocks(dx, c, BB_UNITS_PER_BLK);
        for (b = 0; b < c->nblk; b++) {
            u32 l = c->base + b, n;
            if (l == c->mob_blk || l == c->app_blk || is_bad(c, c->remap[l]) || is_locked(c, l))
                continue;
            n = blk_live(fat, b);
            if (n > 0 && n < bestn) {
                best = b;
                bestn = n;
            }
        }
        if (best == BB_NONE || bestn + 1 > cap || c->nfix + bestn > BB_MAXFIX)
            return;
        if (move_block(dx, c, fat, dir, best))
            return;
    }
}

/* after SfcxBeginUpdateTransaction loaded the root */
s32 bb_begin_post(u8 *dx, s32 status)
{
    struct bb_ctx *c = ctx_of(dx);
    u8 *fat, *dir;
    u32 u;
    if (status < 0 || !c || !c->root_seq || ld32(dx + DX_TXDEPTH) != 1)
        return status;
    fat = (u8 *)ldptr(dx + DX_FATBUF);
    dir = (u8 *)ldptr(dx + DX_DIRBUF);
    c->nfix = 0;
    /* allocations a power cut left behind (the root is already FAT_DEAD) */
    for (u = 0; u < c->nunits; u++)
        if (ld16(fat + u * 2) == FAT_ALLOC)
            st16(fat + u * 2, FAT_FREE);
    mark_locked(c, fat, dir);
    /* SfcxRestartUpdateTransaction: the transaction fills a fresh block,
       starting with the live units of the block that holds the old root, so
       the commit frees that block and never costs a free block overall */
    c->app_blk = BB_NONE;
    if (!is_locked(c, unit_lblk(c, c->root_unit)))
        move_block(dx, c, fat, dir, c->root_unit / BB_UNITS_PER_BLK);
    coalesce(dx, c, fat, dir);
    return status;
}

/* after SfcxEndUpdateTransaction */
s32 bb_end_post(u8 *dx, s32 status)
{
    struct bb_ctx *c = ctx_of(dx);
    if (!c || ld32(dx + DX_TXDEPTH) != 0)
        return status;
    if (status >= 0)
        apply_fixups(dx, c);
    c->nfix = 0;
    return status;
}
