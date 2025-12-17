.include "macros.S"

#============================================================================
#   Patches for Hypervisor 21256.18_17489
#============================================================================

#============================================================================
#  HV Patch Console Seq check
#============================================================================
MAKEPATCH 0x00007204
0:
   nop  
9: 
    
MAKEPATCH 0x00007214
0:
   nop  
9:

#============================================================================
#  HV patch jump
#============================================================================
MAKEPATCH 0x000071B8
0:
   li %r3, 0 
9:

MAKEPATCH 0x0000723C
0:
   nop
    li %r11, 0
9:

#============================================================================
#  HDD filesystem redirection
#============================================================================
.ifdef hdd
.include "sysroot_hdd.S"
.endif

#============================================================================
#  Patch XEX Restrictions check
#============================================================================
   MAKEPATCH 0xA2F48
0:
   li     %r3,  1
9:

   MAKEPATCH 0xA0FAC

0:
   b   0x18
9:

#============================================================================
# Enable Shadowboot patch out the signautre check
#============================================================================
   MAKEPATCH 0x301a8
0:
   nop
9: 

   MAKEPATCH 0x301ac
0:
   nop
9: 

   MAKEPATCH 0x301c0
0:
   nop
9: 

   MAKEPATCH 0x301d0
0:
   nop
9: 

   MAKEPATCH 0x301fc
0:
   nop
9: 

   MAKEPATCH 0x32198
0:
   li %r3, 1
9: 

# VFuse patches for 17489/21256.18


.ifdef vfuses
#============================================================================
#   Setup Fuse Row Pointer to point at Virtual Fuses
#   Change Increment and Range Check of Fuse Row Pointer
#============================================================================
    MAKEPATCH 0x00001BE0
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x00001BF4
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:
#------blow fuses ?CORONA? !!! ISNT CORRECT!!!-----------
    MAKEPATCH 0x00008038
0:
    bla     FixFusesAddr
9:
# ;--------------------------------------
    MAKEPATCH 0x00008058
0:
    addi    %r11, %r11, 0x0001
9:
# ;--------------------------------------
    MAKEPATCH 0x00008064
0:
    cmplwi  %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x00009438
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x00009468
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x000095D8
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x00009608
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x0000972C
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x0000975C
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x00009A58
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x00009A88
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x00009DE4
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x00009E14
0:
    addi    %r11, %r11, 0x0001
    rldicr  %r9, %r9, 3,60
    cmpwi   %cr6, %r11, 0x000c
9:
#--------------------------------------------------
    MAKEPATCH 0x0000A0D8
0:
    bla     FixFusesAddr
9:
#--------------------------------------
    MAKEPATCH 0x0000A104
0:
    addi    %r11, %r11, 0x0001
    rldicr  %r9, %r9, 3,60
    cmpwi   %cr6, %r11, 0x000c
9:

#============================================================================
#   Send Dot Character over Serial as Progress Indicator (ikari)
#============================================================================
   MAKEPATCH 0x000018c0
   .set PrintDotDest, 0x000002D8
0:
   bla      PrintDot  # patches
9:

#============================================================================
#   Utility Functions (c0z and ikari)
#============================================================================
   MAKEPATCH  0x0000B188

# Vfuses offset in NAND are different for each console type
# 16mb small block: 0xe0000
# 64mb small block: 0xe4000
# Jasper BB: 0x100000
# Trinity BB: 0xF0000
# Corona BB: 0xe0000

.ifdef consoletype_jasperbb
   .set nand_patch_offset, 0x0100000
.endif

.ifdef consoletype_trinitybb
   .set nand_patch_offset, 0x00F0000
.endif

.ifdef consoletype_coronabb
.set nand_patch_offset, 0x00e0000
.endif

.ifdef consoletype_sb
   .set nand_patch_offset, 0x00e0000
.endif

.ifdef consoletype_devgl64
   .set nand_patch_offset, 0x00e4000
.endif

   .set HvpGetFlashBaseAddress, 0x0000068C
   .set HvpFlashCopy, 0x00000484 # XeCryptCopyQwVec(void* dest, void* src, int iter)
   .set HvpMemCpy, 0x0000A4E0 #  memcpy(void *destination, const void *source, int len)
   .set PrintDot, PatchAddr
   .set FixFusesAddr, (PatchAddr + (1f - 0f))
   .set PrintChar, (PatchAddr + (2f - 0f))
   #.set HvFlagFixer, (PatchAddr + (3f - 0f))
#--------------------------------------------------
# PrintDot
#--------------------------------------------------
0:
   mflr  %r8
   bla      HvpGetFlashBaseAddress
   oris  %r4, %r3, nand_patch_offset@h
   ori      %r4, %r4, nand_patch_offset@l # source
   
   lis      %r3, 1
   subi  %r3, %r3, 0x60
   # 0x60 bytes, 0xC 64bit vals to copy
   li    %r5, 0xC
   bla      HvpFlashCopy
   
   # remove KV signature check
   lhz     %r3, 0x6(%r0)  # load flag byte into r3
   li      %r4, 0x21
   andc    %r3, %r3, %r4 # clear bit
   sth     %r3, 0x6(%r0)      # store new flag
   cmpldi   %r21,  0    # do what we patched

   li      %r3, '!'
   bla     PrintChar
   li      %r3, '\n'
   bla     PrintChar
   mtlr  %r8
   ba      PrintDotDest
#--------------------------------------------------
# FixFusesAddr
#--------------------------------------------------
1:
   lis      %r3, 1
   subi  %r3, %r3, 0x60
   blr
#--------------------------------------------------
# PrintChar
#--------------------------------------------------
2:
   lis     %r4, 0x8000
   ori     %r4, %r4, 0x0200
   rldicr  %r4, %r4, 32, 31
   oris    %r4, %r4, 0xea00
   slwi    %r3, %r3, 24
   stw     %r3, 0x1014(%r4)
charwait:
   lwz     %r3, 0x1018(%r4)
   rlwinm. %r3, %r3, 0, 6, 6
   beq     charwait
   blr
9:
.endif



#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
