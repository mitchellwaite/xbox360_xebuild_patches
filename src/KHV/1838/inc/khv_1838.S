# Fuck if I know if this is accurate :)

.include "macros.S"

# Start of the syscall table. This is where the address of the real HvxGetVersions (Syscall0) function is found
.set Syscall_Table, 0x1440

# Real HV Functions
.set HV_HvxGetVersions, 0x29A0
.set HV_memcpy, 0xEFF0
.set HV_XeCryptAesKey, 0xB938
.set HV_HvpGetFlashBaseAddress, 0x2870
.set HV_HvpFlashCopy, 0x28F0
.set HV_HvxPostOutput, 0x26C4

# Functions within the patches, some of these change depending on what
# features are enabled.
.set HV_FlagFixer, 0xFA00
.set FixFusesAddr, 0xFAD4

#============================================================================
#   Patches for Hypervisor 1838.0
#============================================================================

#============================================================================
#  HDD filesystem redirection
#============================================================================
.ifdef hdd
.include "sysroot_hdd.S"
.endif

#============================================================================
# Enable Shadowboot patch out the signature check
#============================================================================
MAKEPATCH 0x273C
0:
   nop
9: 

MAKEPATCH 0x2740
0:
   nop
9: 

MAKEPATCH 0x2754
0:
   nop
9: 

MAKEPATCH 0x2764
0:
   nop
9: 

MAKEPATCH 0x27A4
0:
   nop
9: 

MAKEPATCH 0x2C50
0:
   li %r3, 1
9: 

#============================================================================
# Patch XeCryptBnQwBeSigVerify to return "true" instead of "false" when a
# signature check fails
#============================================================================
MAKEPATCH 0xB76C
0:
  li %r3, 1
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 80 00 00 00 01 60 00 00 00
MAKEPATCH 0x000049E0
0:
   nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 8C 00 00 00 01 60 00 00 00
MAKEPATCH 0x000049EC
0:
   nop
9:

# VFuse patches for 17489/21256.18
#============================================================================
#   Setup Fuse Row Pointer to point at Virtual Fuses
#   Change Increment and Range Check of Fuse Row Pointer
#============================================================================
MAKEPATCH 0x29DC
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x29F0
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:

MAKEPATCH 0x00005B00
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005B30
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00005C70
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005CA0
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00005D14
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005D44
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00006008
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00006038
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x0000614C
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00006178
0:
   addi %r11, %r11, 1
   sldi %r9, %r9, 3
   cmplwi cr6, %r11, 0xc
9:

# ============================================================================
#	Branch to HV flag fixer function
# ============================================================================
MAKEPATCH 0x00001CF0
0:
   bla HV_FlagFixer
9:

# ============================================================================
#	HV Flag Fixer branched from 0x1CF0
# ============================================================================
MAKEPATCH HV_FlagFixer
0:
   mflr %r8
   lhz %r3, 6(0)
   li %r4, 0x21
   andc %r3, %r3, %r4
   sth %r3, 6(0)

   # Load the virtual fuses from NAND
   # 0x64 (patch slot address) 0x70 (patch slot size)
   # let us calculate the location of the vfuses
   bla HV_HvpGetFlashBaseAddress
   lwz %r4, 0x64(%r3)
   lwz %r5, 0x70(%r3)

   # XeBuild puts the virtual fuses at the beginning of
   # the second patch slot, comment this out if you use the 1st
   add %r3, %r3, %r4
   add %r4, %r3, %r5

   lis %r3, 1
   # 0x60 bytes, 0xC 64bit vals to copy
   subi %r3, %r3, 0x60
   li %r5, 0xc
   MAKEBRANCHL HV_HvpFlashCopy

   li %r3, '!'
   bl PrintChar
   li %r3, '\n'
   bl PrintChar

   # Do what we patched
   li %r3, 0x200

   # Restore the link register
   mtlr %r8

   # Branch back to where we came from
   bla 0x1CF4

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

# ============================================================================
#	HvxKeysRsaPrvCrypt - Allow access to all XeKeys properties
# ============================================================================
# 00 00 81 3C 00 00 00 01 48 00 00 30
MAKEPATCH 0x000076B4
0:
   MAKEBRANCH 0x76D8
9:

# ============================================================================
# 	HvxCreateImageMapping HV XEX region check 
# ============================================================================
# 00 02 CD D8 00 00 00 01 60 00 00 00
MAKEPATCH 0x00003B30
0:
   b 0x10
9:

#
# Kernel Patches
#

#=============================================================================
# Patch within XexpLoadXexHeaders to skip media type check
#=============================================================================
KMAKEPATCH 0x800766A0
0:
   b 0x10
9:

#=============================================================================
# Patches branch to RtlImageXexHeaderString within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x80076918
0:
   li %r3, 0
9:

#=============================================================================
# Patch within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x80076980
0:
   li %r11, 0
9:

#=============================================================================
# Patches XexpVerifyMinimumVersion
#=============================================================================
KMAKEPATCH 0x80077928
0:
   li %r3, 0
   blr
9:

#=============================================================================
# Patches XeKeysVerifyRSASignature to always return "verified"
#=============================================================================
KMAKEPATCH 0x800BD138
0:
   li %r3, 1
   blr
9:

#=============================================================================
# Patches XeKeysConsoleSignatureVerification
#=============================================================================
#KMAKEPATCH 0x800BD018
#0:
#   cmplwi cr6, %r5, 0
#   li %r3, 1
#   beq cr6, 0x8 # Original patch decompiled as 0x10bf30
#   stw %r3, 0(%r5)
#   blr
#9:

#=============================================================================
# Patches XeCryptBnQwBeSigVerify
#=============================================================================
KMAKEPATCH 0x800C1AE0
0:
   li %r3, 1
   blr
9:

.ifdef patch_gpu
#============================================================================
# Patch VdpOneTimeDeviceInitialize to spoof the GPU ID to avoid E78
#============================================================================

# NOP out a check on the ASIC ID
KMAKEPATCH 0x800FDF14
0:
   nop
9:

KMAKEPATCH 0x800FDF40
0:
    li %r11, 0x11 #Prod GPU
9:

#============================================================================
# Patch VdInitializeEdram to set edram timing, otherwise graphics will look screwy
#============================================================================
KMAKEPATCH 0x800AE9A4
0:
.ifdef patch_gpu_zeus
   li %r10, 0x15 # Zeus/Kronos timing
.endif

.ifdef patch_gpu_rhea
   li %r10, 0x1E # Rhea timing
.endif
9:

KMAKEPATCH 0x800AE9EC
0:
   li %r4, 0x31
9:

KMAKEPATCH 0x800AEA3C
0:
   li %r4, 0x31
9:

.endif


#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
