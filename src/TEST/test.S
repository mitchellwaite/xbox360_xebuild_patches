.include "macros.S"

# 15574 test patch fix

MAKEPATCH 0x001106B8
0:
	bge 0x8
	blr
	lis %r3, 0x8011
	lis %r5, 0
	li %r4, 0
	ori %r4, %r4, 8
	ori %r3, %r3, 0x06e4
	li %r6, 0
	MAKEBRANCHL 0x7ca60
	li %r3, 0
	MAKEBRANCH 0x6139c
	.long   0x5C446576
	.long   0x6963655C
	.long   0x466C6173
	.long   0x685C6C61
	.long   0x756E6368
	.long   0x2E786578
	.long   0x00000000
9:

MAKEPATCH 0x0006138C
0:
	MAKEBRANCHL 0x001106B8
9: