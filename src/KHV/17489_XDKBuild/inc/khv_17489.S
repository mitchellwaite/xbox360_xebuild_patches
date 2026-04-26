.include "macros.S"

#============================================================================
#   Patches for Hypervisor 21256.18_17489
#============================================================================
.set HV_HvpGetFlashBaseAddress, 0x0000068C
.set HV_HvpFlashCopy, 0x00000484 # XeCryptCopyQwVec(void* dest, void* src, int iter)

.set HV_FlagFixer, 0xB188
.set FixFusesAddr, 0xB400

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
# Bypass SD check
#============================================================================
MAKEPATCH 0x000071B8
0:
   li %r3, 0 
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
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

#============================================================================
# Patch XeCryptBnQwBeSigVerify to return "true" instead of "false" when a
# signature check fails
#============================================================================
MAKEPATCH 0x000206DC
0:
  li %r3, 1
9:

#============================================================================
# Patch out signature checks in HvxExpansionInstall
#============================================================================
MAKEPATCH 0x00030C24
0:
  li %r3, 0
9:

MAKEPATCH 0x00030BEC
0:
  nop
9:

MAKEPATCH 0x00030C2C
0:
  nop
9:

# VFuse patches for 17489/21256.18
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
0:
   bla HV_FlagFixer
9:

# ============================================================================
#	HV Flag Fixer branched from 0x18C0
# ============================================================================
MAKEPATCH HV_FlagFixer
0:
   mflr %r8
   lhz %r3, 6(0)
   li %r4, 0x21
   andc %r3, %r3, %r4
   sth %r3, 6(0)

   # Load the virtual fuses from NAND
   bla HV_HvpGetFlashBaseAddress

.ifdef consoletype_jtag
   # JTAGs use virtual fuses too!
   # They're always at address 0x95000, don't need to
   # do any patch slot size/count calculations 
   oris %r4, %r3, 9
   ori %r4, %r4, 0x5000
   nop
   nop
.else
   # 0x64 (patch slot address) 0x70 (patch slot size)
   # let us calculate the location of the vfuses
   lwz %r4, 0x64(%r3)
   lwz %r5, 0x70(%r3)

   # XeBuild puts the virtual fuses at the beginning of
   # the second patch slot, comment this out if you use the 1st
   add %r3, %r3, %r4
   add %r4, %r3, %r5
.endif

   lis %r3, 1
   # 0x60 bytes, 0xC 64bit vals to copy
   subi %r3, %r3, 0x60
   li %r5, 0xc
   MAKEBRANCHL HV_HvpFlashCopy

   li %r3, '!'
   bl PrintChar
   li %r3, '\n'
   bl PrintChar

   # Restore the link register
   mtlr %r8

   # Branch to where we were supposed to go
   ba 0x2D8

PrintChar:
   lis %r4, -0x8000
   ori %r4, %r4, 0x200
   sldi %r4, %r4, 0x20
   oris %r4, %r4, 0xea00
   slwi %r3, %r3, 0x18
   stw %r3, 0x1014(%r4)
   sync
   isync

charwait:
   lwz %r3, 0x1018(%r4)
   rlwinm. %r3, %r3, 0, 6, 6
   beq charwait
   blr
9:

# ============================================================================
# FixFusesAddr
# ============================================================================
MAKEPATCH FixFusesAddr
0:
   lis %r3, 1
   addi %r3, %r3, -0x60
   blr
9:

.ifdef consoletype_jtag
# In 17489, we've got some room right after HvxStartupProcessors
.set HV_StartProcPatchAddr, 0xCE8

# ============================================================================
# For JTAGs only, we need to patch HvxStartupProcessors
#
# The following patch replaces (addis r4, r3, -3) with a branch to our custom
# function, the custom function will then branch back to the instruction
# after what we replaced
# ============================================================================
MAKEPATCH HV_StartProcPatchAddr
0:
   lis %r4, -0x8000
   sldi %r4, %r4, 0x20
   oris %r4, %r4, 0x100
   ori %r4, %r4, 0x3080
   ba 0xC64
9:

MAKEPATCH 0xC60
0:
   ba HV_StartProcPatchAddr
9:
.endif

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
