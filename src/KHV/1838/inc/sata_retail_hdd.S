# ============================================================================
#  Retail formatted HDD support for 1838
#
#  1838's SataDiskInitialize always carves the disk up using its own early
#  layout (PixDump at sector 0x400 sized N/8, Dump/System/Partition1 after
#  it, Cache0/Cache1/AltFlash at the end of the disk). Later kernels read a
#  devkit partition table and fall back to the fixed retail layout when there
#  isn't one, which is what we want here.
#
#  We hook SataDiskInitialize right after Partition0 is assigned and probe
#  for a FATX superblock at both possible Partition1 locations:
#
#    - 1838 Partition1 has FATX          -> keep the original 1838 layout
#    - only retail Partition1 has FATX   -> use the retail layout
#    - neither has FATX                  -> keep the original 1838 layout
#
#  Retail layout (sectors), same as 17489's non-devkit fallback:
#    Cache0           0x00000400  size 0x00400000
#    Cache1           0x00400400  size 0x00400000
#    DumpPartition    0x00800400  size 0x00107180
#    SystemPartition  0x00907580  size 0x00080000
#    Partition1       0x00987580  size N - 0x987580
#  PixDump and AltFlash are left unassigned, just like 17489 on a retail drive.
#
#  Like 17489's SataDiskAuthenticateDevice, N for Partition1 comes from the
#  security sector (byte 0x2000) when there is one, since retail drives can
#  be restricted to fewer sectors than the drive reports. XeKeysVerifyRSASignature
#  is patched out in this kernel so the signature is meaningless; instead we
#  require the serial and model to match IDENTIFY and the count to be sane
#  (past the start of Partition1, not past the end of the disk). Otherwise
#  N is the user addressable sector count.
#
#  Security sector layout:
#    0x00  serial number     (20 bytes)
#    0x14  firmware revision ( 8 bytes)
#    0x1C  model number      (40 bytes)
#    0x44  logo digest       (20 bytes)
#    0x58  sector count      (little endian dword)
#    0x5C  signature
#
#  At the hook: r7 = N (user addressable sectors), r21 = Partition0,
#  r24 = Partition1, r25 = SystemPartition, r26 = DumpPartition and the
#  Cache0/Cache1 device objects are at 0x78(r1)/0x7C(r1). r22 (always 0),
#  r30 and r31 are dead non-volatiles, the IDENTIFY data is still at
#  0xC0(r1) and the delay interval at 0x70(r1) is no longer used.
#  SataDiskAssignPartitionBounds only clobbers r9-r11.
#
#  The code cave lives in the zero filled gap after .text, past the
#  RGLoader-1838_VdInit.S trampolines at 0x8010A220 (which reach 0x8010A5E8
#  at most, even with VdHANAless.S + VdValhalla.S included).
# ============================================================================

.set SataDiskAssignPartitionBounds, 0x800FD370
.set SataDiskInitialize_LayoutHook, 0x800FD738
.set SataDiskInitialize_LayoutResume, 0x800FD73C
.set SataDiskInitialize_Epilogue, 0x800FD7D8
.set SataDiskDumpPartitionStart, 0x801107C8
.set IoSynchronousFsdRequest, 0x80067260
.set ExAllocatePool, 0x800623A8
.set ExFreePool, 0x80061D48
.set DbgPrint, 0x80080688

.set SataRetailHddCave, 0x8010A800

# ============================================================================
#  Hook SataDiskInitialize (replaces rlwinm r5, r5, 29,3,24)
# ============================================================================
KMAKEPATCH SataDiskInitialize_LayoutHook
0:
   KMAKEBRANCH SataRetailHddCave
9:

# ============================================================================
#  Layout detection + retail layout
# ============================================================================
KMAKEPATCH SataRetailHddCave
0:
   mr       %r30, %r7                # r30 = N, survives our calls

   # 512 byte sector buffer in r22
   li       %r3, 0x200
   KMAKEBRANCHL ExAllocatePool
   mr.      %r22, %r3
   beq      sdrh_resume_legacy

   # Where 1838's own layout puts Partition1:
   # 0x400 + min((N >> 3) & ~0x7F, 0x1400000) + 0x107180 + 0x80000
   rlwinm   %r3, %r30, 29, 3, 24
   lis      %r11, 0x140
   cmplw    %cr6, %r3, %r11
   ble      %cr6, sdrh_legacy_size_ok
   mr       %r3, %r11
sdrh_legacy_size_ok:
   addi     %r3, %r3, 0x400
   addis    %r3, %r3, 0x10
   addi     %r3, %r3, 0x7180
   addis    %r3, %r3, 0x8
   bl       sdrh_read_sector
   blt      sdrh_try_retail
   bl       sdrh_is_fatx
   cmplwi   %cr6, %r3, 0
   bne      %cr6, sdrh_use_legacy

