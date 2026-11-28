/*
 * 1888 big block flash support: asm side of the code cave.
 *
 *  - hooks patched over the first instruction of 1888 Sfcx functions; each
 *    checks the big block flag and otherwise runs the original instruction
 *    and continues in the stock function
 *  - kernel -> C thunks that preserve every register except r3 (the 32-bit
 *    C code only keeps the low halves of r14-r31, and some 1888 callers rely
 *    on scratch registers surviving leaf calls)
 *  - C -> kernel stubs that give the callee a 0x60 byte MS-style frame
 *  - the SfcxStartFlashPassThrough tail hook that does DMA requests as
 *    register mode sector I/O on big block
 *
 * Kernel addresses come from link.ld.
 */
        .section .text.hooks, "ax"

/* device extension fields (see bb.h) */
        .set DX_BBMODE, 0x68C
        .set DX_CTX,    0x690

/* ======================================================================== */
/* kernel -> C thunk                                                         */
/* ======================================================================== */
        .set TF, 0x120          /* frame: 0x10 header, 29 x 8 GPRs, CR, XER, CTR */
.macro CENTRY name, cfn
        .globl \name
\name:
        std     %r0, -0x10(%r1)
        mflr    %r0
        stw     %r0, -8(%r1)
        rlwinm  %r0, %r1, 0, 28, 31     /* keep the C stack 16 byte aligned */
        subfic  %r0, %r0, -TF
        stwux   %r1, %r1, %r0
        std     %r2,  0x10(%r1)
        std     %r4,  0x18(%r1)
        std     %r5,  0x20(%r1)
        std     %r6,  0x28(%r1)
        std     %r7,  0x30(%r1)
        std     %r8,  0x38(%r1)
        std     %r9,  0x40(%r1)
        std     %r10, 0x48(%r1)
        std     %r11, 0x50(%r1)
        std     %r12, 0x58(%r1)
        std     %r13, 0x60(%r1)
        std     %r14, 0x68(%r1)
        std     %r15, 0x70(%r1)
        std     %r16, 0x78(%r1)
        std     %r17, 0x80(%r1)
        std     %r18, 0x88(%r1)
        std     %r19, 0x90(%r1)
        std     %r20, 0x98(%r1)
        std     %r21, 0xA0(%r1)
        std     %r22, 0xA8(%r1)
        std     %r23, 0xB0(%r1)
        std     %r24, 0xB8(%r1)
        std     %r25, 0xC0(%r1)
        std     %r26, 0xC8(%r1)
        std     %r27, 0xD0(%r1)
        std     %r28, 0xD8(%r1)
        std     %r29, 0xE0(%r1)
        std     %r30, 0xE8(%r1)
        std     %r31, 0xF0(%r1)
        mfcr    %r0
        stw     %r0, 0xF8(%r1)
        mfxer   %r0
        stw     %r0, 0xFC(%r1)
        mfctr   %r0
        std     %r0, 0x100(%r1)
        bl      \cfn
        ld      %r0, 0x100(%r1)
        mtctr   %r0
        lwz     %r0, 0xFC(%r1)
        mtxer   %r0
        lwz     %r0, 0xF8(%r1)
        mtcrf   0xFF, %r0
        ld      %r2,  0x10(%r1)
        ld      %r4,  0x18(%r1)
        ld      %r5,  0x20(%r1)
        ld      %r6,  0x28(%r1)
        ld      %r7,  0x30(%r1)
        ld      %r8,  0x38(%r1)
        ld      %r9,  0x40(%r1)
        ld      %r10, 0x48(%r1)
        ld      %r11, 0x50(%r1)
        ld      %r12, 0x58(%r1)
        ld      %r13, 0x60(%r1)
        ld      %r14, 0x68(%r1)
        ld      %r15, 0x70(%r1)
        ld      %r16, 0x78(%r1)
        ld      %r17, 0x80(%r1)
        ld      %r18, 0x88(%r1)
        ld      %r19, 0x90(%r1)
        ld      %r20, 0x98(%r1)
        ld      %r21, 0xA0(%r1)
        ld      %r22, 0xA8(%r1)
        ld      %r23, 0xB0(%r1)
        ld      %r24, 0xB8(%r1)
        ld      %r25, 0xC0(%r1)
        ld      %r26, 0xC8(%r1)
        ld      %r27, 0xD0(%r1)
        ld      %r28, 0xD8(%r1)
        ld      %r29, 0xE0(%r1)
        ld      %r30, 0xE8(%r1)
        ld      %r31, 0xF0(%r1)
        lwz     %r1, 0(%r1)
        lwz     %r0, -8(%r1)
        mtlr    %r0
        ld      %r0, -0x10(%r1)
        blr
