# Fuck if I know if this is accurate :)

.include "macros.S"

MAKEPATCH 0x000005B4
0:
	b 0x4c10
9:

MAKEPATCH 0x00000830
0:
	nop
9:

MAKEPATCH 0x00000990
0:
	nop
9:

MAKEPATCH 0x00000A8C
0:
	b 0x4564
9:

# Allow empty patch slots
MAKEPATCH 0xE30
0:
    b 0x14
9:

MAKEPATCH 0x00004F20
0:
# this is a bunch of LONGs for hardware init
   # pci-pci bridge
	.long 0xD0000010
	.long 0xEA000000
	.long 0x00000156

   # host bridge
	.long 0xD0008010
	.long 0xe0000000
	.long 0x00000002

   # GPU
   .long 0xD0010010
	.long 0xec800000
	.long 0x00000002

   # 1414:5801
   .long 0xD0100010
	.long 0xEA001800
	.long 0x00000002

   # SATA (1)
	.long 0xD0108010
   .long 0xEA001200
	.long 0x00000006

   # SATA (2)
	.long 0xD0108014
	.long 0xEA001220
	.long 0x00000006

   # SATA (3)
	.long 0xD0110010
	.long 0xEA001300
	.long 0x00000006

   # SATA (4)
	.long 0xD0110014
	.long 0xEA001320
	.long 0x00000006

   # USB (1)
	.long 0xD0120010
	.long 0xEA002000
	.long 0x00000156

   # USB (2)
	.long 0xD0121010
	.long 0xEA003000
	.long 0x00000106

   # USB (3)
	.long 0xD0128010
	.long 0xEA004000
	.long 0x00000156

   # USB (4)
	.long 0xD0129010
	.long 0xEA005000
	.long 0x00000106

   # Ethernet
	.long 0xD0138010
	.long 0xEA001400
	.long 0x00000006

   # System Flash Controller (1)
	.long 0xD0140010
	.long 0xEA00C000
	.long 0x00000006

   # System Flash Controller (2)
	.long 0xD0140014
	.long 0xC8000000
	.long 0x00000006

   # Audio
	.long 0xD0148010
	.long 0xEA001600
	.long 0x00000006

   # SMC
	.long 0xD0150010
	.long 0xEA001000
	.long 0x00000002

   # End of list!
   #.long 0x00000000
9:

MAKEPATCH 0x00004FF0
0:
	clrldi %r27, %r22, 0x20
	mflr %r12
	mfmsr %r7
	li %r8, 0x10
	andc %r8, %r7, %r8
	mtmsrd %r8
	li %r3, 0x2e

	bl loc_525C
	bl loc_525C

	li %r8, 0x200
	oris %r8, %r8, 0x8000
	sldi %r8, %r8, 0x20
	oris %r8, %r8, 0xea00
	lis %r9, 0x400
	lis %r10, 0x100
	li %r11, 0
	stw %r9, 0x1084(%r8)
	stw %r10, 0x1080(%r8)
	stw %r11, 0x1080(%r8)
	stw %r11, 0x1080(%r8)
	stw %r11, 0x1080(%r8)
	stw %r11, 0x1084(%r8)

smc_handshake_loop:
	lwz %r12, 0x1094(%r8)
	and. %r12, %r12, %r9
	beq smc_handshake_loop
	stw %r9, 0x1094(%r8)
	lwz %r12, 0x1090(%r8)
	lwz %r3, 0x1090(%r8)
	lwz %r3, 0x1090(%r8)
	lwz %r3, 0x1090(%r8)
	stw %r11, 0x1094(%r8)
	srwi %r3, %r12, 0x18
	cmpwi %r3, 1
	bne smc_handshake_loop

# Get the powerup cause from the SMC
	rlwinm %r3, %r12, 0x10, 0x18, 0x1f
	cmpwi %r3, 0
	beq start_kernel
	li %r5, 0x200
	oris %r5, %r5, 0x8000
	sldi %r5, %r5, 0x20
	oris %r5, %r5, 0xc800
	lbz %r4, 0x4f(%r5)
	cmplw %r3, %r4
	beq load_xell
	lbz %r4, 0x4e(%r5)
	cmplw %r3, %r4
	beq load_xell

start_kernel:
	mtmsrd %r7
	mtlr %r12
	b -0x4624

loc_50B8:
	lis %r3, -0x8000
	ori %r3, %r3, 0x17c
	sldi %r3, %r3, 0x20
	oris %r3, %r3, 0x400
	ori %r3, %r3, 0x4f1c
	li %r30, 0x200
	oris %r30, %r30, 0x8000
	sldi %r30, %r30, 0x20

loc_50D8:   
	lwzu %r4, 4(%r3)
	cmplwi %r4, 0
	beqlr
	lwzu %r31, 4(%r3)
	stwbrx %r31, %r30, %r4
	li %r31, 0xff
	andc %r4, %r4, %r31
	ori %r4, %r4, 4
	lwbrx %r31, %r30, %r4
	lwzu %r29, 4(%r3)
	or %r31, %r31, %r29
	stwbrx %r31, %r30, %r4
	b loc_50D8

load_xell:   
	li %r7, 0x200
	oris %r7, %r7, 0x8000
	sldi %r7, %r7, 0x20
	oris %r7, %r7, 6
	ori %r7, %r7, 0x1010

# set POST code 0x10
	li %r3, 0x10
	sldi %r3, %r3, 0x38
	std %r3, 0(%r7)

	li %r3, 0x3d
	bl loc_525C
	bl loc_50B8
	li %r3, 0x3d
	bl loc_525C

# Construct the address to XeLL in the memory mapped NAND space   
	li %r5, 0x200
	oris %r5, %r5, 0x8000
	sldi %r5, %r5, 0x20
	oris %r5, %r5, 0xc807
	mr %r5, %r5
	lis %r6, -0x8000
	sldi %r6, %r6, 0x20
	oris %r6, %r6, 0x1c00
	mr %r9, %r6
	mtspr 0x139, %r11

# set POST code 0x11
	li %r3, 0x11
	sldi %r3, %r3, 0x38
	std %r3, 0(%r7)

	lis %r4, 1
	mtctr %r4

xell_copy_loop:
	lwz %r8, 0(%r5)
	stw %r8, 0(%r6)
	dcbst 0, %r6
	icbi 0, %r6
	sync
	isync
	addi %r6, %r6, 4
	addi %r5, %r5, 4
	bdnz xell_copy_loop

# set post code 0x12
	li %r3, 0x12
	sldi %r3, %r3, 0x38
	std %r3, 0(%r7)

# Jump to XeLL
	li %r4, 0x30
	mfmsr %r3
	andc %r3, %r3, %r4
	mtspr 0x1b, %r3
	mtspr 0x1a, %r9
	rfid


# TODO this looks like the patching engine
	mfmsr %r7
	li %r8, 0x10
	andc %r8, %r7, %r8
	mtmsrd %r8

   # Something goes here?

	li %r5, 0x200
	oris %r5, %r5, 0x8000
	sldi %r5, %r5, 0x20
	oris %r5, %r5, 0xc800
   lwz %r4, 0x64(%r5) # Patch Slot Address
   lwz %r3, 0x70(%r5) # Patch Slot Size
   add %r4, %r4, %r3 # Skip First Patch Slot
	add %r4, %r4, %r5
	addi %r3, %r4, 0x5c
	isync

loc_51F8:
	mtmsrd %r8
	isync
	lwzu %r4, 4(%r3)
	cmpwi %r4, -1
	beq loc_5240


	addi %r4, %r4, -4
	lwzu %r6, 4(%r3)
	mtctr %r6

loc_5218:   
	mtmsrd %r8
	isync
	lwzu %r6, 4(%r3)
	mtmsrd %r7
	isync
	stwu %r6, 4(%r4)
	dcbst 0, %r4
	icbi 0, %r4
	bdnz loc_5218
	b loc_51F8

loc_5240:   
	mtmsrd %r8 
	li %r3, 0x2e
	bl loc_525C
	sync
	isync
	mtmsrd %r7
	rfid

 loc_525C: 
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 0xea00
	slwi %r3, %r3, 0x18
	stw %r3, 0x1014(%r4)
	sync
	isync

loc_527C:
	lwz %r3, 0x1018(%r4)
	rlwinm. %r3, %r3, 0, 6, 6
	beq loc_527C
	blr
9:

# done with patch section

#============================================================================
.long 0xFFFFFFFF
.end
#============================================================================
