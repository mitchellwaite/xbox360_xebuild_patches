.include "macros.S"

.globl _start
_start:

#==================================================================================
#	Disables branch leading to further checks potentially resulting in:
#	Panic 0xA0 - VERIFY_SECOTP_6 - Verify 2BL Revocation - 2BL LDV mismatch 
#==================================================================================
MAKEPATCH 0x00004DF4
0:
	nop
9:

#==================================================================================
#	Disables Panic 0xA3 - Verify Secure ROM 9 - VERIFY_SECOTP_9
#	bne cr6, loc_6B08 -> nop
#	cmplwi cr6, r30, 0x3000 -> nop
#	bne cr6, loc_6B08 -> nop
#
# cOz notes: remove smc size limitation
#==================================================================================
MAKEPATCH 0x00004F50
0:
	nop
	nop
	nop
9:

#==================================================================================
#	Disables Panic 0xAD - 4BL Signature Verify - SHA_VERIFY_4BL - Disable CD hash check
#	bl XeCryptMemDiff -> li r3, 0
#==================================================================================
MAKEPATCH 0x00005660
0:
	li %r3, 0
9:

.ifdef vfuses

.set XeCryptCopyQwVec,		0x5750	# XeCryptCopyQwVec(VOID *dest, VOID *src, DWORD len) ; len is in number of 64bit reads
.set qwSbFlashAddrOff,		0x258
.set dwSysUpdateAddr,		0x64
.set dwSysUpdateSlotSize,	0x70
.set fusesSize,				0xC

MAKEPATCH 0x000067E4
0:
	ld %r3, qwSbFlashAddrOff(%r29)
	lwz %r4, dwSysUpdateAddr(%r3)
	lwz %r5, dwSysUpdateSlotSize(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL	XeCryptCopyQwVec
9:

MAKEPATCH 0x00006BE0
0:
	ld %r3, 0x258(%r26)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL	XeCryptCopyQwVec
9:

MAKEPATCH 0x00000410
0:
	li %r4, 0x601
9:
.endif



#============================================================================
	.long 0xFFFFFFFF
	.end
#============================================================================
