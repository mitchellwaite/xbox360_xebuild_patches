# SD17489 patches for rgh2 XDK kernel 
# can be used on all rgh2 hadware revisons 

.include "macros.S"
.globl _start
_start:

.ifdef patchengine
#============================================================================
# Branch to CDXell... this replaces the first instruction at the entrypoint
# of the SD with a function call
#============================================================================   
MAKEPATCH 0x310 
0:
   bl 0x4c20 
9:

#============================================================================
# Rather than calling the rfid instruction to launch the kernel, branch to
# the patch engine to apply 
#============================================================================
MAKEPATCH 0x6B4  
0:
   b       0x4b48
9:

#============================================================================
# Replace the function call to 0xA58, effectively making it always return 0
# Blocks the fuse decode logic in the SD (POST 0x4D, panic 0xB6)
#============================================================================
MAKEPATCH 0xD28
0:
   li      %r3, 0
9:

#============================================================================
# Disable panic 0xB5 (VERIFY_OFFSET_6BL)
#============================================================================
MAKEPATCH 0xD7C 
0:
   nop
9:

.endif

#============================================================================
# Patch out SE hash check panic (Allows arbitrary SE/CE to run)
#============================================================================
MAKEPATCH 0xCE0
0:
   b       0x8
9:

.ifdef vfuses
#============================================================================
# read vfuses
#============================================================================
MAKEPATCH 0xA80
0:
   lis     %r3, 0x1800
   ori     %r3, %r3, 0
   lwz     %r4, 0x64(%r3)
   lwz     %r5, 0x70(%r3)
   add     %r3, %r3, %r4
   add     %r4, %r3, %r5
   mr      %r3, %r10
   li      %r5, 0xc
   bl      0x460
   nop 
9:
.endif

.ifdef patchengine
#============================================================================
# PCI init, SMC handshake, patching engine, Boot XeLL
# This section of the patch is based on CDXell
#============================================================================   
MAKEPATCH 0x4F30
0:
   # This section of the patch appears to skip UART 
   # init if NAND at 0x4D is set to 0   
   li      %r5, 0x200
   oris    %r5, %r5, 0x8000
   sldi    %r5, %r5, 32
   oris    %r5, %r5, 0xC800  # r5 pointing to memory mapped NAND: 0x80000200 0xC8000000
   lbz     %r4, 0x4D(%r5)
   isync
   cmplwi  %r4, 0
   beq     smc_init

# Enable UART
   lis     %r3, -0x51FF # 0xAE010000 -> set UART to 38400, 8, N, 1 (CYGNOS compatible??? this is what XeLL sets the reg to in cygnos mode)
   lis     %r4, -0x8000 
   ori     %r4, %r4, 0x200   
   sldi    %r4, %r4, 32
   oris    %r4, %r4, 0xEA00 # 0x80000200 0xEA00101C is the UART config register
   stw     %r3, 0x101C(%r4)

# SMC handshake
smc_init:            
   mflr    %r12
   bl      print_dot_uart
   mtlr    %r12
   li      %r8, 0x200
   oris    %r8, %r8, 0x8000
   sldi    %r8, %r8, 32
   oris    %r8, %r8, 0xEA00 # R8 -> SMC FIFO base address 
   lis     %r9, 0x400
   lis     %r10, 0x100 # SMC command 0x1 is GetPowerUpCause
   li      %r11, 0
   stw     %r9, 0x1084(%r8)   # start message
   stw     %r10, 0x1080(%r8)  # command 0x1 (GetPowerUpCause)
   stw     %r11, 0x1080(%r8)  # rest of the SMC message is blank 0x0
   stw     %r11, 0x1080(%r8)  #
   stw     %r11, 0x1080(%r8)  #
   stw     %r11, 0x1084(%r8)  # end message

smc_handshake_loop:            
   lwz     %r12, 0x1094(%r8) # Wait for a message
   and.    %r12, %r12, %r9
   beq     smc_handshake_loop
   stw     %r9, 0x1094(%r8)  # Start to read reply
   lwz     %r12, 0x1090(%r8) # First byte of the response is all we care about
   lwz     %r3, 0x1090(%r8)  # the rest of the reply are zeros... put them in r3
   lwz     %r3, 0x1090(%r8)
   lwz     %r3, 0x1090(%r8)
   stw     %r11, 0x1094(%r8) # end read reply
   srwi    %r3, %r12, 24     # shift right so we get the first byte of the reply in R3 (which should be 0x1)
   cmpwi   %r3, 1
   bne     smc_handshake_loop # If we got a bad reply... try again

# This is a list of valid powerup causes:
#
# class PowerUpCause(Enum):
#     POWER           = 0x11
#     EJECT           = 0x12
#     UNDOCUMENTED_15 = 0x15
#     UNDOCUMENTED_16 = 0x16
#     REMOPOWER       = 0x20
#     UNDOCUMENTED_21 = 0x21
#     REMOX           = 0x22
#     WINBUTTON       = 0x24
#     UNDOCUMENTED_30 = 0x30
#     UNDOCUMENTED_31 = 0x31
#     KIOSK           = 0x41
#     WIRELESSX       = 0x55
#     WIREDXF1        = 0x56
#     WIREDXF2        = 0x57
#     WIREDXB2        = 0x58
#     WIREDXB1        = 0x59
#     WIREDXB3        = 0x5A

