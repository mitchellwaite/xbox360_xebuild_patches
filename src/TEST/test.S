.include "macros.S"

#============================================================================
# SataDiskAuthenticateDevice Disable Harddisk Authentication                 
#============================================================================
KMAKEPATCH 0x8015d9d8
0:
	li      %r3, 1
	blr
9:


#============================================================================
# six seven patch for 6717                 
#============================================================================

.set KRNL_VER, 0x1A6F

MAKEPATCH 0x00000002
0:
	.short KRNL_VER
	.short 0
9:

MAKEPATCH 0x00002A48
0:
	lis     %r11, 0x0760
	lis     %r10, KRNL_VER
9:

KMAKEPATCH 0x80040002
0:
	.short KRNL_VER
	.short 0
9:

KMAKEPATCH 0x8004040C
0:
	.short KRNL_VER
	.short 0
9:

KMAKEPATCH 0x80040430
0:
	.short KRNL_VER
	.short 0
9: