#;—————————————————————————————————————————————————————————————————————————————
#;   2BL / CB 5771 (Falcon)                                                    
#;                                               
#; Thanks to cOz for releasing the patch sources, this is based on reverse engineering
#; and the sources from the following:\
#;
#; https://github.com/cOzInABox/XeBuild/blob/main/patches/base_jtag/cb_5771_falcon.S                                        
#;—————————————————————————————————————————————————————————————————————————————

.include "macros.S"

.set CB_ORIG_SIZE, 0x00009340
.set FixAddr3dest, 0x00006F20

	.globl _start
_start:

#==================================================================================
# Extend the size of the loader
#==================================================================================
MAKEPATCH 0x0000000C
0:
	.long (CB_ORIG_SIZE+UTILSIZE)
9:

#==================================================================================
# Print an @ symbol to indicate we've reached CB
#==================================================================================
MAKEPATCH 0x000003C0
0:
	MAKEBRANCHL 0x9340
9:

#==================================================================================
# Replaces a bunch of li rXX, 0x17A instructions with a 0 immediate value
#
# Note from the cOz release: this fixes reloc addresses
#==================================================================================
MAKEPATCH 0x00000510
0:
	li %r25, 0
9:

MAKEPATCH 0x00000614
0:
	li %r4, 0
9:

MAKEPATCH 0x00000720
0:
	li %r26, 0
9:

#;============================================================================
#; fix CD flash address                                                       
#;============================================================================
MAKEPATCH 0x00000764
0:
	MAKEBRANCH 0x9388
9:

#==================================================================================
# Replaces a bunch of li rXX, 0x17A instructions with a 0 immediate value
#
# Note from the cOz release: this fixes reloc addresses
#==================================================================================
MAKEPATCH 0x000064D8
0:
	li %r3, 0
9:

MAKEPATCH 0x00006504
0:
	li %r3, 0
9:

MAKEPATCH 0x00006534
0:
	li %r4, 0
9:

#==================================================================================
# Branch to the patch engine
#==================================================================================
MAKEPATCH 0x0000655C
0:
	MAKEBRANCH 0x9398
9:

#==================================================================================
# vfuse patch
#==================================================================================
MAKEPATCH 0x00006704
0:
	MAKEBRANCHL 0x9370
9:

MAKEPATCH 0x00006718
0:
	addi %r11, %r11, 1
9:

MAKEPATCH 0x00006720
0:
	cmpwi cr6, %r11, 0xc
9:

#==================================================================================
# Disable branches leading to panics 0xA2, 0xA3 (VERIFY_SECOTP_8, VERIFY_SECOTP_9)
#
# Note from cOz release: remove smc size restriction
#==================================================================================
MAKEPATCH 0x00006A18
0:
	nop
	nop
	nop
9:

#==================================================================================
# vfuse patch
#==================================================================================
MAKEPATCH 0x00006B00
0:
	MAKEBRANCHL 0x9370
9:

MAKEPATCH 0x00006B18
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

#==================================================================================
# skip hwinit
#==================================================================================
MAKEPATCH 0x00006D30
0:
	nop
9:

#==================================================================================
# vfuse patch
#==================================================================================
MAKEPATCH 0x000070C0
0:
	MAKEBRANCHL 0x937C
9:

MAKEPATCH 0x000070D0
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

#==================================================================================
# skip computation of 4BL hash
#==================================================================================
MAKEPATCH 0x00007130
0:
	nop
9:

#==================================================================================
# loadfare generated patches
# - disable entire fuse check routine in the cb
# - disable smc hash check
#==================================================================================
MAKEPATCH 0x000004D0
0:
	nop
9:

MAKEPATCH 0x000071B8
0:
	b 0x14
9:

MAKEPATCH CB_ORIG_SIZE
	.set UartDot, PatchAddr
	.set FixFuseAddr1, (PatchAddr + (1f - 0f))
	.set FixFuseAddr2, (PatchAddr + (2f - 0f))
	.set FixCdAddr, (PatchAddr + (3f - 0f))
	.set CopyPatches, (PatchAddr + (4f - 0f))
	.set UTILSIZE, (9f - 0f)
0:
# print an @ symbol to UART
	li %r3, '@'
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

# do the thing we patched
	lis %r3, 0x100
	blr

# 0x9370
# fuse fixer 1
1:
	addis %r31, %r11, 2
	addi %r31, %r31, -0x6500 # 0x9B00
	blr

# 0x937C
# fuse fixer 2
2:
	addis %r9, %r10, 2
	addi %r9, %r9, -0x6500 # 0x9B00
	blr

# Fix CD address
3:
	li %r24, 0
	ori %r24, %r24, 0x9340
	stw %r24, 0(%r8)
	MAKEBRANCH 0x6f20

# 9398
# CopyPatches
4:
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x1000
	lis %r4, -0x8000
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 0x400
	addi %r3, %r3, -4
	addi %r4, %r4, -4

copyPatchIter:	
	lwzu %r5, 4(%r3)
	cmpwi %r5, -1
	beq done

	add %r5, %r4, %r5
	lwzu %r6, 4(%r3)
	mtctr %r6

copyPatchLoop:
	lwzu %r6, 4(%r3)
	stwu %r6, 4(%r5)
	bdnz copyPatchLoop
	b copyPatchIter

done:
	blr
	.long 0x00000000
	.long 0x00000000
9:

# done with patch section

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