# Get the powerup cause from the smc
   extrwi  %r3, %r12, 8,8
   cmpwi   %r3, 0
   beq     start_kernel
   lbz     %r4, 0x4F(%r5)
   cmplw   %r3, %r4
   beq     load_xell
   lbz     %r4, 0x4E(%r5)
   cmplw   %r3, %r4
   beq     load_xell

# Boot the kernel... no need to go further
# The bl to the beginning of this function
# replaces a lis instruction, so we'll do
# what was replaced and then branch back
# to where we left off
start_kernel:            
   lis     %r3, 0x300
   blr

load_xell:
   li      %r7, 0x200
   oris    %r7, %r7, 0x8000
   sldi    %r7, %r7, 32
   oris    %r7, %r7, 6
   ori     %r7, %r7, 0x1010 # r7 contains the base address for the POST bus  0x80000200_00061010

# Set post code 0x10
   li      %r3, 0x10
   sldi    %r3, %r3, 56
   std     %r3, 0(%r7)

# Initialize PCI devices before we jump to XeLL
   bl      pci_init

# Construct the address to XeLL in the memory mapped NAND space
# XeLL offset in NAND is different for each console type
# Corona is indeed the same offset as SB consoles. BB consoles (256/512)
# are a bit screwy with the location of the patch sets and such

# The offsets might not make sense to you. You might think, how tf is XeLL
# found at 0xC80F or 0xC8B8??? Well, fear not, this does actually make sense.
# On the Xbox 360, NAND is mapped in to memory at 0x80000200C8000000. See that
# C8? Well, that's the beginning of the NAND memory map. The 0F/B8 is the offset
# from the beginning of the logical NAND data- XeLL on a 16MB image lives at
# 0xF0000, in a BB image it lives at 0xB8000. The reason we can't just do a load
# immediate into the register is because 64-bit load immediates aren't a thing-
# all we get is the 16 bit li instruction so we get the rigamarole to load a 64-bit
# value into the register to point to the memory mapped location where XeLL lives
# Assembly is fun!

# Used if we're using SD 17489 to boot CE 1888
   .ifdef xell_C807
   .set xell_offset, 0xC807
   .endif

# 16mb/64mb SB/Corona BB: 0xF0000
   .ifdef xell_C80F
   .set xell_offset, 0xC80F
   .endif

# Jasper/Trinity BB: 0xB80000
   .ifdef xell_C8B8
   .set xell_offset, 0xC8B8
   .endif

   li      %r5, 0x200
   oris    %r5, %r5, 0x8000
   sldi    %r5, %r5, 32
.ifdef devgl64
   bl set_bits_for_xell_in_flashfs
.else
   oris    %r5, %r5, xell_offset  # XeLL loaction in flash changes for full flash fs vs. 16mb
.endif
   mr      %r5, %r5
   lis     %r6, -0x8000
   sldi    %r6, %r6, 32
   oris    %r6, %r6, 0x1C00
   mr      %r9, %r6
   mtspr   0x139, %r11

# Set post code 0x11
   li      %r3, 0x11
   sldi    %r3, %r3, 56
   std     %r3, 0(%r7)
   
   lis     %r4, 1
   mtctr   %r4 

xell_copy_loop:            
   lwz     %r8, 0(%r5)
   stw     %r8, 0(%r6)
   dcbst   %r0, %r6
   icbi    %r0, %r6
   sync
   isync
   addi    %r6, %r6, 4
   addi    %r5, %r5, 4
   bdnz    xell_copy_loop

# Set POST code 0x12 (XeLL is done loading)
   li      %r3, 0x12
   sldi    %r3, %r3, 56
   std     %r3, 0(%r7)

# Jump to XeLL
   li      %r4, 0x30 # '0'
   mfmsr   %r3
   andc    %r3, %r3, %r4
   mtsrr1  %r3
   mtsrr0  %r9
   rfid

pci_init:            
   lis     %r3, -0x8000
   ori     %r3, %r3, 0x17c   
   sldi    %r3, %r3, 32
   oris    %r3, %r3, 0x400
   ori     %r3, %r3, 0x50fC # Address of PCI_INIT_LIST. If code is added before the struct, this must be changed
   li      %r30, 0x200
   oris    %r30, %r30, 0x8000
   sldi    %r30, %r30, 32

