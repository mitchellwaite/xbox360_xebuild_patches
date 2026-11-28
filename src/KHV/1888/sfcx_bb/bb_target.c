/*
 * 1888 big block flash support: console glue.
 *
 * Flash I/O goes through 1888's own SfcxSynchronousFlashPassThrough, so it
 * is queued and completed like every other Sfcx request (and, on big
 * block, the DMA requests are done as register mode transfers by the
 * SfcxStartFlashPassThrough hook).
 */
#include "bb.h"

/* stubs.S: MS-ABI calls into the kernel */
s32 k_SfcxSynchronousFlashPassThrough(u32 ioctl, void *devobj, void *desc);
void *k_ExAllocatePoolWithTag(u32 size, u32 tag);
void k_ExFreePool(void *p);
void k_FscInvalidateByteRange(void *cache, u32 offset, u32 length);
void k_KeEnterCriticalRegion(void);
void k_KeLeaveCriticalRegion(void);
void k_ExAcquireReadWriteLockExclusive(void *lock);
void k_ExReleaseReadWriteLock(void *lock);

/* Sfcx pass-through descriptor */
struct sfcx_desc {
    u32 addr, data, unused, status, logical, physical, spare, count;
} __attribute__((aligned(8)));

#define IOCTL_READ_DMA   0x3C002C /* physical read, data + spares */
#define IOCTL_READ_SPARE 0x3C003C /* physical read, spare of one sector */
#define IOCTL_ERASE      0x3C8014
#define IOCTL_WRITE_DMA  0x3C8038 /* physical write, driver computes ECC */

static s32 pass(u8 *dx, u32 ioctl, u32 addr, void *data, void *spare, u32 n)
{
    struct sfcx_desc d;
    s32 s;
    d.addr = addr;
    d.data = (u32)(bbptr)data;
    d.unused = 0;
    d.status = 0;
    d.logical = 0;
    d.physical = 0;
    d.spare = (u32)(bbptr)spare;
    d.count = n;
    s = k_SfcxSynchronousFlashPassThrough(ioctl, ldptr(dx + DX_DEVOBJ), &d);
    if (s < 0)
        return PLAT_IO;
    if (d.status & 0x2)
        return PLAT_WRERR;
    if ((d.status & 0x1C) >= 0x10 || (d.status & 0x20) || (d.status & 0x800))
        return PLAT_ECC;
    return PLAT_OK;
}

s32 plat_read(u8 *dx, u32 addr, void *data, void *spare, u32 nsect)
{
    if (!data)
        return pass(dx, IOCTL_READ_SPARE, addr, 0, spare, 1);
    return pass(dx, IOCTL_READ_DMA, addr, data, spare, nsect);
}

s32 plat_write(u8 *dx, u32 addr, const void *data, const void *spare, u32 nsect)
{
    return pass(dx, IOCTL_WRITE_DMA, addr, (void *)data, (void *)spare, nsect);
}

s32 plat_erase(u8 *dx, u32 addr) { return pass(dx, IOCTL_ERASE, addr, 0, 0, 0); }

void *plat_alloc(u32 size) { return k_ExAllocatePoolWithTag(size, 0x42426673 /* 'BBfs' */); }
void plat_free(void *p) { k_ExFreePool(p); }

void plat_invalidate(u8 *dx, u32 offset, u32 length) { k_FscInvalidateByteRange(dx, offset, length); }

/* SfcxMountVolume(DeviceObject) on big block */
s32 bb_mount_entry(u8 *devobj);
s32 bb_mount_entry(u8 *devobj)
{
    u8 *dx = (u8 *)ldptr(devobj + 0x18);
    k_KeEnterCriticalRegion();
    k_ExAcquireReadWriteLockExclusive(dx + DX_RWLOCK);
    bb_mount(dx);
    k_ExReleaseReadWriteLock(dx + DX_RWLOCK);
    k_KeLeaveCriticalRegion();
    stptr(devobj + 0x0C, devobj); /* mounted */
    return ST_OK;
}

/* the compiler may emit these for struct copies/clears */
void *memset(void *d, int v, unsigned long n)
{
    u8 *p = (u8 *)d;
    while (n--)
        *p++ = (u8)v;
    return d;
}

void *memcpy(void *d, const void *s, unsigned long n)
{
    u8 *p = (u8 *)d;
    const u8 *q = (const u8 *)s;
    while (n--)
        *p++ = *q++;
    return d;
}
