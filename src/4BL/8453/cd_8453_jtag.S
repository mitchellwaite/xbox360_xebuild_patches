# Fuck if I know if this is accurate :)

.include "macros.S"

# Extend the size of the CD
MAKEPATCH 0x0000000C
0:
	.long 0x00005830
9:

MAKEPATCH 0x00000260
0:
	bl 0x5778
9:

MAKEPATCH 0x000003E0
0:
	bl 0x57a8
9:

MAKEPATCH 0x000005A4
0:
	b 0x57b4
9:

MAKEPATCH 0x00000940
0:
	addi %r11, %r11, 1
9:

MAKEPATCH 0x00000948
0:
	cmpwi cr6, %r11, 0xc
	addi %r9, %r9, 0x3360
9:

# Skip loading the patch slots
MAKEPATCH 0x00000DF4
0:
	li %r3, 0
9:

# Avoid panic 0xB7 (empty patch slots)
MAKEPATCH 0x00000E18
0:
	b 0x14
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

	lwz %r3, 0x1018(%r4)
	rlwinm. %r3, %r3, 0, 6, 6
	beq 0x5794

	li %r3, 0x200
	blr

	lis %r3, 1
	ori %r3, %r3, 0x6500
	blr

	mfmsr r7
	li %r8, 0x10
	andc %r8, r7, %r8
	lis %r3, -0x8000
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x100
	ori %r3, %r3, 0x2000
	addi %r3, %r3, -4
	mtmsrd %r8
	isync
	lwzu %r4, 4(%r3)
	cmpwi %r4, -1
	beq 0x581c
	addi %r4, %r4, -4
	lwzu r6, 4(%r3)
	mtctr r6
	mtmsrd %r8
	isync
	lwzu r6, 4(%r3)
	mtmsrd r7
	isync
	stwu r6, 4(%r4)
	dcbst 0, %r4
	icbi 0, %r4
	bdnz 0x57f4
	b 0x57d4
	sync
	isync
	rfid
	.long 0x00000000
	.long 0x00000000
9:

# done with patch section