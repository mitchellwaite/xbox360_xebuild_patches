.include "macros.S"

# This is a fixed version of the nointmu patch that correctly disables trinity and corona internal memory units

#;============================================================================
#; SfcxMuMountStorage, disable nand mu
#; lis     %r10, 0x3000
#;============================================================================
KMAKEPATCH 0x8008D080
0:
	lis     %r10, 0x6000
9:

#;============================================================================
#; MassDriverEntry, disable internal usb mu
#; lis       r10, 0x4000
#;============================================================================
KMAKEPATCH 0x800e2024
0:
	lis     %r10, 0x6000
9:

#;============================================================================
#; MmcxMuMountStorage, disable corona memory unit 17559: 0x8008f3f8
#;============================================================================
KMAKEPATCH 0x8008E3A8
0:
	blr
9:
