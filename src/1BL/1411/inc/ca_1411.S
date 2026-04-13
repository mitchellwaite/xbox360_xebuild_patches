# Fuck if I know if this is accurate :)

.include "macros.S"

MAKEPATCH 0x00000104
0:
	# Prints an exclamation mark to show that our patched 1BL is running
	MAKEBRANCHL 0x7E88
9:

MAKEPATCH 0x000030B0
0:
	li %r4, 0
9:

MAKEPATCH 0x0000339C
0:
	# Live patch the 2BL before we jump to it
	MAKEBRANCH 0x7EC4
9:

MAKEPATCH 0x000042AC
0:
   # Load 2BL from where freeboot puts it rather than 0x8000
	MAKEBRANCH 0x7EB8
9:

MAKEPATCH 0x00007E88
0:
print_dot_uart:
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
	li %r3, 0
	blr

# Patches the 1BL to load the next stage (aka CB) from 0xD5060
loc_7EB8:
	lis %r25, 0xD
	ori %r25, %r25, 0x5060
	MAKEBRANCH 0x42B0

loc_7EC4:
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 1
	addi %r3, %r3, -4
	addi %r4, %r4, -4

loc_7ee8:
	lwzu %r5, 4(%r3)
	cmpwi %r5, -1
	beq loc_7F10
	add %r5, %r4, %r5
	lwzu %r6, 4(%r3)
	mtctr %r6

loc_7F00:
	lwzu %r6, 4(%r3)
	stwu %r6, 4(%r5)
	bdnz loc_7F00
	b loc_7ee8

loc_7F10:
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x3000
	lis %r4, -0x8000 
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 1
	ori %r4, %r4, 0x9b00
	li %r5, 0

loc_7f38:
	ld %r6, 0(%r3)
	stdx %r6, %r4, %r5
	addi %r3, %r3, 8
	addi %r5, %r5, 8
	cmpldi %r5, 0x60
	blt loc_7f38

	lis %r3, -0x8000
	ori %r3, %r3, 0x200
	sldi %r3, %r3, 0x20
	isync
	mtspr 0x139, %r3
	isync

	# Do the thing we patched
	li %r0, 0
	MAKEBRANCH 0x33A0
9:

# done with patch section

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
