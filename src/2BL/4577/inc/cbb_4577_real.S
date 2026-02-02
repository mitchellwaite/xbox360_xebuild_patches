#============================================================================
# Note: this is how i would have liked to do the 4577 patch (aka exactly
# like 5772/6752), but 4577 likes to throw a fusecheck panic when extended
# to the same size as 5772. Easier to disable the fusecheck altogether until
# i find a zephyr i can wire up a postcode reader to
#============================================================================

.include "macros.S"

.globl _start
_start:

#============================================================================
# extend the ldr size to make CB_B 4577 compatible with the standard EXT_CLK
# timing files that assume CB_B 5772
#============================================================================

# set the size in the header of the CB_B
MAKEPATCH 0xc
0:
	.long 0x9350
9:

# add a dummy nop to the last byte to make XeBuild happy
MAKEPATCH 0x934C
0:
   nop
9:

.ifdef vfuses
MAKEPATCH 0x00000410
0:
	li %r4, 0x601
9:

MAKEPATCH 0x0000679C
0:
	ld %r3, 0x258(%r30)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL 0x5E70
9:
.endif

#==================================================================================
#	Disables branch leading to further checks potentially resulting in:
#	Panic 0xA0 - VERIFY_SECOTP_6 - Verify 2BL Revocation - 2BL LDV mismatch 
#	bne cr6, loc_6954 -> nop
#==================================================================================
# 00 00 69 44 00 00 00 01 60 00 00 00 
MAKEPATCH 0x000054A4
0:
	nop
9:

#==================================================================================
#	Disables Panic 0xA3 - Verify Secure ROM 9 - VERIFY_SECOTP_9
#	bne cr6, loc_5620 -> nop
#	cmplwi cr6, r29, 0x3000 -> nop
#	bne cr6, loc_5620 -> nop
#==================================================================================
# 00 00 6A A0 00 00 00 03 60 00 00 00 60 00 00 00 60 00 00 00 
MAKEPATCH 0x00005600
0:
	nop
	nop
	nop
9:

.ifdef vfuses
MAKEPATCH 0x000056F8
0:
	ld %r3, 0x258(%r26)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL 0x5E70
9:
.endif

#==================================================================================
#	Disables Panic 0xAD - 4BL Signature Verify - SHA_VERIFY_4BL - Disable CD hash check
#	bl XeCryptMemDiff -> li r3, 0
#==================================================================================
# 00 00 71 B0 00 00 00 01 38 60 00 00
MAKEPATCH 0x00005D98
0:
	li %r3, 0
9:

#============================================================================
	.long 0xFFFFFFFF
	.end
#============================================================================