.endm

        CENTRY  c_alloc,      bb_alloc_unit
        CENTRY  c_erase,      bb_erase_unit
        CENTRY  c_write_root, bb_write_root
        CENTRY  c_write_data, bb_write_data
        CENTRY  c_write_mob,  bb_write_mobile
        CENTRY  c_mount,      bb_mount_entry
        CENTRY  c_begin_post, bb_begin_post
        CENTRY  c_end_post,   bb_end_post

/* ======================================================================== */
/* C -> kernel stubs                                                         */
/* ======================================================================== */
.macro KCALL name, target
        .globl \name
\name:
        mflr    %r0
        stw     %r0, 4(%r1)
        stwu    %r1, -0x60(%r1)
        bl      \target
        addi    %r1, %r1, 0x60
        lwz     %r0, 4(%r1)
        mtlr    %r0
        blr
.endm

        KCALL   k_SfcxSynchronousFlashPassThrough, K_SfcxSynchronousFlashPassThrough
        KCALL   k_ExAllocatePoolWithTag,           K_ExAllocatePoolWithTag
        KCALL   k_ExFreePool,                      K_ExFreePool
        KCALL   k_KeEnterCriticalRegion,           K_KeEnterCriticalRegion
        KCALL   k_KeLeaveCriticalRegion,           K_KeLeaveCriticalRegion
        KCALL   k_ExAcquireReadWriteLockExclusive, K_ExAcquireReadWriteLockExclusive
        KCALL   k_ExReleaseReadWriteLock,          K_ExReleaseReadWriteLock

/* FscInvalidateByteRange(cache, LONGLONG offset, ULONG length): the
   offset is one 64-bit register on the MS side */
        .globl  k_FscInvalidateByteRange
k_FscInvalidateByteRange:
        mflr    %r0
        stw     %r0, 4(%r1)
        stwu    %r1, -0x60(%r1)
        clrldi  %r4, %r4, 32
        clrldi  %r5, %r5, 32
        bl      K_FscInvalidateByteRange
        addi    %r1, %r1, 0x60
        lwz     %r0, 4(%r1)
        mtlr    %r0
        blr

/* ======================================================================== */
/* hooks                                                                     */
/* ======================================================================== */

/* SfcxTranslateLogicalFlashBlock(dx, unit, flag) -> physical 16KB unit.
   Big block: (remap[base + unit/8] << 3) | (unit & 7). Leaf, uses r0/r11/r12. */
        .globl  hk_translate
hk_translate:
        lwz     %r12, DX_BBMODE(%r3)
        cmplwi  %r12, 0
        bne     1f
        mflr    %r12
        b       K_SfcxTranslateLogicalFlashBlock_4
1:      lwz     %r12, DX_CTX(%r3)
        cmplwi  %r12, 0
        beq     2f
        lhz     %r11, 0(%r12)           /* ctx->base */
        srwi    %r0, %r4, 3
        add     %r11, %r11, %r0
        slwi    %r11, %r11, 1
        addi    %r11, %r11, 4           /* ctx->remap[] */
        lhzx    %r11, %r12, %r11
        rlwinm  %r3, %r4, 0, 29, 31
        rlwimi  %r3, %r11, 3, 0, 28
        blr
2:      mr      %r3, %r4
        blr

/* SfcxFindAvailableFreeFlashBlock(dx, hint) is a leaf whose caller keeps
   r6 live across it; c_alloc preserves everything but r3 */
        .globl  hk_alloc
hk_alloc:
        lwz     %r11, DX_BBMODE(%r3)
        cmplwi  %cr6, %r11, 0
        bne     %cr6, c_alloc
        mr      %r11, %r3
        b       K_SfcxFindAvailableFreeFlashBlock_4

.macro HOOK name, centry, orig4
        .globl \name
\name:
        lwz     %r11, DX_BBMODE(%r3)
        cmplwi  %cr6, %r11, 0
        bne     %cr6, \centry
        mflr    %r12
        b       \orig4
.endm

        HOOK    hk_erase,      c_erase,      K_SfcxEraseLogicalFlashBlock_4
        HOOK    hk_write_root, c_write_root, K_SfcxWriteRootDirectoryFlashBlock_4
        HOOK    hk_write_data, c_write_data, K_SfcxWriteFileDataFlashBlock_4
        HOOK    hk_write_mob,  c_write_mob,  K_SfcxWriteMobileFile_4

/* SfcxVolumeWrite: raw 16KB volume writes would erase a 128KB block */
        .globl  hk_volume_write
hk_volume_write:
        lwz     %r11, DX_BBMODE(%r3)
        cmplwi  %cr6, %r11, 0
        beq     %cr6, 1f
        lis     %r3, -0x4000
        ori     %r3, %r3, 0x00A2        /* STATUS_MEDIA_WRITE_PROTECTED */
        blr
1:      mflr    %r12
        b       K_SfcxVolumeWrite_4

/* SfcxMountVolume(DeviceObject) */
        .globl  hk_mount
hk_mount:
        lwz     %r11, 0x18(%r3)         /* DeviceExtension */
        lwz     %r11, DX_BBMODE(%r11)
        cmplwi  %cr6, %r11, 0
        bne     %cr6, c_mount
        mflr    %r12
        b       K_SfcxMountVolume_4

/* SfcxBegin/EndUpdateTransaction: run the stock function, then the C post hook */
.macro WRAP name, orig4, post
        .globl \name
\name:
        lwz     %r11, DX_BBMODE(%r3)
        cmplwi  %cr6, %r11, 0
        bne     %cr6, 1f
        mflr    %r12
        b       \orig4
1:      mflr    %r0
        stw     %r0, -8(%r1)
        std     %r31, -0x10(%r1)
        stwu    %r1, -0x60(%r1)
        mr      %r31, %r3
        bl      2f
        mr      %r4, %r3
        mr      %r3, %r31
        bl      \post
        addi    %r1, %r1, 0x60
        lwz     %r0, -8(%r1)
        mtlr    %r0
        ld      %r31, -0x10(%r1)
        blr
2:      mflr    %r12
        b       \orig4
.endm

        WRAP    hk_begin, K_SfcxBeginUpdateTransaction_4, c_begin_post
        WRAP    hk_end,   K_SfcxEndUpdateTransaction_4,   c_end_post

/* SfcxInitializeHardware (replaces "extrwi r11, r9, 2,26")
   r9 = SFC config, r31 = device extension; exits with r11 = units,
   r10 = spare units at the stock store code */
        .globl  hk_geometry
hk_geometry:
        li      %r11, 0
        stw     %r11, DX_BBMODE(%r31)
        stw     %r11, DX_CTX(%r31)
        extrwi  %r10, %r9, 2, 13        /* controller type */
        cmplwi  %cr6, %r10, 0
        beq     %cr6, 1f
        cmplwi  %cr6, %r10, 3
        beq     %cr6, 1f
        extrwi  %r11, %r9, 2, 26        /* size field */
        cmplwi  %cr6, %r11, 2
        beq     %cr6, 2f
        cmplwi  %cr6, %r11, 0           /* newer controllers report 16MB as 0 */
        bne     %cr6, 1f
        li      %r11, 0x400
        li      %r10, 0x20
        b       K_InitHwStore
