/*
 * 1888 big block flash support: engine interface.
 *
 * The engine is plain C with no globals. It is built twice: for the 1888
 * kernel (xenon-gcc, linked into the code cave) and for the host-side NAND
 * simulator tests. Everything it shares with 1888 (the Sfcx device
 * extension, FAT and directory buffers, FCBs, IRPs) is big endian and is
 * accessed through the ld/st helpers below so the host build sees the same
 * bytes the console does.
 */
#ifndef BB_H
#define BB_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef int s32;
typedef unsigned long bbptr; /* pointer-sized integer (32-bit on the console) */

/* ---------------------------------------------------------------------- */
/* NTSTATUS values                                                         */
/* ---------------------------------------------------------------------- */
#define ST_OK            0
#define ST_BAD_BLOCK     ((s32)0xC0051100) /* 1888: write/erase failed, caller retries */
#define ST_INVALID       ((s32)0xC000000D) /* STATUS_INVALID_PARAMETER */
#define ST_DISK_FULL     ((s32)0xC000007F) /* STATUS_DISK_FULL */
#define ST_NO_MEMORY     ((s32)0xC000009A) /* STATUS_INSUFFICIENT_RESOURCES */
#define ST_WRITE_PROTECT ((s32)0xC00000A2) /* STATUS_MEDIA_WRITE_PROTECTED */
#define ST_IO_ERROR      ((s32)0xC0000185) /* what 1888 returns for ECC errors */

/* ---------------------------------------------------------------------- */
/* Flash geometry (64MB system area of a big block part)                  */
/* ---------------------------------------------------------------------- */
#define BB_BLOCKS        0x200 /* 128KB blocks in the system area */
#define BB_USABLE        0x1E0 /* blocks 0x1E0-0x1FF are the spare area */
#define BB_SECT_PER_BLK  256
#define BB_SECT_PER_UNIT 32
#define BB_UNITS_PER_BLK 8
#define BB_PAGES_PER_BLK 64    /* 2KB pages */
#define BB_MAX_UNITS     4096  /* size of 1888's bitmaps and FAT */

/* Block types (spare byte 12, low 6 bits) */
#define BT_DATA   0x2A
#define BT_ROOT   0x2C
#define BT_MOBILE 0x30 /* + mobile index 1..9 (MobileB..MobileJ) */

/* FAT values (low 13 bits) and 1888's transaction flags */
#define FAT_ALLOC  0x1FFD
#define FAT_FREE   0x1FFE
#define FAT_END    0x1FFF
#define FAT_NEW    0x8000 /* written in this transaction */
#define FAT_DEAD   0x9FFE /* freed when the transaction commits */

/* ---------------------------------------------------------------------- */
/* 1888 retail Sfcx device extension (stock size 0x68C)                    */
/* ---------------------------------------------------------------------- */
#define DX_DEVOBJ     0x000 /* PDEVICE_OBJECT */
#define DX_VOLSIZE    0x00C /* raw volume length in bytes */
#define DX_BADMAP     0x060 /* 4096-bit bad unit bitmap, bit u&31 of word u>>5 */
#define DX_FREEMAP    0x260 /* 4096-bit free unit bitmap, bit 31-(u&31) of word u>>5 */
#define DX_REPLMAP    0x460 /* 128 x u16 spare replacement table */
#define DX_TOTAL      0x560 /* u16 units */
#define DX_RESERVED   0x562 /* u16 spare units */
#define DX_USABLE     0x564 /* u16 units the FS may use */
#define DX_RWLOCK     0x568 /* volume read/write lock */
#define DX_FCBS_RO    0x5A0 /* LIST_ENTRY: read-only FCBs */
#define DX_FCBS_WO    0x5A8 /* LIST_ENTRY: write FCBs */
#define DX_FILETAB    0x5B0 /* 10 x 12: [0] root, [1..9] MobileB..J */
#define DX_TXDEPTH    0x670 /* u32 update transaction depth */
#define DX_DIRBUF     0x674 /* u8 * 8KB directory (last 512 = bad bitmap) */
#define DX_FATBUF     0x678 /* u16 * 4096 FAT entries */
#define DX_DATABUF    0x67C /* u8 * 16KB unit being written */
#define DX_CANCELLED  0x680 /* u8 */
#define DX_DIRTY      0x681 /* u8 */
#define DX_CURSOR     0x686 /* u16 allocation hint */
#define DX_FREECOUNT  0x688 /* u16 free units */
/* added by the patch */
#define DX_BBMODE     0x68C /* u32: 1 = big block */
#define DX_CTX        0x690 /* struct bb_ctx * */
#define DX_SIZE       0x6A0

/* DX_FILETAB entry (12 bytes) */
#define FT_UNIT  0  /* u16 */
#define FT_SIZE  2  /* u16, 0x8000 = deleted */
#define FT_SEQ   4  /* u32, 0 = no file */
#define FT_PAGE  8  /* u8 first sector inside the unit */
#define FT_NEXT  9  /* u8 next free sector for in-place appends (always 0 on BB) */
#define FT_SIZEOF 12

/* FCB (32 bytes) */
#define FCB_LINK     0  /* LIST_ENTRY */
#define FCB_SIZE     16 /* u32 */
#define FCB_FIRST    20 /* u16 first unit */
#define FCB_CACHEIX  22 /* u16 cached chain index */
#define FCB_CACHEU   24 /* u16 unit at FCB_CACHEIX */
#define FCB_MOBILE   27 /* u8 */
#define FCB_MOBIX    28 /* u8 mobile index */

