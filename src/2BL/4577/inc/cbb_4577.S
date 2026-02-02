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

# add a dummy nop to the CB_B, making it 0x9350 bytes long
MAKEPATCH 0x934C
0:
   nop
9:

#==================================================================================
# Disable all fusecheck related panics + the SMC sum panic
# It's a bit overkill, but there aren't any observed side effects for glitch2m.
# Credits to wurthless-electroniks.
#==================================================================================
MAKEPATCH 0x000004D0
0:
	nop
9:

#==================================================================================
#	Disables Panic 0xAD - 4BL Signature Verify - SHA_VERIFY_4BL (CD hash check)
#==================================================================================
MAKEPATCH 0x00005DA0
0:
	b 0x14
9:

#============================================================================
	.long 0xFFFFFFFF
	.end
#============================================================================

