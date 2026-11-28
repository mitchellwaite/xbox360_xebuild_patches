/*
 * Big block engine tests against a stock xeBuild big block image.
 *
 *   test_bb <64MB+spare image> [iterations] [seed]
 *
 * 1. mount and read every file; compare with an independent decode of the
 *    raw image (unit u at block base + u/8, slot u%8)
 * 2. random file replace/create/delete and mobile writes, rebooting
 *    (remounting) regularly and checking every file and mobile file
 * 3. power cuts at random points, the remount must show the old or new
 *    state of the file being written and nothing else changed
 * 4. fill the flash until disk full, free space, fill again
 * 5. a packed volume: deletes, small writes, settings writes with power
 *    cuts and remounts; a free block must always be left
 * 6. failing erase/program on blocks the allocator will pick
 * The simulator fails the run on any NAND rule violation.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nandsim.h"
#include "fs1888.h"

#define MAXF 256
#define MAXSZ (6 << 20)

static struct {
    char name[23];
    u8 *data;
    u32 len;
    int used;
} files[MAXF];
static struct {
    u8 data[0x4000];
    u32 len;
    int present;
} mob[10];

static u32 rng = 1;
static u32 rnd(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

#define CHECK(c, ...)                                                                              \
    do {                                                                                           \
        if (!(c)) {                                                                                \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);                                   \
            fprintf(stderr, __VA_ARGS__);                                                          \
            fprintf(stderr, "\n");                                                                 \
            exit(1);                                                                               \
        }                                                                                          \
    } while (0)

static u8 *tmpbuf;

static int find_file(const char *n)
{
    int i;
    for (i = 0; i < MAXF; i++)
        if (files[i].used && !strcmp(files[i].name, n))
            return i;
    return -1;
}

static void set_file(const char *n, const u8 *d, u32 len)
{
    int i = find_file(n);
    if (i < 0) {
        for (i = 0; i < MAXF && files[i].used; i++)
            ;
        CHECK(i < MAXF, "model full");
        strcpy(files[i].name, n);
        files[i].used = 1;
        files[i].data = (u8 *)malloc(MAXSZ);
    }
    memcpy(files[i].data, d, len);
    files[i].len = len;
}

static void del_file(const char *n)
{
    int i = find_file(n);
    if (i >= 0) {
        free(files[i].data);
        files[i].used = 0;
    }
}

/* every file and mobile file must match the model */
static void verify_all(const char *when)
{
    char names[MAXF][23];
    u32 sizes[MAXF];
    int n, i, k, count = 0;
    CHECK(fs_load_root() == 0, "%s: root unreadable", when);
    n = fs_list(names, sizes, MAXF);
    for (i = 0; i < n; i++) {
        int m = find_file(names[i]);
        u32 len = 0;
        CHECK(m >= 0, "%s: unexpected file %s", when, names[i]);
        CHECK(fs_read_file(names[i], tmpbuf, &len) == 0, "%s: read %s failed", when, names[i]);
        CHECK(len == files[m].len, "%s: %s size %x != %x", when, names[i], len, files[m].len);
        CHECK(!memcmp(tmpbuf, files[m].data, len), "%s: %s content differs", when, names[i]);
        count++;
    }
    for (i = 0; i < MAXF; i++)
        if (files[i].used)
            count--;
    CHECK(count == 0, "%s: files missing from the directory", when);
    for (k = 1; k <= 9; k++) {
        u32 len = 0;
        s32 r = fs_mobile_read(k, tmpbuf, &len);
        if (!mob[k].present) {
            CHECK(r < 0, "%s: mobile %d should not exist", when, k);
            continue;
        }
        CHECK(r == 0, "%s: mobile %d unreadable", when, k);
        CHECK(len == mob[k].len && !memcmp(tmpbuf, mob[k].data, len), "%s: mobile %d differs", when, k);
    }
    CHECK(sim_violations == 0, "%s: NAND rule violations", when);
}

static void reboot(const char *when)
{
    CHECK(fs_mount() == 0, "%s: mount failed", when);
    verify_all(when);
}

/* ground truth straight from the image, independent of the engine */
static void raw_check(void)
{
    char names[MAXF][23];
    u32 sizes[MAXF];
    int n, i;
    u32 base = 0x1E0 - 4 - 0x80, rootblk = 0, slot = 0, best = 0, b, s;
    /* newest type 0x2C slot */
    for (b = 0; b < 0x1E0; b++)
        for (s = 0; s < 8; s++) {
            const u8 *sp = nand + ((size_t)b * 256 + s * 32) * 528 + 512;
            u32 seq = sp[5] | (sp[3] << 8) | (sp[4] << 16) | ((u32)sp[6] << 24);
            if ((sp[12] & 0x3F) == 0x2C && seq != 0xFFFFFFFF && seq >= best && sp[0] == 0xFF) {
                best = seq;
                rootblk = b;
                slot = s;
                base = 0x1E0 - sp[9] - 4 * sp[8];
            }
        }
    CHECK(best, "raw: no root in image");
    n = fs_list(names, sizes, MAXF);
    printf("raw check: root at block %x slot %u seq %u, base %x, %d files\n", rootblk, slot, best, base, n);
    for (i = 0; i < n; i++) {
        u32 len = 0, u, off;
        const u8 *ent = 0, *rs = nand + ((size_t)rootblk * 256 + slot * 32) * 528;
        u32 o;
        CHECK(fs_read_file(names[i], tmpbuf, &len) == 0, "raw: read %s", names[i]);
        for (o = 0; o < 15; o++) {
            const u8 *ds = rs + (2 * o + 1) * 528;
            u32 e;
            for (e = 0; e < 512; e += 32)
                if (!strncmp((const char *)ds + e, names[i], 22) && ds[e] != 5)
                    ent = ds + e;
        }
        CHECK(ent, "raw: %s not in raw root", names[i]);
        u = ld16(ent + 22);
        for (off = 0; off < len; off += 0x4000) {
            const u8 *unit = nand + ((size_t)(base + u / 8) * 256 + (u % 8) * 32) * 528;
            u32 k;
            for (k = 0; k < 32 && off + k * 512 < len; k++) {
                u32 m = len - off - k * 512 > 512 ? 512 : len - off - k * 512;
                CHECK(!memcmp(unit + k * 528, tmpbuf + off + k * 512, m), "raw: %s differs at %x", names[i],
                      off + k * 512);
            }
            u = ld16(rs + (2 * (u >> 8)) * 528 + (u & 255) * 2) & 0x1FFF;
        }
        set_file(names[i], tmpbuf, len);
        if (len >= 4 && strstr(names[i], ".xex") && !strstr(names[i], ".xexp"))
            CHECK(!memcmp(tmpbuf, "XEX2", 4), "raw: %s is not XEX2", names[i]);
    }
}

static void load_mobiles(void)
{
    int k;
    for (k = 1; k <= 9; k++) {
        u32 len = 0;
        mob[k].present = fs_mobile_read(k, mob[k].data, &len) == 0;
        mob[k].len = len;
        if (mob[k].present)
            printf("mobile %c.dat: %u bytes\n", 'A' + k, len);
    }
}

static void fill_rand(u8 *p, u32 n)
{
    u32 i;
    for (i = 0; i < n; i++)
        p[i] = (u8)rnd();
}

static const int mob_ids[] = { 1, 2, 3, 5, 6, 7 };