/* IRP fields */
#define IRP_INFO     0x14 /* IoStatus.Information */
#define IRP_UBUF     0x1C /* UserBuffer */

/* ---------------------------------------------------------------------- */
/* Engine context (pool memory, pointer at DX_CTX)                         */
/* The asm translate hook reads base at +0 and remap[] at +4.              */
/* ---------------------------------------------------------------------- */
#define CTX_BASE  0
#define CTX_REMAP 4
#define BB_NONE   0xFFFF
#define BB_MAXFIX 1024 /* units moved per transaction (FCB fixup log) */

struct bb_ctx {
    u16 base;               /* +0 first FS block */
    u16 nblk;               /* +2 FS blocks */
    u16 remap[BB_BLOCKS];   /* +4 logical block -> physical block */
    u32 bad[BB_BLOCKS / 32];    /* physical blocks known bad */
    u32 locked[BB_BLOCKS / 32]; /* logical blocks coalescing must not move */
    u8 geo7, geo8, geo9, pad;   /* geometry bytes copied into FS spares */
    u32 nunits;
    u32 root_unit, root_seq;    /* committed root, seq 0 = no FS */
    u32 mob_blk, mob_seq, mob_next; /* mobile block, highest seq used, next free 2KB page */
    u16 mob_page[10];           /* latest entry of each type: first sector, BB_NONE = none */
    u16 mob_size[10];           /* its size field (0x8000 = deleted) */
    u32 app_blk, app_slot;      /* block this transaction is filling */
    u32 last_alloc;             /* unit handed out by bb_alloc_unit, BB_NONE = none */
    u32 cursor;                 /* rotating start for free block search */
    u32 nfix;
    u16 fix_old[BB_MAXFIX], fix_new[BB_MAXFIX];
    u8 *buf;                    /* 16KB, 4KB aligned */
    u8 *buf2;                   /* 16KB, 4KB aligned */
    void *raw;                  /* allocation backing buf/buf2 */
};

/* the asm translate hook depends on these */
_Static_assert(__builtin_offsetof(struct bb_ctx, base) == CTX_BASE, "ctx base offset");
_Static_assert(__builtin_offsetof(struct bb_ctx, remap) == CTX_REMAP, "ctx remap offset");

/* ---------------------------------------------------------------------- */
/* Platform interface                                                      */
/* ---------------------------------------------------------------------- */
#define PLAT_OK    0
#define PLAT_ECC   1 /* uncorrectable ECC error */
#define PLAT_WRERR 2 /* program/erase failure */
#define PLAT_IO    3 /* request failed */

/* addr = physical byte address (sector aligned). With data == 0 only the
   spare of one sector is read. data requests are at most 8 sectors and
   must not cross a 4KB boundary of the (4KB aligned) buffer. */
s32 plat_read(u8 *dx, u32 addr, void *data, void *spare, u32 nsect);
s32 plat_write(u8 *dx, u32 addr, const void *data, const void *spare, u32 nsect);
s32 plat_erase(u8 *dx, u32 addr);
void *plat_alloc(u32 size);
void plat_free(void *p);
void plat_invalidate(u8 *dx, u32 offset, u32 length);

/* ---------------------------------------------------------------------- */
/* Engine entry points (called from the hooks)                             */
/* ---------------------------------------------------------------------- */
s32 bb_mount(u8 *dx);
s32 bb_alloc_unit(u8 *dx, u32 hint);
s32 bb_erase_unit(u8 *dx, u8 *irp, u32 unit, u8 *physout);
s32 bb_write_data(u8 *dx, u8 *irp, u32 unit, u32 phys);
s32 bb_write_root(u8 *dx, u8 *irp, u32 unit, u32 phys);
s32 bb_write_mobile(u8 *dx, u8 *irp, u8 *fcb, u32 size);
s32 bb_begin_post(u8 *dx, s32 status);
s32 bb_end_post(u8 *dx, s32 status);
u32 bb_xlate(u8 *dx, u32 unit); /* C version of the asm translate hook */

/* ---------------------------------------------------------------------- */
/* Big endian accessors                                                    */
/* ---------------------------------------------------------------------- */
static inline u32 ld8(const void *p) { return *(const u8 *)p; }
static inline u32 ld16(const void *p)
{
    const u8 *b = (const u8 *)p;
    return ((u32)b[0] << 8) | b[1];
}
static inline u32 ld32(const void *p)
{
    const u8 *b = (const u8 *)p;
    return ((u32)b[0] << 24) | ((u32)b[1] << 16) | ((u32)b[2] << 8) | b[3];
}
static inline void st8(void *p, u32 v) { *(u8 *)p = (u8)v; }
static inline void st16(void *p, u32 v)
{
    u8 *b = (u8 *)p;
    b[0] = (u8)(v >> 8);
    b[1] = (u8)v;
}
static inline void st32(void *p, u32 v)
{
    u8 *b = (u8 *)p;
    b[0] = (u8)(v >> 24);
    b[1] = (u8)(v >> 16);
    b[2] = (u8)(v >> 8);
    b[3] = (u8)v;
}
static inline void *ldptr(const void *p) { return (void *)(bbptr)ld32(p); }
static inline void stptr(void *p, const void *v) { st32(p, (u32)(bbptr)v); }

#endif