sdrh_try_retail:
   lis      %r3, 0x98
   ori      %r3, %r3, 0x7580
   bl       sdrh_read_sector
   blt      sdrh_use_legacy
   bl       sdrh_is_fatx
   cmplwi   %cr6, %r3, 0
   beq      %cr6, sdrh_use_legacy

   # Security sector, restricts N if it looks legit
   li       %r3, 0x10
   bl       sdrh_read_sector
   blt      sdrh_retail_free
   addi     %r8, %r1, 0xC0 + 20      # IDENTIFY serial number
   mr       %r9, %r22
   li       %r10, 10
   bl       sdrh_match_ident
   cmplwi   %cr6, %r3, 0
   beq      %cr6, sdrh_retail_free
   addi     %r8, %r1, 0xC0 + 54      # IDENTIFY model number
   addi     %r9, %r22, 0x1C
   li       %r10, 20
   bl       sdrh_match_ident
   cmplwi   %cr6, %r3, 0
   beq      %cr6, sdrh_retail_free
   addi     %r11, %r22, 0x58
   lwbrx    %r11, 0, %r11
   cmplw    %cr6, %r11, %r30
   bgt      %cr6, sdrh_retail_free
   lis      %r10, 0x98
   ori      %r10, %r10, 0x7580
   cmplw    %cr6, %r11, %r10
   ble      %cr6, sdrh_retail_free
   mr       %r30, %r11

sdrh_retail_free:
   mr       %r3, %r22
   KMAKEBRANCHL ExFreePool

   bl       sdrh_msg_end
   .string "SATA: retail partition layout detected (%08X sectors).\n"
   .align 2
sdrh_msg_end:
   mflr     %r3
   mr       %r4, %r30
   KMAKEBRANCHL DbgPrint

   # Cache0 / Cache1
   li       %r4, 0x400
   lis      %r5, 0x40
   lwz      %r3, 0x78(%r1)
   KMAKEBRANCHL SataDiskAssignPartitionBounds
   addis    %r4, %r4, 0x40
   lwz      %r3, 0x7C(%r1)
   KMAKEBRANCHL SataDiskAssignPartitionBounds

   # DumpPartition
   addis    %r4, %r4, 0x40
   lis      %r11, SataDiskDumpPartitionStart@ha
   stw      %r4, SataDiskDumpPartitionStart@l(%r11)
   lis      %r5, 0x10
   ori      %r5, %r5, 0x7180
   mr       %r3, %r26
   KMAKEBRANCHL SataDiskAssignPartitionBounds

   # SystemPartition
   add      %r4, %r4, %r5
   lis      %r5, 0x8
   mr       %r3, %r25
   KMAKEBRANCHL SataDiskAssignPartitionBounds

   # Partition1, up to N
   addis    %r4, %r4, 0x8
   subf     %r5, %r4, %r30
   mr       %r3, %r24
   KMAKEBRANCHL SataDiskAssignPartitionBounds

   KMAKEBRANCH SataDiskInitialize_Epilogue

sdrh_use_legacy:
   mr       %r3, %r22
   KMAKEBRANCHL ExFreePool
sdrh_resume_legacy:
   mr       %r5, %r30
   mr       %r7, %r30
   rlwinm   %r5, %r5, 29, 3, 24      # do what we patched
   KMAKEBRANCH SataDiskInitialize_LayoutResume

# ----------------------------------------------------------------------------
#  sdrh_read_sector
#  in:  r3 = sector number on Partition0
#  out: r3 = NTSTATUS, cr0 set from it, sector data in r22
# ----------------------------------------------------------------------------
sdrh_read_sector:
   mflr     %r31
   clrldi   %r3, %r3, 32
   sldi     %r3, %r3, 9
   std      %r3, 0x70(%r1)           # byte offset
   li       %r3, 2                   # IRP_MJ_READ
   mr       %r4, %r21                # Partition0
   mr       %r5, %r22
   li       %r6, 0x200
   addi     %r7, %r1, 0x70
   KMAKEBRANCHL IoSynchronousFsdRequest
   mtlr     %r31
   cmpwi    %r3, 0
   blr

# ----------------------------------------------------------------------------
#  sdrh_is_fatx
#  out: r3 = 1 if r22 holds a FATX superblock 1838 would mount
#       ('XTAF', sectors per cluster a power of two <= 0x80), else 0
# ----------------------------------------------------------------------------
sdrh_is_fatx:
   li       %r3, 0
   lwz      %r4, 0(%r22)
   lis      %r5, 0x5854
   ori      %r5, %r5, 0x4146         # 'XTAF'
   cmplw    %cr6, %r4, %r5
   bnelr    %cr6

   lwz      %r4, 8(%r22)             # SectorsPerCluster
   addi     %r5, %r4, -1
   and.     %r5, %r5, %r4
   bnelr
   cmplwi   %cr6, %r4, 0
   beqlr    %cr6
   cmplwi   %cr6, %r4, 0x80
   bgtlr    %cr6

   li       %r3, 1
   blr

# ----------------------------------------------------------------------------
#  sdrh_match_ident
#  in:  r8 = IDENTIFY string, r9 = security sector string, r10 = halfwords
#  out: r3 = 1 if they match (IDENTIFY words are byte swapped), else 0
# ----------------------------------------------------------------------------
sdrh_match_ident:
   mtctr    %r10
   li       %r3, 0
sdrh_match_loop:
   lhbrx    %r10, 0, %r8
   lhz      %r11, 0(%r9)
   cmplw    %cr6, %r10, %r11
   bnelr    %cr6
   addi     %r8, %r8, 2
   addi     %r9, %r9, 2
   bdnz     sdrh_match_loop
   li       %r3, 1
   blr
9:
