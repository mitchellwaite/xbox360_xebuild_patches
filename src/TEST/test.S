.include "macros.S"

#============================================================================
# SataDiskAuthenticateDevice Disable Harddisk Authentication                 
#============================================================================
KMAKEPATCH 0x8015d9d8
0:
	li      %r3, 1
	blr
9:
