# ============================================================================
# For JTAGs only: keep the JTAG payload page intact when the kernel writes to
# flash, otherwise enabling KDNet bricks the console
# Thanks to @kavkazsila on discord for pointing it out in the 16537 patch
#
# Included from khv_17489.S for JTAG builds (consoletype_jtag).
#
# Background
# ----------
# Each 512-byte flash page has a 16-byte spare area. Spare bytes 0x0-0xB hold
# filesystem metadata (block ID, sequence, bad-block marker, ...). Byte 0xC
# holds a 6-bit block type, and the top 26 bits of the little-endian word at
# 0xC are the page's ECC. The ECC covers the 512 data bytes, spare 0x0-0xB
# and the block type.
#
# On a JTAG image, flash page 1 (offset 0x200) is the JTAG payload, and its
# spare area isn't what the kernel would write. xeBuild builds it as:
#
#     small block   00 00 00 00 00 FF 00 00 00 00 | 03 50 | 00 7B 83 57
#     big block     FF 00 00 00 00 00 00 00 00 00 | 03 50 | C0 0F 45 BF
#                                                   ^^^^^   ECC valid for 03 50
#
# Normal pages have 00 00 in bytes 0xA-0xB. When the kernel rewrites block 0
# it builds a normal spare for page 1, the 03 50 is lost and the JTAG
# exploit stops working: the console is bricked until it's reflashed.
# (Why enabling KDNet leads to that rewrite hasn't been traced.)
#
# This makes three changes to the SFCX (flash controller) driver:
#   1. SfcxEncodeECC: when the page being encoded is the JTAG payload page,
#      put 03 50 back and fix the ECC to match.
#   2. SfcxFinishFlashPassThrough: ignore an "uncorrectable ECC" status on
#      requests at flash address 0 (block 0, which holds page 1).
#   3. SfcxSynchronousWriteInternal: skip the spare-area read-back check.
#      Change 1 writes a spare that differs from the one the caller asked
#      for, so the check would always fail.
#
# The 16537 version of change 1 has a bug. It stored the correct ECC and then
# ran the original stwbrx, which overwrites it with the ECC for 00 00. Page 1
# was left with 03 50 and an uncorrectable ECC. Change 2 probably exists to
# hide that. This version writes the correct ECC; change 2 is kept for
# consoles where page 1 has already been damaged that way.
#
# Changing the payload
# --------------------
# JTAG_COMP_SB/_BB are the ECC of xeBuild's payload page, so they have to
# change if the page does. xeBuild uses defPayload from build.c and patches
# its "li r4, reps" (offset 0x50) to (core size + 3) >> 2. The built-in 0xD40
# byte core gives reps = 0x350. A different core size or a custom payload.bin
# gives different COMPs.
# JTAG_ECC_FIX depends only on JTAG_SC, which xeBuild hard-codes (xb.spare[26]
# = 3, xb.spare[27] = 0x50 in image_write.c), so it's the same for both
# layouts. To get the values for a build, run tools/jtag_kd_consts.py on a
# small-block and a big-block image:
#
#     python tools/jtag_kd_consts.py updflash.bin
#
# (The 16537 patch's values were for RGBuild's payload on small block and an
# older xeBuild core, reps 0x34C, on big block.)
#
# 16537 -> 17489 addresses:
#   SfcxEncodeECC                 0x800C1E08 -> 0x800C20B8
#   SfcxFinishFlashPassThrough    0x800BC8A8 -> 0x800BCB90
#   SfcxSynchronousWriteInternal  0x800B72F8 -> 0x800B7578
#                                 0x800B730C -> 0x800B758C
# ============================================================================

# Empty space in the last page of .text, which ends at 0x801C1770. This is past
# RGLoader's loader at 0x801C1774 (ends 0x801C17B0) and before the strings in
# sysroot_hdd.S at 0x801C1850. The ECC cave runs to 0x801C17F0 and the flash
# cave to 0x801C1808.
.set KdnetJtagEccCave,   0x801C17C0
.set KdnetJtagFlashCave, 0x801C17F0

.set SfcxEncodeECC_Store,          0x800C20B8
.set SfcxFinishFlashPassThrough_Ld, 0x800BCB90

# Bytes 0xA-0xB of the payload page's spare on a JTAG image
.set JTAG_SC, 0x350

# The ECC word SfcxEncodeECC computes for xeBuild's payload page (built-in
# payload and core), i.e. with 00 00 in bytes 0xA-0xB. The page data is the
# same on every console; only the spare bytes before 0xA differ:
#   _SB: small block (Xenon, Zephyr, Falcon, 16MB Jasper), FF at byte 5
#   _BB: big block (256/512MB Jasper), FF at byte 0
.set JTAG_COMP_SB, 0x630A69C0
.set JTAG_COMP_BB, 0x8BCC1D00