pci_init_loop:            
   lwzu    %r4, 4(%r3)
   cmplwi  %r4, 0
   beqlr   # Return from the function when we hit the 0x00000000
   lwzu    %r31, 4(%r3)
   stwbrx  %r31, %r30, %r4
   li      %r31, 0xFF
   andc    %r4, %r4, %r31
   ori     %r4, %r4, 4
   lwbrx   %r31, %r30, %r4
   lwzu    %r29, 4(%r3)
   or      %r31, %r31, %r29
   stwbrx  %r31, %r30, %r4
   b       pci_init_loop
# End of function pci_init

PCI_INIT_LIST:
   .long 0xD0000010
   .long 0xEA000000
   .long 0x00000156
   .long 0xD0008010
   .long 0xE0000000
   .long 0x00000002
   .long 0xD0010010
   .long 0xEC800000
   .long 0x00000002
   .long 0xD0100010
   .long 0xEA001800
   .long 0x00000002
   .long 0xD0108010
   .long 0xEA001200
   .long 0x00000006
   .long 0xD0108014
   .long 0xEA001220
   .long 0x00000006
   .long 0xD0110010
   .long 0xEA001300
   .long 0x00000006
   .long 0xD0110014
   .long 0xEA001320
   .long 0x00000006
   .long 0xD0120010
   .long 0xEA002000
   .long 0x00000156
   .long 0xD0121010
   .long 0xEA003000
   .long 0x00000106
   .long 0xD0128010
   .long 0xEA004000
   .long 0x00000156
   .long 0xD0129010
   .long 0xEA005000
   .long 0x00000106
   .long 0xD0138010
   .long 0xEA001400
   .long 0x00000006
   .long 0xD0140010
   .long 0xEA00C000
   .long 0x00000006
   .long 0xD0140014
   .long 0xC8000000
   .long 0x00000006
   .long 0xD0148010
   .long 0xEA001600
   .long 0x00000006
   .long 0xD0150010
   .long 0xEA001000
   .long 0x00000002
   .long 0x00000000

print_dot_uart:            
   li      %r3, 0x2E       # ASCII 0x2E (.) 
   lis     %r4, -0x8000 
   ori     %r4, %r4, 0x200   
   sldi    %r4, %r4, 32
   oris    %r4, %r4, 0xEA00 # SMC base address 0xEA000000
   slwi    %r3, %r3, 24
   stw     %r3, 0x1014(%r4) # 0xEA001014 == UART data register

wait_for_character_sent:            
   lwz     %r3, 0x1018(%r4) # wait until the character we sent is actually sent
   rlwinm. %r3, %r3, 0,6,6
   beq     wait_for_character_sent
   blr
# End of function print_dot_uart

# TODO this looks like the patching engine
loc_511C:            
   mfmsr   %r7
   li      %r8, 0x10
   andc    %r8, %r7, %r8
   mtmsrd  %r8
   bl      print_dot_uart
   li      %r5, 0x200 
   oris    %r5, %r5, 0x8000
   sldi    %r5, %r5, 32
   oris    %r5, %r5, 0xC800 
   mr      %r5, %r5
   lwz     %r6, 0x70(%r5) # Load the patch slot size from 0x70 in NAND
   lwz     %r4, 0x64(%r5) # load the first patch slot address from 0x64 in NAND
   cmplwi  %r6, 0         # Test if the patch slot size is 0 (xeBuild bug? even if not, the images don't boot when this is 0)
   bne     patch_slot_size_nonzero
   lis     %r6, 1         # Default patch slot size (doesn't work for me but whatever this is how the existing patches work)

patch_slot_size_nonzero:            
   add     %r4, %r4, %r6
   addi    %r4, %r4, 0x5C # Skip past the virtual fuses (the first 0x60 bytes in the patch set)
   or      %r3, %r5, %r4
   isync

loc_5168:            
   mtmsrd  %r8
   isync
   lwzu    %r4, 4(%r3)
   cmpwi   %r4, -1
   beq     loc_51B0
   addi    %r4, %r4, -4
   lwzu    %r6, 4(%r3)
   mtctr   %r6

loc_5188:            
   mtmsrd  %r8
   isync
   lwzu    %r6, 4(%r3)
   mtmsrd  %r7
   isync
   stwu    %r6, 4(%r4)
   dcbst   %r0, %r4
   icbi    %r0, %r4
   bdnz    loc_5188
   b       loc_5168

loc_51B0:            
   sync
   isync
   mtmsrd  %r7
   rfid

# For armin's hacky 64mb XDKbuild image, xell in flashfs lives
# a whole 0x4000 later in NAND. This makes us need an additional
# instruction to set up the value in r5 we want to read from.
# Branching here so we don't accidentally mess up the offsets
# elsewhere in the patch set. TODO: can we put the oris/ori
# in the original spot or will it bump everything too far?
# In any case. XeLL lives at 0xF4000 in flash on a 64mb
# devkit image because reasons. Need to handle that separately.
.ifdef devgl64
set_bits_for_xell_in_flashfs:
   oris    %r5, %r5, 0xC80F
   ori     %r5, %r5, 0x4000
   blr
.endif

9:

.endif

#============================================================================
   .long 0xFFFFFFFF
   .end
#============================================================================
