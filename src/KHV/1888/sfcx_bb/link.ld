/* 1888 big block flash support: code cave layout */
OUTPUT_FORMAT("elf32-powerpc")
OUTPUT_ARCH(powerpc:common)

SECTIONS
{
    /* tail of the last .text page (0x800E11A8-0x800EFFFF), which the HV
       copies and maps as kernel code with the rest of .text */
    . = 0x800E1200;
    .text : {
        *(.text.hooks)
        *(.text .text.*)
        *(.rodata .rodata.* .sdata2 .sdata2.*)
        . = ALIGN(4);
    }
    .data : { *(.data .data.* .sdata .sdata.* .bss .bss.* .sbss .sbss.* COMMON) }
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.gnu.attributes) }
}

ASSERT(SIZEOF(.data) == 0, "sfcx_bb: no writable data allowed (state lives in pool memory)")
ASSERT(ADDR(.text) + SIZEOF(.text) <= 0x800F0000, "sfcx_bb: code cave overflows the last .text page")

/* retail 1888 kernel */
K_KfRaiseIrql                         = 0x8005EAF0;
K_KfLowerIrql                         = 0x8005EB14;
K_KeAcquireSpinLockAtRaisedIrql       = 0x8005A290;
K_KeReleaseSpinLockFromRaisedIrql     = 0x8005A2DC;
K_KeInsertQueueDpc                    = 0x8005DA90;
K_KeEnterCriticalRegion               = 0x8005CB70;
K_KeLeaveCriticalRegion               = 0x8005CB88;
K_ExAcquireReadWriteLockExclusive     = 0x80050FA8;
K_ExReleaseReadWriteLock              = 0x800510D8;
K_ExAllocatePoolWithTag               = 0x80051758;
K_ExFreePool                          = 0x80051468;
K_FscInvalidateByteRange              = 0x80059540;
K_SfcxSynchronousFlashPassThrough     = 0x800758C0;
K_ExpSettingsContainers               = 0x800F01E8;

/* hooked functions, one past the patched first instruction */
K_SfcxTranslateLogicalFlashBlock_4    = 0x80072524;
K_SfcxEraseLogicalFlashBlock_4        = 0x80072A74;
K_SfcxFindAvailableFreeFlashBlock_4   = 0x80072B8C;
K_SfcxWriteRootDirectoryFlashBlock_4  = 0x80072E84;
K_SfcxWriteMobileFile_4               = 0x80072FFC;
K_SfcxEndUpdateTransaction_4          = 0x80073314;
K_SfcxBeginUpdateTransaction_4        = 0x800734AC;
K_SfcxWriteFileDataFlashBlock_4       = 0x800749D4;
K_SfcxVolumeWrite_4                   = 0x80074B14;
K_SfcxMountVolume_4                   = 0x8007666C;

/* SfcxStartFlashPassThrough / SfcxInitializeHardware */
K_StartTail_4                         = 0x8007614C;
K_StartEpilogue                       = 0x800761D0;
K_InitHwDecode_4                      = 0x800762BC;
K_InitHwStore                         = 0x80076314;