# ECC is linear, so setting bytes 0xA-0xB from 00 00 to JTAG_SC always flips
# the same bits of the ECC word whatever the payload or spare is. XOR this
# into the kernel's word to get the ECC for the JTAG spare:
#   JTAG_COMP_SB ^ JTAG_ECC_FIX = 0x57837B00, stored as 00 7B 83 57
#   JTAG_COMP_BB ^ JTAG_ECC_FIX = 0xBF450FC0, stored as C0 0F 45 BF
.set JTAG_ECC_FIX, 0x348912C0

# ==================================================================
# SfcxEncodeECC hook, replaces the stwbrx r9, r7, r4
#
# SfcxEncodeECC(r3 = data, r4 = spare, r5 = page count) fills in the ECC
# for two pages at a time: data r3 / r3+0x200, spares r4 / r4+0x10. The
# hooked instruction stores the second page's word (r7 = 0x1C, so
# r4 + 0x10 + 0xC), with r9 = ECC << 6 | block type. That makes the hook see
# only the second page of each pair, which is where page 1 always lands. The
# tail path for an odd last page is never hooked.
#
# r11 and cr0 are free here (nothing reads them before they're set again),
# and r9 isn't read again after the store.
# ==================================================================
KMAKEPATCH SfcxEncodeECC_Store
0:
	KMAKEBRANCH KdnetJtagEccCave
9:

KMAKEPATCH KdnetJtagEccCave
0:
   # Is this the JTAG payload page?
   xoris     %r11, %r9, JTAG_COMP_SB@h
   cmplwi    %r11, JTAG_COMP_SB@l
   beq       KdnetJtag_EccMatch
   xoris     %r11, %r9, JTAG_COMP_BB@h
   cmplwi    %r11, JTAG_COMP_BB@l
   bne       KdnetJtag_EccStore

KdnetJtag_EccMatch:
   # Put back the JTAG bytes at 2nd spare + 0xA. r4 + 0x10 + 0xA = 0x1A.
   li        %r11, JTAG_SC
   sth       %r11, 0x1A(%r4)
   # Switch the ECC word to the one that matches those bytes
   xoris     %r9, %r9, JTAG_ECC_FIX@h
   xori      %r9, %r9, JTAG_ECC_FIX@l

KdnetJtag_EccStore:
   # do what we patched and branch back
   stwbrx    %r9, %r7, %r4
	KMAKEBRANCH (SfcxEncodeECC_Store + 4)
9:

# ==================================================================
# SfcxFinishFlashPassThrough hook, replaces the lwz r11, 0x10(r28)
#
# Runs when a flash command finishes. r25 is the SFCX status register, r31
# is the request (+0 = flash address, the %08x in its error messages). Later
# in the function, (status & 0x1C) >= 0x10 is an uncorrectable ECC error:
# "SFCX: ECC error to address %08x", STATUS_IO_DEVICE_ERROR (0xC0000185).
# Clearing bit 0x10 turns that into a correctable result for address 0. r25
# is also saved to the request at +0xC, so callers see the cleared value too.
#
# r3 is free (loaded from 0x18(r31) a few instructions later), and so is cr0.
# ==================================================================
KMAKEPATCH SfcxFinishFlashPassThrough_Ld
0:
	KMAKEBRANCH KdnetJtagFlashCave
9:

KMAKEPATCH KdnetJtagFlashCave
0:
   lwz       %r3, 0(%r31)              # request flash address
   cmplwi    %r3, 0
   bne       KdnetJtag_FlashOrig
   rlwinm    %r25, %r25, 0, 28, 26     # r25 &= ~0x10

KdnetJtag_FlashOrig:
   # do what we patched and branch back
   lwz       %r11, 0x10(%r28)
	KMAKEBRANCH (SfcxFinishFlashPassThrough_Ld + 4)
9:

# ==================================================================
# SfcxSynchronousWriteInternal
#
# After writing, this reads the pages back. For each page it checks that the
# first 12 spare bytes (RtlCompareMemory(..., 0xC) == 0xC) and the 6-bit
# block type match what the caller passed. If not, it fails with
# "SFCX: read-back validation failed for %08x" (0xC005000F). The JTAG page
# never matches because SfcxEncodeECC changed bytes 0xA-0xB, so both
# branches are removed. The SHA-1 check of the page data afterwards stays.
# ==================================================================
KMAKEPATCH 0x800B7578                  # bne cr6, fail (spare bytes 0x0-0xB)
0:
   nop
9:

KMAKEPATCH 0x800B758C                  # bne fail (block type)
0:
   nop
9:
