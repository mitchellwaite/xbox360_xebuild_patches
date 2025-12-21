# Fuck if I know if this is accurate :)

.include "macros.S"

# Start of the syscall table. This is where the address of the real HvxGetVersions (Syscall0) function is found
.set Syscall_Table, 0x13D8

# Real HV Functions
.set HV_HvxGetVersions,0x20c0
.set HV_memcpy, 0xE5F0
.set HV_XeCryptAesKey, 0xA3B8
.set HV_HvpGetFlashBaseAddress, 0xb2c
.set HV_HvpFlashCopy, 0x788

# Functions within the patches, some of these change depending on what
# features are enabled.

.set HV_FlagFixer, 0xFA00
.set FixFusesAddr, 0xFAD4
.set HV_setmemprot, 0x1580
.set HV_PP_Syscall0, 0xFB00
.set HV_DevkitXexKeyCheck, 0x1620

# ============================================================================
#	Branch to HV flag fixer function
# ============================================================================
MAKEPATCH 0x00001C24
0:
   bla HV_FlagFixer
9:


# ============================================================================
# HvFixKeys patch
# ============================================================================
# pbkey xex2key make transform key 81300D49C232F145
MAKEPATCH 0x00000018
0:
   .long 0x81300D49
   .long 0xC232F145
9:

# Disable copying transform key from SoC
MAKEPATCH 0x00002348
0:
   nop
9:

# ============================================================================
# Vfuse patches for the HV
# ============================================================================
MAKEPATCH 0x00002108
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x0000211C
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00005550
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005580
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000056C0
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x000056F0
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000057D8
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005808
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00005A40
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005A70
0:
   addi %r11, %r11, 1
   cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00005B64
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00005B90
0:
   addi %r11, %r11, 1
   sldi %r9, %r9, 3
   cmplwi cr6, %r11, 0xc
9:
# ============================================================================
# End vfuse patches
# ============================================================================

# ============================================================================
#	Devkit XEX2 AES key
# ============================================================================
# 00 00 00 F0 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
MAKEPATCH 0xF0
0:
   .long 0
   .long 0
   .long 0
   .long 0
9:

# ============================================================================	
# Disable memory protection
#	ExceptionVectorDSI
# ============================================================================
# 00 00 11 BC 00 00 00 01 48 00 15 4E
MAKEPATCH 0x1134
0:
   ba HV_setmemprot
9:

# ============================================================================
#	The li %r4, 7 in this is modified by the syscall0 backdoor 
#	to toggle the memory protection state.
#	ENABLED = 0x38800000 (li r4, 0) || DISABLED = 0x38800007 (li r4, 7)
# ============================================================================
# 00 00 15 4C 00 00 00 04 38 80 00 07 7C 21 20 78 7C 35 EB A6 48 00 11 C2
MAKEPATCH HV_setmemprot
0:
   li %r4, 7             # DISABLED by default
   andc %r1, %r1, %r4
   mtspr 0x3b5, %r1      # do what we patched
   ba 0x1138             # branch to the next instruction 
9:

# ============================================================================
# 	Disable fuse blowing ???
#  Looks like this is actually HvxLockL2...
# ============================================================================
# 00 00 A5 60 00 00 00 02 38 60 00 01 4E 80 00 20
MAKEPATCH 0x00005CE8
0:
   li %r3, 1
   blr
9:

# ============================================================================
#	HvxLoadImageData - nop's out a sig check?
# ============================================================================
# 00 02 A3 0C 00 00 00 02 60 00 00 00 60 00 00 00
MAKEPATCH 0x00003CBC
0:
   nop
   nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 80 00 00 00 01 60 00 00 00
MAKEPATCH 0x00004368
0:
   nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 8C 00 00 00 01 60 00 00 00
MAKEPATCH 0x00004374
0:
   nop
9:

# ============================================================================
#	HV Flag Fixer branched from 0x1C24
# ============================================================================
MAKEPATCH HV_FlagFixer
0:
   mflr %r8
   lhz %r3, 6(0)
   li %r4, 0x21
   andc %r3, %r3, %r4
   ori %r3, %r3, 0x1e
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
   bla HV_HvpFlashCopy

   li %r3, '!'
   bl PrintChar
   li %r3, '\n'
   bl PrintChar

   # Do what we patched
   li %r3, 0x200

   # Restore the link register
   mtlr %r8

   # Branch back to where we came from
   ba 0x1C28

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
# FreeBoot syscall 0 backdoor
# ============================================================================
MAKEPATCH HV_PP_Syscall0
0:
   lis %r11, 0x7262                  # Freeboot syscall key - 0x72627472 "rbtr" 1st half
   ori %r11, %r11, 0x7472            # 2nd half

   cmplw cr6, %r3, %r11             # Check for the magic key 0x72627472
   beq cr6, checkOpType             # Branch to checkOpType if matches - 0xb578
   ba HV_HvxGetVersions             # If not, branch back to the real HvxGetVersions

checkOpType:
   cmplwi cr6, %r4, 4                # Check for 4 aka hvxExecute
   bgt cr6, doMemCpy                # If it's greter than 4 it must be MemCpy         
   beq cr6, hvxExecuteCode          # If it matches then it's hvxExecute
   li %r5, HV_setmemprot             # Memory protections function address added in an earlier patch
   lis %r6, 0x3880                   # Sets r6 to 0x38800000 - Remains like this if protections are to be ENABLED
   cmplwi cr6, %r4, 2                # Check for 2 aka set mem protections DISABLED     
   bne cr6, checkForMemProtectOn    # If not, branch to check for mem protections ENABLED - 0xb59c
   ori %r6, %r6, 7                    # Updates r6 to 0x38800007 - Indicating protections are to be DISABLED
   b setMemProtections              # Branch to set memory protections setup 

checkForMemProtectOn:   
   cmplwi cr6, %r4, 3                # Check for 3 aka set mem protections ENABLED
   bne cr6, returnOne               # If not, branch to returnOne to exit - 0xb5bc

setMemProtections:
   li %r0, 0
   stw %r6, 0(%r5)                    # Sets the start of the set mem function based on what was set in r6 earlier - ENABLED = 0x38800000 (li r4, 0) || DISABLED = 0x38800007 (li r4, 7)
   dcbst 0, %r5
   icbi 0, %r5
   sync 0
   isync

returnOne:
   li %r3, 1
   blr

hvxExecuteCode:
   mflr %r12
   std %r12, -8(%r1)
   stdu %r1, -0x10(%r1)
   mtlr %r5
   mtctr %r7

cpyLoop:
   lwz %r4, 0(%r6)
   stw %r4, 0(%r5)
   dcbst 0, %r5
   icbi 0, %r5
   sync 0
   isync
   addi %r5, %r5, 4
   addi %r6, %r6, 4
   bdnz cpyLoop
   blr
   addi %r1, %r1, 0x10
   ld %r12, -8(%r1)
   mtlr %r12
   blr

doMemCpy:
   cmplwi cr6, %r4, 5
   bne cr6, returnTwo   # Branch to returnTwo
   mr %r3, %r6
   mr %r4, %r5
   mr %r5, %r7
   ba HV_memcpy         # Branch to the HV MemCpy function

returnTwo:
   li %r3, 2
   blr
9:

# ============================================================================
# Set the address of the syscall 0 backdoor in the syscall table
# ============================================================================
MAKEPATCH Syscall_Table
0:
   .long HV_PP_Syscall0
9:

# ============================================================================
#	HvxKeysRsaPrvCrypt - Allow access to all XeKeys properties
# ============================================================================
# 00 00 81 3C 00 00 00 01 48 00 00 30
MAKEPATCH 0x0000707C
0:
   b 0x30
9:

# ============================================================================
#	HvpCompareXGD2MediaID - Always return true
# ============================================================================
# 00 02 4D 58 00 00 00 02 38 60 00 01 4E 80 00 20
MAKEPATCH 0x00008AF8
0:
   li %r3, 1
   blr
9:

# ============================================================================
# Bypasses C0000221 STATUS_IMAGE_CHECSUM_MISMATCH in HvxCreateImageMapping
#
# All this patch does is allow for devkit signed xex files
# as a fallback if the call to XeCryptBnQwBeSigVerify fails (rc = 0).
#
# To allow for unsigned retail xex support on retail kernels, launch.xex hooks
# XexpLoadImage and XexpVerifyImageHeaders and pokes the instruction in the
# HV to change the fallback decryption key
#
# (this is exactly what DashLaunch does on regular kernels)
#
# If the patches are changed, 
#
# ============================================================================

# ============================================================================
# Rather than saving registers r21-r31 on the stack, we'll save r20 as well
# and will use r20 to persist the result of the XeCryptBnQwBeSigVerify call
# ============================================================================
MAKEPATCH 0x30AC
0:
   MAKEBRANCHL 0xE518
9:

# ============================================================================
# We've got to restore r20 - r31 as well
# ============================================================================
MAKEPATCH 0x3648
0:
   MAKEBRANCHL 0xE568
9:

# ============================================================================
# Save the return value of XeCryptBnQwBeSigVerify and then skip the branch
# to the code that sets STATUS_IMAGE_CHECKSUM_MISMATCH - C0000221
# ============================================================================
MAKEPATCH 0x000031C8
0:
   mr %r20, %r3
   b 0x10
9:

# ============================================================================
# Replace the "li r4, 0x54" at 0x35A0 with a branch to a function
# that will check the value in r20 set the devkit XEX key as needed
# ============================================================================
MAKEPATCH 0x000035A0
0:
   MAKEBRANCH HV_DevkitXexKeyCheck
9:

MAKEPATCH HV_DevkitXexKeyCheck
0:
   li %r4, 0x54
   cmpwi cr6, %r20, 0   # Check if the result from XeCryptBnQwBeSigVerify was 0
   bne cr6, done
   li %r4, 0xF0         # If it was zero, set the address of the devkit xex key
                        # This instruction is the DWORD at 0x162C, if the code
                        # is modified, launch.xex must be updated!
done:
   MAKEBRANCH 0x35A4   # the next instruction that would have run
9:

# ============================================================================
# 	HvxCreateImageMapping HV XEX region check 
# ============================================================================
# 00 02 CD D8 00 00 00 01 60 00 00 00
MAKEPATCH 0x00003308
0:
   b 0x10
9:

# 
# Kernel Patches
#

#=============================================================================
# Patch within XexpLoadXexHeaders to skip media type check
#=============================================================================
KMAKEPATCH 0x800638D0
0:
   b 0x10
9:

#=============================================================================
# Patches branch to RtlImageXexHeaderString within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x80063B28
0:
   li %r3, 0
9:

#=============================================================================
# Patch within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x80063B90
0:
   li %r11, 0
9:

#=============================================================================
# Patches XexpVerifyMinimumVersion
#=============================================================================
KMAKEPATCH 0x80064A90
0:
   li %r3, 0
   blr
9:

#=============================================================================
# Patches XeKeysVerifyRSASignature to always return "verified"
#=============================================================================
KMAKEPATCH 0x800BC210
0:
   li %r3, 1
   blr
9:

#=============================================================================
# Patches XeKeysConsoleSignatureVerification
#=============================================================================
KMAKEPATCH 0x800BC0D8
0:
   cmplwi cr6, %r5, 0
   li %r3, 1
   beq cr6, 0x8 # Original patch decompiled as 0x10bf30
   stw %r3, 0(%r5)
   blr
9:

#=============================================================================
# Patches XeCryptBnQwBeSigVerify
#=============================================================================
KMAKEPATCH 0x800C0690
0:
   li %r3, 1
   blr
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice (Disables hdd security sector verification)
#============================================================================
#KMAKEPATCH 0x800DD7C0
#0:
#   li %r3, 1
#   blr
#9:

#
# TODO we've got some *stuff* that needs to be done if we want DashLaunch and all that jazz to work
# For now forget about it, that can come in V2 of the patch
#

#============================================================================
# During Phase1 initialization, after we've loaded xam.xex, branch to free
# space so we can load launch.xex. This is a bit simpler of a function
# compared to what 17559 does... this is closer to what RGLoader does.
#
# We've patched out XeKeysConsoleSignatureVerification, so address 0x800BC0EC
# to address 0x800BC208 is effectively free for our use.
#============================================================================
.set Phase1PatchAddress, 0x80050C34
.set XeKeysFreeSpace, 0x800BC0EC
.set XexLoadImage, 0x80065A18

# Phase1PatchAddress
KMAKEPATCH 0x80050C34
0:
   # Jump to the code after the string for the launch.xex path
   KMAKEBRANCH (XeKeysFreeSpace + 0x1C)
9:

KMAKEPATCH XeKeysFreeSpace
0:
   #
   # \\Device\\Flash\\launch.xex
   #
   .long 0x5C446576    
   .long 0x6963655C    
   .long 0x466C6173    
   .long 0x685C6C61    
   .long 0x756E6368    
   .long 0x2E786578
   .long 0

   # Load launch.xex
   lis %r11, XeKeysFreeSpace@h
   ori %r3, %r11, XeKeysFreeSpace@l
	lis %r5, 0               # Set r5 (MinimumVersion)
	li %r4, 0               # Set r4 (ModuleTypeFlags) - 1st half
	ori %r4, %r4, 8         # Set r4 (ModuleTypeFlags) - 2nd half
	li %r6, 0                # Set r6 (pHandle)
   KMAKEBRANCHL XexLoadImage

   # Optional: If we fail to load launch.xex,
   # branch back to the bit of code that throws an E79
   # (Failure to load xam.xex)
   cmpwi %r3, 0
   bge 0x8
   KMAKEBRANCH (Phase1PatchAddress - 0xC)

   # Do the instruction that the Phase1Initialization patch replaced
   # then branch back to the last instruction of Phase1Initialization
   li %r3, 0
   KMAKEBRANCH (Phase1PatchAddress + 0x4)
9:

.ifdef patch_gpu
#============================================================================
# Patch VdpOneTimeDeviceInitialize to spoof the GPU ID to avoid E78
#============================================================================
KMAKEPATCH 0x800DE5FC
0:
    li %r11, 0x11 #Prod GPU
9:

# Another option to skip the GPU version check is to patch the bge before the call to VdDisplayFatalError
# KMAKEPATCH 0x800DE6A8
# 0:
#     b +0x10
# 9:

#============================================================================
# Patch VdInitializeEdram to set edram timing, otherwise graphics will look screwy
#============================================================================
KMAKEPATCH 0x80098688
0:
.ifdef patch_gpu_zeus
   li %r10, 0x15 # Zeus/Kronos timing
.endif

.ifdef patch_gpu_rhea
   li %r10, 0x1E # Rhea timing
.endif
9:

KMAKEPATCH 0x800986D0
0:
   li %r4, 0x31
9:

KMAKEPATCH 0x80098718
0:
   li %r4, 0x31
9:

.endif

# done with patch section


#============================================================================
.long 0xFFFFFFFF
.end
#============================================================================