/* one random operation; returns the status */
static s32 random_op(char *what, u8 *data, u32 *plen, char *fname, int *kind, u32 *mk)
{
    u32 r = rnd() % 100;
    if (r < 45) {
        /* mobile write (settings) */
        u32 k = mob_ids[rnd() % 6], len;
        if (rnd() % 10 == 0)
            len = 0x8000; /* delete */
        else if (rnd() % 20 == 0)
            len = 512 + rnd() % 0x3E00; /* large entry */
        else
            len = 1 + rnd() % 2048;
        if (!(len & 0x8000))
            fill_rand(data, len);
        *kind = 2;
        *mk = k;
        *plen = len;
        sprintf(what, "mobile %u len %x", k, len);
        return fs_mobile_write(k, data, len);
    }
    if (r < 85) {
        /* replace or create a file */
        static const char *targets[] = { "bootanim.xex", "launch.ini", "dashlaunch.ini", "test1.bin",
                                         "test2.bin", "xenonclatin.xtt", "hud.xex" };
        const char *n = targets[rnd() % 7];
        u32 len = rnd() % 4 == 0 ? rnd() % 0x80000 : rnd() % 0x8000;
        fill_rand(data, len);
        strcpy(fname, n);
        *kind = 1;
        *plen = len;
        sprintf(what, "write %s len %x", n, len);
        return fs_write_file(n, data, len);
    }
    {
        static const char *targets[] = { "test1.bin", "test2.bin", "launch.ini", "dashlaunch.ini" };
        const char *n = targets[rnd() % 4];
        strcpy(fname, n);
        *kind = 3;
        sprintf(what, "delete %s", n);
        return fs_delete_file(n);
    }
}

static void apply_model(int kind, const char *fname, const u8 *data, u32 len, u32 k)
{
    if (kind == 1)
        set_file(fname, data, len);
    else if (kind == 3)
        del_file(fname);
    else if (kind == 2) {
        if (len & 0x8000)
            mob[k].present = 0;
        else {
            mob[k].present = 1;
            mob[k].len = len;
            memcpy(mob[k].data, data, len);
        }
    }
}

static void test_random(int iters)
{
    int i;
    u8 *data = (u8 *)malloc(MAXSZ);
    u8 *fcb = fs_open_ro("xam.xex");
    CHECK(fcb, "open xam.xex");
    for (i = 0; i < iters; i++) {
        char what[96], fname[32];
        int kind = 0;
        u32 len = 0, k = 0;
        s32 r = random_op(what, data, &len, fname, &kind, &k);
        CHECK(r >= 0, "op %d (%s) failed %08x", i, what, (u32)r);
        apply_model(kind, fname, data, len, k);
        /* the open FCB must follow xam.xex if coalescing moved it */
        CHECK(fs_load_root() == 0, "root");
        CHECK(ld16(fcb + FCB_FIRST) == (u32)fs_entry_start("xam.xex"), "op %d (%s): open FCB is stale", i,
              what);
        if (i % 7 == 6) {
            char when[64];
            sprintf(when, "random op %d", i);
            reboot(when);
            fcb = fs_open_ro("xam.xex");
        }
    }
    reboot("after random ops");
    free(data);
    printf("random: %d ops ok, %ld programs, %ld erases\n", iters, sim_programs, sim_erases);
}

/* the read FCB on xam.xex must point at xam.xex's first unit after every
   commit, even when coalescing moved it */
static void test_fcb_fixup(void)
{
    u8 *fcb, *data = (u8 *)malloc(0x20000);
    int i, moved = 0;
    reboot("fcb test start");
    fcb = fs_open_ro("xam.xex");
    for (i = 0; i < 200; i++) {
        u32 first0 = ld16(fcb + FCB_FIRST), len = 0x4000 + (rnd() % 8) * 0x4000;
        /* rewriting the small files packed in front of xam.xex leaves its
           first block mostly dead, so coalescing moves xam.xex's units */
        static const char *victims[] = { "frag.bin", "vk.xex", "updater.xex", "signin.xex" };
        const char *n = victims[i % 4];
        fill_rand(data, len);
        CHECK(fs_write_file(n, data, len) >= 0, "frag write %s", n);
        set_file(n, data, len);
        CHECK(fs_load_root() == 0, "root");
        CHECK(ld16(fcb + FCB_FIRST) == (u32)fs_entry_start("xam.xex"), "frag %d: open FCB is stale", i);
        if (ld16(fcb + FCB_FIRST) != first0)
            moved++;
    }
    del_file("frag.bin");
    CHECK(fs_delete_file("frag.bin") >= 0, "delete frag");
    printf("fcb fixup: xam.xex first unit followed %d moves\n", moved);
    free(data);
}

static void test_power_cuts(int iters)
{
    int i, cuts = 0, newstate = 0;
    u8 *data = (u8 *)malloc(MAXSZ);
    for (i = 0; i < iters; i++) {
        char what[96], fname[32];
        int kind = 0;
        u32 len = 0, k = 0;
        long start = sim_ops;
        u32 save = rng;
        volatile int cut;
        /* measure the op on a snapshot, then cut it somewhere inside */
        void *snap = sim_snapshot();
        u32 seed_ops;
        random_op(what, data, &len, fname, &kind, &k);
        seed_ops = (u32)(sim_ops - start);
        sim_restore(snap);
        rng = save;
        reboot("before cut");
        start = sim_ops;
        /* the rerun after a reboot costs a few more ops (new erase), so the
           window reaches past the commit sometimes */
        sim_cut_at = sim_ops + 1 + rnd() % (seed_ops + 40);
        cut = 0;
        if (setjmp(sim_cut_jmp) == 0) {
            rng = save;
            random_op(what, data, &len, fname, &kind, &k);
            sim_cut_at = -1;
        } else {
            cut = 1;
            cuts++;
        }
        sim_cut_at = -1;
        CHECK(fs_mount() == 0, "mount after cut (%s)", what);
        CHECK(sim_violations == 0, "violations after cut");
        if (cut) {
            /* either the old or the new state, nothing else */
            int matched_old = 1;
            if (kind == 1 || kind == 3) {
                u32 l2 = 0;
                int m = find_file(fname);
                s32 r;
                CHECK(fs_load_root() == 0, "root after cut");
                r = fs_read_file(fname, tmpbuf, &l2);
                if (kind == 1)
                    matched_old = !(r == 0 && l2 == len && !memcmp(tmpbuf, data, len));
                else
                    matched_old = r == 0;
                if (matched_old) {
                    if (m >= 0)
                        CHECK(r == 0 && l2 == files[m].len && !memcmp(tmpbuf, files[m].data, l2),
                              "cut %d (%s): neither old nor new", i, what);
                    else
                        CHECK(r < 0, "cut %d (%s): file appeared half written", i, what);
                }
            } else if (kind == 2) {
                u32 l2 = 0;
                s32 r = fs_mobile_read(k, tmpbuf, &l2);
                int isnew = (len & 0x8000) ? r < 0 : (r == 0 && l2 == len && !memcmp(tmpbuf, data, len));
                matched_old = !isnew;
                if (matched_old)
                    CHECK(mob[k].present ? (r == 0 && l2 == mob[k].len && !memcmp(tmpbuf, mob[k].data, l2))
                                         : r < 0,
                          "cut %d (%s): mobile neither old nor new", i, what);
            }
            if (!matched_old) {
                apply_model(kind, fname, data, len, k);
                newstate++;
            }
        } else {
            apply_model(kind, fname, data, len, k);
        }
        sim_snap_free(snap);
        verify_all("after cut");
    }
    free(data);
    printf("power cuts: %d cuts in %d ops (%d landed on the new state), all consistent\n", cuts, iters,
           newstate);
}

static void test_fill(void)
{
    u8 *data = (u8 *)malloc(0x100000);
    int i, n = 0;
    s32 r = 0;
    char name[32];
    for (i = 0; i < 400; i++) {
        sprintf(name, "fill%03d.bin", i);
        fill_rand(data, 0x40000);
        r = fs_write_file(name, data, 0x40000);
        if (r < 0)
            break;
        set_file(name, data, 0x40000);
        n++;
    }
    CHECK(r == ST_DISK_FULL, "fill ended with %08x, expected disk full", (u32)r);
    printf("fill: %d x 256KB before disk full (free units %u)\n", n, ld16(dx + DX_FREECOUNT));
    reboot("after fill");
    for (i = 0; i < n; i += 2) {
        sprintf(name, "fill%03d.bin", i);
        CHECK(fs_delete_file(name) >= 0, "delete %s", name);
        del_file(name);
    }
    reboot("after deleting half");
    for (i = 0; i < n / 2; i++) {
        sprintf(name, "refill%03d.bin", i);
        fill_rand(data, 0x40000);
        r = fs_write_file(name, data, 0x40000);
        CHECK(r >= 0, "refill %d failed %08x (coalescing should have made room)", i, (u32)r);
        set_file(name, data, 0x40000);
    }
    reboot("after refill");
    for (i = 0; i < MAXF; i++)
        if (files[i].used && (!strncmp(files[i].name, "fill", 4) || !strncmp(files[i].name, "refill", 6))) {
            CHECK(fs_delete_file(files[i].name) >= 0, "cleanup %s", files[i].name);
            del_file(files[i].name);
        }
    reboot("after fill cleanup");
    free(data);
    printf("fill/refill ok\n");
}

/* blocks the allocator could still erase and use (the reserve) */
static u32 free_blocks(void)
{
    const struct bb_ctx *c = (const struct bb_ctx *)ldptr(dx + DX_CTX);
    u32 b, i, n = 0;
    for (b = 0; b < c->nblk; b++) {
        u32 l = c->base + b, pb = c->remap[l], ok = 1;
        if (l == c->mob_blk || l == c->app_blk || ((c->bad[pb >> 5] >> (pb & 31)) & 1))
            continue;
        for (i = 0; i < BB_UNITS_PER_BLK && ok; i++) {
            u32 u = b * BB_UNITS_PER_BLK + i;
            ok = (ld32(dx + DX_FREEMAP + (u >> 5) * 4) >> (31 - (u & 31))) & 1;
        }
        n += ok;
    }
    return n;
}

/* where the free units are, for failures on a full volume */
static void dump_space(void)
{
    const struct bb_ctx *c = (const struct bb_ctx *)ldptr(dx + DX_CTX);
    u32 b, i, hist[9] = { 0 };
    fprintf(stderr, "app %x slot %u, mob %x, free blocks %u, free units %u, root unit %x (blk %x)\n", c->app_blk,
            c->app_slot, c->mob_blk, free_blocks(), ld16(dx + DX_FREECOUNT), c->root_unit, c->base + c->root_unit / 8);
    for (b = 0; b < c->nblk; b++) {
        u32 n = 0, l = c->base + b;
        for (i = 0; i < BB_UNITS_PER_BLK; i++) {
            u32 u = b * BB_UNITS_PER_BLK + i;
            n += (ld32(dx + DX_FREEMAP + (u >> 5) * 4) >> (31 - (u & 31))) & 1;
        }
        hist[n]++;
        if (n && n < 8)
            fprintf(stderr, "  blk %x: %u free%s%s%s\n", l, n, l == c->mob_blk ? " (mobile)" : "",
                    l == c->app_blk ? " (append)" : "", ((c->locked[l >> 5] >> (l & 31)) & 1) ? " (locked)" : "");
    }
    for (i = 0; i <= 8; i++)
        fprintf(stderr, "  %u blocks with %u free units\n", hist[i], i);
}

/* write files of len until one doesn't fit (or max were written) */
static int pack(const char *prefix, u32 len, int *serial, u8 *data, int max)
{
    int n = 0;
    s32 r = 0;
    char name[32];
    while (n < max) {
        sprintf(name, "%s%03d.bin", prefix, (*serial)++);
        fill_rand(data, len);
        r = fs_write_file(name, data, len);
        if (r < 0)
            break;
        set_file(name, data, len);
        n++;
    }
    CHECK(n == max || r == ST_DISK_FULL, "packing ended with %08x", (u32)r);
    return n;
}

/* A settings write, cut by a power failure somewhere inside it when docut
   is set or when it compacts the log. Updates the model; returns 1 if it
   was cut, 2 if the cut was inside a compaction. */
static int mobile_write_cut(u32 k, const u8 *data, u32 len, int docut)
{
    const struct bb_ctx *c = (const struct bb_ctx *)ldptr(dx + DX_CTX);
    void *snap = sim_snapshot();
    long start = sim_ops;
    u32 ops, l2 = 0, blk0 = c->mob_blk;
    volatile int cut = 0;
    s32 r = fs_mobile_write(k, data, len);
    int isnew = 1, compacted = c->mob_blk != blk0;
    CHECK(r >= 0, "mobile %u (len %x) failed %08x on a full volume", k, len, (u32)r);
    ops = (u32)(sim_ops - start);
    if (docut || compacted) {
        sim_restore(snap);
        sim_snap_free(snap);
        reboot("before mobile cut");
        sim_cut_at = sim_ops + 1 + rnd() % (ops + 8);
        if (setjmp(sim_cut_jmp) == 0)
            fs_mobile_write(k, data, len);
        else
            cut = 1;
        sim_cut_at = -1;
        CHECK(fs_mount() == 0, "mount after mobile cut");
        CHECK(sim_violations == 0, "violations after mobile cut");
        r = fs_mobile_read(k, tmpbuf, &l2);
        isnew = r == 0 && l2 == len && !memcmp(tmpbuf, data, len);
        if (!isnew)
            CHECK(mob[k].present ? (r == 0 && l2 == mob[k].len && !memcmp(tmpbuf, mob[k].data, l2)) : r < 0,
                  "mobile %u cut: neither old nor new", k);
    } else {
        sim_snap_free(snap);
    }
    if (isnew) {
        mob[k].present = 1;
        mob[k].len = len;
        memcpy(mob[k].data, data, len);
    }
    return cut ? 1 + compacted : 0;
}

/* The flash packed to the last unit the allocator hands out: deletes and
   settings writes must keep working through remounts and power cuts, and
   one free block must always be left (mobile compaction needs it). */
static void test_full_disk(int iters)
{
    u8 *data = (u8 *)malloc(MAXSZ);
    int i, serial = 0, npack, refused = 0, deleted = 0, cuts = 0, ccuts = 0;
    char name[32];
    s32 r;
    i = pack("full", 0x40000, &serial, data, 1000);
    npack = i + pack("full", 0x4000, &serial, data, 1000);
    fprintf(stderr, "packed %d x 256KB, %d x 16KB, %u free blocks\n", i, npack - i, free_blocks());
    CHECK(free_blocks() >= 1, "packed: no free block left");
    reboot("packed");
    CHECK(free_blocks() >= 1, "packed, remounted: reserve block used up");
    for (i = 0; i < iters; i++) {
        u32 op = rnd() % 10, len;
        if (op < 6) {
            u32 k = (u32)mob_ids[rnd() % 6];
            len = 1 + rnd() % 2048;
            fill_rand(data, len);
            int cr = mobile_write_cut(k, data, len, rnd() % 3 == 0);
            cuts += cr != 0;
            ccuts += cr == 2;
        } else if (op < 8) {
            /* a small file: may or may not fit */
            sprintf(name, "small%u.bin", rnd() % 6);
            len = 0x4000 * (1 + rnd() % 2);
            fill_rand(data, len);
            r = fs_write_file(name, data, len);
            CHECK(r >= 0 || r == ST_DISK_FULL, "op %d: write %s failed %08x", i, name, (u32)r);
            if (r >= 0)
                set_file(name, data, len);
            else
                refused++;
        } else {
            /* delete a packing file, fill the space again */
            int m, s = (int)(rnd() % MAXF);
            for (m = 0; m < MAXF; m++)
                if (files[(s + m) % MAXF].used && !strncmp(files[(s + m) % MAXF].name, "full", 4))
                    break;
            if (m == MAXF)
                continue;
            m = (s + m) % MAXF;
            strcpy(name, files[m].name);
            len = files[m].len;
            r = fs_delete_file(name);
            if (r < 0)
                dump_space();
            CHECK(r >= 0, "op %d: delete %s failed %08x on a full volume", i, name, (u32)r);
            del_file(name);
            deleted++;
            if (!pack("full", len, &serial, data, 1))
                refused++;
            pack("full", 0x4000, &serial, data, 4);
        }
        CHECK(free_blocks() >= 1, "op %d: reserve block used up", i);
        if (i % 5 == 4) {
            reboot("full volume");
            CHECK(free_blocks() >= 1, "op %d, remounted: reserve block used up", i);
        }
    }
    reboot("after full volume ops");
    /* everything deleted, the space must come back */
    for (i = 0; i < MAXF; i++)
        if (files[i].used && (!strncmp(files[i].name, "full", 4) || !strncmp(files[i].name, "small", 5))) {
            strcpy(name, files[i].name);
            CHECK(fs_delete_file(name) >= 0, "cleanup %s", name);
            del_file(name);
        }
    reboot("after full volume cleanup");
    fill_rand(data, 0x100000);
    CHECK(fs_write_file("big.bin", data, 0x100000) >= 0, "1MB write after cleanup");
    set_file("big.bin", data, 0x100000);
    CHECK(fs_delete_file("big.bin") >= 0, "delete big.bin");
    del_file("big.bin");
    reboot("after big write");
    free(data);
    CHECK(ccuts > 0, "no power cut landed in a mobile compaction");
    printf("full volume: %d files packed, %d ops, %d deletes, %d writes refused, %d mobile cuts (%d in a "
           "compaction)\n",
           npack, iters, deleted, refused, cuts, ccuts);
}

static void test_bad_blocks(void)
{
    u8 *data = (u8 *)malloc(0x40000);
    u32 b, failed = 0;
    int i;
    /* fail program on a few FS blocks and erase on a few others */
    for (b = 0x15C; b < 0x1DC; b += 9) {
        if (b == 0x1C8)
            continue;
        if ((b / 9) & 1)
            sim_fail_program(b);
        else
            sim_fail_erase(b);
        failed++;
    }
    for (i = 0; i < 60; i++) {
        s32 r;
        fill_rand(data, 0x30000);
        r = fs_write_file("bad.bin", data, 0x30000);
        CHECK(r >= 0, "write with bad blocks failed %08x", (u32)r);
        set_file("bad.bin", data, 0x30000);
        if (i % 10 == 9)
            reboot("bad blocks");
    }
    sim_reset_state(); /* clears the failure injection (keeps contents) */
    reboot("after bad blocks");
    printf("bad blocks: %u failing blocks, writes recovered\n", failed);
    free(data);
}

int main(int argc, char **argv)
{
    int iters = argc > 2 ? atoi(argv[2]) : 300;
    if (argc < 2) {
        fprintf(stderr, "usage: %s <bb image> [iterations] [seed]\n", argv[0]);
        return 2;
    }
    rng = argc > 3 ? (u32)strtoul(argv[3], 0, 0) : 0x1888;
    tmpbuf = (u8 *)malloc(MAXSZ);
    sim_load(argv[1]);
    CHECK(fs_mount() == 0, "initial mount");
    CHECK(fs_load_root() == 0, "no root after mount");
    raw_check();
    load_mobiles();
    verify_all("initial");
    test_random(iters);
    test_fcb_fixup();
    test_power_cuts(iters / 2);
    test_fill();
    test_full_disk(iters / 2);
    test_bad_blocks();
    printf("ALL TESTS PASSED (seed %u)\n", rng);
    return 0;
}
