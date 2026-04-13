# Fuck if I know if this is accurate :)

.include "macros.S"

#============================================================================
# Extend the size of CD
#============================================================================ 
MAKEPATCH 0x0000000C
0:
	.long 0x00005830
9:

#============================================================================
# Print an exclamation mark to UART to show we've reached CD
#============================================================================ 
MAKEPATCH 0x00000260
0:
	MAKEBRANCHL 0x5778
9:

MAKEPATCH 0x000003E0
0:
	MAKEBRANCHL 0x57a8
9:

#============================================================================
# Jump to the patch engine before starting the kernel
#============================================================================ 
MAKEPATCH 0x000005A4
0:
	MAKEBRANCH 0x57b4
9:

#============================================================================
# vfuse patch
#============================================================================
MAKEPATCH 0x00000940
0:
	addi %r11, %r11, 1
9:

MAKEPATCH 0x00000948
0:
	cmpwi cr6, %r11, 0xc
	addi %r9, %r9, 0x3360
9:

MAKEPATCH 0x00005778
0:
	li %r3, 0x2e
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

	li %r3, 0x200
	blr

loc_57a8:
	lis %r3, 1

# this is 6C40 in the jasper jtag patch set for some reason
	ori %r3, %r3, 0x6500
	blr

loc_57b4:
	mfmsr %r7
	li %r8, 0x10
	andc %r8, %r7, %r8
	lis %r3, -0x8000

# 57c4
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x2000
	addi %r3, %r3, -4

loc_57d4:
	mtmsrd %r8
	isync
	lwzu %r4, 4(%r3)
	cmpwi %r4, -1

# 57e4
	beq loc_581c
	addi %r4, %r4, -4
	lwzu %r6, 4(%r3)
	mtctr %r6

loc_57f4:
	mtmsrd %r8
	isync
	lwzu %r6, 4(%r3)
	mtmsrd %r7
	isync
	stwu %r6, 4(%r4)
	dcbst 0, %r4
	icbi 0, %r4
	bdnz loc_57f4
	b loc_57d4

loc_581c:
	sync
	isync
	rfid
	.long 0x00000000
	.long 0x00000000
9:

.ifdef rgloader

#============================================================================
# NOP out the call to post_output for 0x50/0x51 (load patch slot)
#============================================================================
MAKEPATCH 0x00000DD4
0:
	nop
9:

#============================================================================
# Disable panic 0xB3 (5BL signature check)
#============================================================================
MAKEPATCH 0x00000C48
0:
	nop
9:

#============================================================================
# Disable panic 0xB4 (5BL decompression panic)
#============================================================================
MAKEPATCH 0x00000C7C
0:
	nop
9:

#============================================================================
# Disable panic 0xB5 (VERIFY_OFFSET_6BL)
#============================================================================
MAKEPATCH 0x00000D28
0:
	nop
9:

#============================================================================
# Disable panic 0xB6 (DECODE_FUSES)
#============================================================================
MAKEPATCH 0x000009CC
0:
	nop
9:

#============================================================================
# Skip loading patch slots
#============================================================================
MAKEPATCH 0x00000D88
0:
	nop
	nop
	nop
	MAKEBRANCH 0xE10
9:

#============================================================================
# Disable panic 0xB7 (UPDATE_MISSING)
#============================================================================
MAKEPATCH 0x00000E28
0:
	nop
9:

#============================================================================
# I really don't know what this does but it's in the RGL jtag patch set
# and it's at the end of the function that loads the patch sets and such
#============================================================================
MAKEPATCH 0x00000E30
0:
	li %r4, 0
9:

# This is just some empty space
MAKEPATCH 0x00001024
0:
	or %r11, %r11, %r10
	xori %r11, %r11, 1
	MAKEBRANCH 0xE40
9:

MAKEPATCH 0x00000E3C
0:
	MAKEBRANCH 0x1024
9:

.endif

# done with patch section

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
