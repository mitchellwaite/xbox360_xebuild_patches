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
# Print a character to UART to show we've reached CD
#============================================================================ 
MAKEPATCH 0x00000260
0:
	MAKEBRANCHL 0x5778
9:

#============================================================================
# Jump to a function that adjusts the next BL location to load 5BL from
# the standard spot in NAND rather than from directly after the JTAG CD
#============================================================================
.ifdef jtag_5bl_offset 
MAKEPATCH 0x000003E0
0:
	MAKEBRANCHL 0x57a8
9:
.endif

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
	li %r3, '#'
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
.ifdef jtag_5bl_offset
	ori %r3, %r3, jtag_5bl_offset
.else
	nop
.endif
	blr

loc_57b4:
	mfmsr %r7
	li %r8, 0x10
	andc %r8, %r7, %r8
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x2000
	addi %r3, %r3, -4

loc_57d4:
	mtmsrd %r8
	isync
	lwzu %r4, 4(%r3)
	cmpwi %r4, -1 # If we're seeing 0xFFFFFFFF we're done patching

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

#============================================================================
# Disable panic 0xB1 (VERIFY_OFFSET)
#============================================================================
MAKEPATCH 0x00000AA8
0:
	nop
9:

#============================================================================
# Disable panic 0xB2 (VERIFY_OFFSET)
#============================================================================
MAKEPATCH 0x00000AEC
0:
	nop
9:

MAKEPATCH 0x00000B00
0:
	nop
9:

MAKEPATCH 0x00000B10
0:
	nop
9:

MAKEPATCH 0x00000B24
0:
	MAKEBRANCH 0x00000B38
9:

#============================================================================
# Disable panic 0xB3 (5BL signature check)
#============================================================================
MAKEPATCH 0x00000C38
0:
	b 0x14
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
MAKEPATCH 0x00000CDC
0:
	nop
9:

MAKEPATCH 0x00000CEC
0:
	nop
9:

MAKEPATCH 0x00000CF8
0:
	nop
9:

MAKEPATCH 0x00000D04
0:
	nop
9:

MAKEPATCH 0x00000D18
0:
	MAKEBRANCH 0xD2C
9:

#============================================================================
# Disable panic 0xB6 (DECODE_FUSES) by disabling fusechecks in CD
#============================================================================
MAKEPATCH 0x00000C98
0:
	li %r3, 0
9:

.ifdef skip_patch_slots
#============================================================================
# NOP out the call to post_output for 0x50/0x51 (load patch slot)
#============================================================================
MAKEPATCH 0x00000DD4
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
.endif

#============================================================================
# Disable panic 0xB7 (UPDATE_MISSING)
#============================================================================
MAKEPATCH 0x00000E28
0:
	nop
9:

#============================================================================
# TODO: I really don't know why RGL has this patch, it effectively means we'll
# write 0x00 to the POST bus rather than 0x52 when we branch to 5BL
#============================================================================
MAKEPATCH 0x00000E30
0:
	li %r4, 0
9:

# =================================================================================
# remove unpaired bit from bootloader flags
# TODO is this even needed when all the hypervisors have flag fixers?
# =================================================================================
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

# done with patch section

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