2:      li      %r11, 1                 /* big block */
        stw     %r11, DX_BBMODE(%r31)
        /* XConfig containers 0/1 (raw volume blocks at -16KB/-32KB) become
           MobileF.dat/MobileG.dat; a raw 16KB write would erase 128KB */
        lis     %r12, K_ExpSettingsContainers@ha
        addi    %r12, %r12, K_ExpSettingsContainers@l
        lis     %r11, mobilef_name@ha
        addi    %r11, %r11, mobilef_name@l
        stw     %r11, 0x00(%r12)
        lis     %r11, mobileg_name@ha
        addi    %r11, %r11, mobileg_name@l
        stw     %r11, 0x14(%r12)
        li      %r11, 0
        stw     %r11, 0x04(%r12)        /* offset */
        stw     %r11, 0x08(%r12)        /* flags: write only the used sectors */
        stw     %r11, 0x18(%r12)
        stw     %r11, 0x1C(%r12)
        li      %r11, 0x400             /* 1024 16KB units, no unit-level spares */
        li      %r10, 0
        b       K_InitHwStore
1:      extrwi  %r11, %r9, 2, 26
        b       K_InitHwDecode_4

/* ======================================================================== */
/* SfcxStartFlashPassThrough common tail (replaces "lbz r3, 0x21(r19)").     */
/* Big block DMA requests (cmd 6/7 reads, cmd 8 writes) are done as register */
/* mode sector transfers here; the DMA length field counts 2KB pages on BB.  */
/* Live: r19 devext, r21 count, r22 DMA flag, r23 data, r24 metadata array,  */
/* r25 descriptor, r29 command. r19-r31 are restored by the stock epilogue.  */
/* ======================================================================== */
        .set REG_STATUS,  0x04
        .set REG_COMMAND, 0x08
        .set REG_ADDRESS, 0x0C
        .set REG_DATA,    0x10

        .globl  hk_start_tail
hk_start_tail:
        lwz     %r11, DX_BBMODE(%r19)
        cmplwi  %cr6, %r11, 0
        beq     %cr6, 1f
        cmplwi  %cr6, %r22, 0
        bne     %cr6, 2f
1:      lbz     %r3, 0x21(%r19)
        b       K_StartTail_4

2:      lbz     %r3, 0x21(%r19)         /* same IRQL/lock handling as stock */
        bl      K_KfRaiseIrql
        addi    %r31, %r19, 0x18
        mr      %r3, %r31
        bl      K_KeAcquireSpinLockAtRaisedIrql
        addi    %r11, %r13, 0x100
        stw     %r11, 0x24(%r19)

        li      %r30, 0                 /* OR of every sector's status */
        lwz     %r27, 0(%r25)           /* flash address */
        mr      %r26, %r23              /* data */
        mr      %r28, %r24              /* spares (SfcxStaticMetadataArray) */
        mr      %r20, %r21
        cmplwi  %cr6, %r20, 16
        ble     %cr6, 3f
        li      %r20, 16
3:      cmplwi  %cr6, %r20, 0
        beq     %cr6, 6f
        cmplwi  %cr6, %r29, 8           /* DMA_RAM_TO_PHY */
        beq     %cr6, 5f

4:      mr      %r3, %r27               /* reads */
        mr      %r4, %r26
        mr      %r5, %r28
        bl      read_sector
        or      %r30, %r30, %r3
        addi    %r27, %r27, 0x200
        addi    %r26, %r26, 0x200
        addi    %r28, %r28, 0x10
        addic.  %r20, %r20, -1
        bne     4b
        b       6f

5:      mr      %r3, %r27               /* writes; spares already have ECC */
        mr      %r4, %r26
        mr      %r5, %r28
        bl      write_sector
        or      %r30, %r30, %r3
        addi    %r27, %r27, 0x200
        addi    %r26, %r26, 0x200
        addi    %r28, %r28, 0x10
        addic.  %r20, %r20, -1
        bne     5b

6:      mr      %r3, %r31               /* complete through the DPC like the ISR */
        bl      K_KeReleaseSpinLockFromRaisedIrql
        li      %r3, 2
        bl      K_KfLowerIrql
        addi    %r3, %r19, 0x28
        mr      %r4, %r30
        li      %r5, 0
        bl      K_KeInsertQueueDpc
        b       K_StartEpilogue

/* wait for the controller to go idle, then clear status; r3 = status.
   Clobbers r0, r10-r12, ctr; leaves r12 = SFC base. A timeout reports a
   write error and an uncorrectable ECC error. */
wait_ready:
        lis     %r12, 0x7FEA
        ori     %r12, %r12, 0xC000
        addi    %r10, %r12, REG_STATUS
        lis     %r0, 0x20
        mtctr   %r0
1:      lwbrx   %r3, 0, %r10
        andi.   %r11, %r3, 1
        beq     2f
        bdnz    1b
        ori     %r3, %r3, 0x1E
2:      stwbrx  %r3, 0, %r10
        eieio
        blr

/* r3 = flash address, r4 = 512 data, r5 = 16 spare; r3 = status */
read_sector:
        mflr    %r9
        lis     %r12, 0x7FEA
        ori     %r12, %r12, 0xC000
        addi    %r10, %r12, REG_ADDRESS
        stwbrx  %r3, 0, %r10
        eieio
        li      %r11, 3                 /* PHY_PAGE_TO_BUF */
        addi    %r10, %r12, REG_COMMAND
        stwbrx  %r11, 0, %r10
        eieio
        bl      wait_ready
        mr      %r6, %r3
        li      %r0, 0
        stw     %r0, REG_ADDRESS(%r12)
        eieio
        li      %r11, 128
        mtctr   %r11
1:      stw     %r0, REG_COMMAND(%r12)  /* PAGE_BUF_TO_REG */
        eieio
        lwz     %r11, REG_DATA(%r12)
        stw     %r11, 0(%r4)
        addi    %r4, %r4, 4
        bdnz    1b
        li      %r11, 4
        mtctr   %r11
2:      stw     %r0, REG_COMMAND(%r12)
        eieio
        lwz     %r11, REG_DATA(%r12)
        stw     %r11, 0(%r5)
        addi    %r5, %r5, 4
        bdnz    2b
        mr      %r3, %r6
        mtlr    %r9
        blr

/* r3 = flash address, r4 = 512 data, r5 = 16 spare; r3 = status.
   Same sequence as the stock single page write. */
write_sector:
        mflr    %r9
        lis     %r12, 0x7FEA
        ori     %r12, %r12, 0xC000
        li      %r0, 0
        stw     %r0, REG_ADDRESS(%r12)
        eieio
        lis     %r6, 0x100              /* REG_TO_PAGE_BUF, byte swapped */
        li      %r11, 128
        mtctr   %r11
1:      lwz     %r11, 0(%r4)
        addi    %r4, %r4, 4
        stw     %r11, REG_DATA(%r12)
        eieio
        stw     %r6, REG_COMMAND(%r12)
        eieio
        bdnz    1b
        li      %r11, 4
        mtctr   %r11
2:      lwz     %r11, 0(%r5)
        addi    %r5, %r5, 4
        stw     %r11, REG_DATA(%r12)
        eieio
        stw     %r6, REG_COMMAND(%r12)
        eieio
        bdnz    2b
        lis     %r11, 0x5500            /* unlock 0x55, 0xAA */
        stw     %r11, REG_COMMAND(%r12)
        eieio
        lis     %r11, -0x5600
        stw     %r11, REG_COMMAND(%r12)
        eieio
        addi    %r10, %r12, REG_ADDRESS
        stwbrx  %r3, 0, %r10
        eieio
        li      %r11, 4                 /* WRITE_PAGE_TO_PHY */
        addi    %r10, %r12, REG_COMMAND
        stwbrx  %r11, 0, %r10
        eieio
        bl      wait_ready
        mtlr    %r9
        blr

/* ======================================================================== */
/* read-only data                                                            */
/* ======================================================================== */
        .section .rodata
        .balign 4
mobilef_name:                           /* STRING */
        .short  27, 28
        .long   mobilef_text
mobileg_name:
        .short  27, 28
        .long   mobileg_text
mobilef_text:
        .asciz  "\\Device\\FlashFs\\MobileF.dat"
mobileg_text:
        .asciz  "\\Device\\FlashFs\\MobileG.dat"
