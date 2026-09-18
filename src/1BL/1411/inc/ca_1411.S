# Patches based on reverse engineering and the release from cOz at https://github.com/cOzInABox/XeBuild/blob/main/patches/base_jtag/ca_1BL_all.S

.include "macros.S"

#============================================================================
# patch entry point for exclamation mark output on uart                                   
#============================================================================
MAKEPATCH 0x00000104
0:
	BLMAKEBRANCHL UartDot
9:

#============================================================================
# change address to that of the in ram/copied 1BL                            
#============================================================================
MAKEPATCH 0x000030B0
0:
	li %r4, 0
9:

#============================================================================
# Live patch the 2BL before we jump to it                            
#============================================================================
MAKEPATCH 0x0000339C
.set CopyPatchesDone, (PatchAddr+4)
0:
	BLMAKEBRANCH CopyPatches
9:

#============================================================================
# Load 2BL from where freeboot puts it rather than 0x8000
#============================================================================
MAKEPATCH 0x000042AC
.set FixCBAddrDone, (PatchAddr+4)
0:
	BLMAKEBRANCH FixCBAddr
9:

#============================================================================
# utility functions                                                          
#============================================================================
MAKEPATCH 0x00007E88
.set UartDot, PatchAddr
.set FixCBAddr, (PatchAddr + (1f - 0f))
.set CopyPatches, (PatchAddr + (2f - 0f))
0:
	li %r3, '!'
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 0xea00
	slwi %r3, %r3, 0x18
	stw %r3, 0x1014(%r4)

wait_for_character_sent:   
	lwz %r3, 0x1018(%r4)
	rlwinm. %r3, %r3, 0, 6, 6
	beq wait_for_character_sent
	li %r3, 0
	blr

# FixCBAddr
# Patches the 1BL to load the next stage (aka CB) from 0xD5060
1:
	lis %r25, 0xD
	ori %r25, %r25, 0x5060
	MAKEBRANCH FixCBAddrDone

# CopyPatches
2:
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100		# 0x80000000_00010000
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 1			# 0x80000200_00010000
	addi %r3, %r3, -4
	addi %r4, %r4, -4

copyPatchLoop:
	lwzu %r5, 4(%r3)
	cmpwi %r5, -1
	beq copyFuses
	add %r5, %r4, %r5
	lwzu %r6, 4(%r3)
	mtctr %r6

copyloop:
	lwzu %r6, 4(%r3)
	stwu %r6, 4(%r5)
	bdnz copyloop
	b copyPatchLoop

copyFuses:
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x3000		# 0x80000000_01003000
	lis %r4, -0x8000 
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 1
	ori %r4, %r4, 0x9b00		# 0x80000200_00019B00
	li %r5, 0

copyFuseLoop:
	ld %r6, 0(%r3)
	stdx %r6, %r4, %r5
	addi %r3, %r3, 8
	addi %r5, %r5, 8
	cmpldi %r5, 0x60
	blt copyFuseLoop

	lis %r3, -0x8000
	ori %r3, %r3, 0x200
	sldi %r3, %r3, 0x20
	isync
	mtspr SPR_HRMOR, %r3
	isync

	# Do the thing we patched
	li %r0, 0
	MAKEBRANCH CopyPatchesDone
9:

# done with patch section

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
