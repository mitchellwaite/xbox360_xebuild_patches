.include "macros.S"

.globl _start
_start:

.ifdef vfuses
MAKEPATCH 0x00000410
0:
	li %r4, 0x601
9:

MAKEPATCH 0x0000679C
0:
	ld %r3, 0x258(%r29)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	bl 0xae8
9:
.endif

#==================================================================================
#	Disables branch leading to further checks potentially resulting in:
#	Panic 0xA0 - VERIFY_SECOTP_6 - Verify 2BL Revocation - 2BL LDV mismatch 
#	bne cr6, loc_6954 -> nop
#==================================================================================
# 00 00 69 44 00 00 00 01 60 00 00 00 
MAKEPATCH 0x00006944
0:
	nop
9:

#==================================================================================
#	Disables Panic 0xA3 - Verify Secure ROM 9 - VERIFY_SECOTP_9
#	bne cr6, loc_6AC0 -> nop
#	cmplwi cr6, r30, 0x3000 -> nop
#	bne cr6, loc_6AC0 -> nop
#==================================================================================
# 00 00 6A A0 00 00 00 03 60 00 00 00 60 00 00 00 60 00 00 00 
MAKEPATCH 0x00006AA0
0:
	nop
	nop
	nop
9:

.ifdef vfuses
MAKEPATCH 0x00006B98
0:
	ld %r3, 0x258(%r26)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	bl 0x6ec
9:
.endif

#==================================================================================
#	Disables Panic 0xAD - 4BL Signature Verify - SHA_VERIFY_4BL - Disable CD hash check
#	bl XeCryptMemDiff -> li r3, 0
#==================================================================================
# 00 00 71 B0 00 00 00 01 38 60 00 00
MAKEPATCH 0x000071B0
0:
	li %r3, 0
9:

#============================================================================
	.long 0xFFFFFFFF
	.end
#============================================================================

