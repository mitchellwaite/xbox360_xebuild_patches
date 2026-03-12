#
# 6717 khv patches credit to Holofractal/dotprofile
#

.include "macros.S"

# Start of the syscall table. This is where the address of the real HvxGetVersions (syscall 0) is found
.set Syscall_Table, 0x1CD4

# Real HV Functions
.set HvpGetFlashBase,0x998
.set CopyBy64,0x78C
.set resumeInit,0x19A4
.set HvxGetVersions,0x2A48
.set HV_memcpy,0xC740

# Functions within the patches
.set FixFusesAddr    0xD020
.set HV_PP_Syscall0  0xD030
.set HV_setmemprot   0x1570

# ============================================================================
#	Branch to HV flag fix function
# ============================================================================
MAKEPATCH 0x000019A0
0:
   bla 0xcf80
9:

# ============================================================================
# Vfuse patches for the HV
# ============================================================================
MAKEPATCH 0x00002A90
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00002AA4
0:
   addi r11, r11, 1
   cmplwi cr6, r11, 0xc
9:

MAKEPATCH 0x00007198
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x000071C8
0:
   addi r11, r11, 1
   cmplwi cr6, r11, 0xc
9:


MAKEPATCH 0x00007308
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00007338
0:
   addi r11, r11, 1
   cmplwi cr6, r11, 0xc
9:

MAKEPATCH 0x00007428
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00007458
0:
   addi r11, r11, 1
   cmplwi cr6, r11, 0xc
9:

MAKEPATCH 0x00007698
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x000076C8
0:
   addi r11, r11, 1
   cmplwi cr6, r11, 0xc
9:


MAKEPATCH 0x000077EC
0:
   bla FixFusesAddr
9:

MAKEPATCH 0x00007818
0:
   addi r11, r11, 1
   sldi r9, r9, 3
   cmpwi cr6, r11, 0xc
9:
# ============================================================================
# End vfuse patches
# ============================================================================

# ============================================================================
#	Devkit XEX2 AES key
# ============================================================================
MAKEPATCH 0x000000F0 # devkit xex key
0:
   .long 0x00000000
   .long 0x00000000
   .long 0x00000000
   .long 0x00000000
9:

MAKEPATCH 0x00001420
0:
   cmplwi r0, 0x7c
9:

# ============================================================================
# Disable memory protection
#	ExceptionVectorDSI
# ============================================================================
MAKEPATCH 0x0000114C
0:
   ba HV_setmemprot
9:

# ============================================================================
#	The li %r4, 7 in this is modified by the syscall0 backdoor
#	to toggle the memory protection state.
#	ENABLED = 0x38800000 (li r4, 0) || DISABLED = 0x38800007 (li r4, 7)
# ============================================================================
MAKEPATCH HV_setmemprot
0:
   li r4, 7				# DISABLED by default
   andc r1, r1, r4
   mtspr 0x3b5, r1
   ba 0x1150
9:

# ============================================================================
# HvxLockL2... Disables fuse blowing ???
# ============================================================================
MAKEPATCH 0x000079F0
0:
   li r3, 1
   blr
9:

# ============================================================================
#	HvxLoadImageData - nop's out a sig check
# ============================================================================
MAKEPATCH 0x00004C5C
0:
   nop
   nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
MAKEPATCH 0x00005340
0:
   nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
MAKEPATCH 0x0000534C
0:
   nop
9:

# ============================================================================
#	HV Flag Fixer branched from 0x19A0
# ============================================================================
MAKEPATCH 0x0000CF80
0:
   # Clear HV flags
   mflr r8
   lhz r3, 6(r0)
   li r4, 0x21
   andc r3, r3, r4
   sth r3, 6(r0)

   # Load VFuses
   bla HvpGetFlashBase # 0x998
   lwz r4, 0x64(r3)	# 0x64 in NAND is the patch slot address
   lwz r5, 0x70(r3)  # 0x70 in NAND is the patch slot size
   add r3, r3, r4
   add r4, r3, r5

   lis r3, 1

   # 0x60 bytes, 0xC 64bit vals to copy
   addi r3, r3, -0x60
   li r5, 0xc
   bla CopyBy64 	# HvpFlashCopy, a few other names for this func lol

   # Print the staus indicator
   li r3, '!'
   bl PrintChar
   li r3, '\n'
   bl PrintChar
   mtlr r8

   # Branch back to where we came from 
   ba resumeInit 	# 0x19A4

PrintChar:
   lis r4, -0x8000
   ori r4, r4, 0x200
   sldi r4, r4, 0x20
   oris r4, r4, 0xea00
   slwi r3, r3, 0x18
   stw r3, 0x1014(r4)

charwait:
   lwz r3, 0x1018(r4)
   rlwinm. r3, r3, 0, 6, 6
   beq charwait
   blr
9:

# ============================================================================
# FixFusesAddr: Fuse Fixing Function
# ============================================================================
MAKEPATCH FixFusesAddr
0:
   lis r3, 1
   addi r3, r3, -0x60
   blr
9:

# ---------------------------------------------------
# HV_PP_Syscall0 (syscall 0 backdoor)
# ---------------------------------------------------
MAKEPATCH HV_PP_Syscall0
0:
   lis r11, 0x7262         # Freeboot syscall key - 0x72627472 "rbtr" 1st half
   ori r11, r11, 0x7472    # 2nd half
   cmplw cr6, r3, r11      # Check for the magic key
   beq cr6, checkOpType		# Branch to checkOpType at 0xD018 if it matches
   ba HvxGetVersions 		# Otherwise branch to the real HvxGetVersions (0x2A48)

checkOpType: # 0xD018
   cmplwi cr6, r4, 4             # Check for 4, aka hvxExecute
   bgt cr6, doMemCpy 	         # >4 must be MemCpy (0xD0B0)
   beq cr6, hvxExecuteCode 	   # If it matches, must be hvxExecute
   li r5, Hv_setmemprot 	      # Memory protection function address
   lis r6, 0x3880                # Sets r6 to 0x38800000 - Remains like this if protections are to be ENABLED
   cmplwi cr6, r4, 2             # Check for 2 aka set mem protections DISABLED
   bne cr6, checkforMemProtectOn # If not, branch to check for mem protections ENABLED - 0xd03c
   ori r6, r6, 7                 # Updates r6 to 0x38800007 - Indicating protections are to be DISABLED
   b setMemProtections           # Branch to set memory protections setup 0xd044

checkforMemProtectOn:
   cmplwi cr6, r4, 3             # Check for 3 aka set mem protections ENABLED
   bne cr6, returnOne 		      # If not, branch to returnOne to exit 0xD05C

setMemProtections:
   li r0, 0
   stw r6, 0(r5)                 # Sets the start of the set mem function based on what was set in r6 earlier - ENABLED = 0x38800000 (li r4, 0) || DISABLED = 0x38800007 (li r4, 7)
   dcbst 0, r5
   icbi 0, r5
   sync
   isync

returnOne:
   li r3, 1
   blr

hvxExecuteCode:
   mflr r12
   std r12, -8(r1)
   stdu r1, -0x10(r1)
   mtlr r5
   mtctr r7

cpyLoop:
   lwz r4, 0(r6)
   stw r4, 0(r5)
   dcbst 0, r5
   icbi 0, r5
   sync
   isync
   addi r5, r5, 4
   addi r6, r6, 4
   bdnz cpyLoop			# 0xD078
   blr
   addi r1, r1, 0x10
   ld r12, -8(r1)
   mtlr r12
   blr

doMemCpy:
   cmplwi cr6, r4, 5
   bne cr6, returnTwo 	#0xD0C8
   mr r3, r6
   mr r4, r5
   mr r5, r7
   ba HV_memcpy 	# 0xC740

returnTwo:
   li r3, 2
   blr
9:

# ============================================================================
# Patch syscall table with address of our fake Syscall0 backdoor
# ============================================================================
MAKEPATCH Syscall_Table 
0:
   .long HV_PP_Syscall0
9:

# ============================================================================
#       HvxSecurity Functions  (sets machine acct flags)
# ============================================================================
MAKEPATCH 0x000090B0 # HvxSecuritySetDetected
0:
   li r3, 0
   blr
9:

MAKEPATCH 0x00009178 # HvxSecurityGetDetected
0:
   li r3, 0
   blr
9:

MAKEPATCH 0x000091C0 # HvxSecuritySetActivated
0:
   li r3, 0
   blr
9:

MAKEPATCH 0x00009268 # HvxSecurityGetActivated
0:
   li r3, 0
   blr
9:

# ============================================================================
#	HvxKeysRsaPrvCrypt - Allow access to all XeKeys properties
# ============================================================================
MAKEPATCH 0x00009FF0 
0:
   b 0x30 #0xA020
9:

# ============================================================================
# Bypass CB sig check - Replaces call to XeCryptBnQwBeSigVerify
# There is no CD check in 6717
# ============================================================================
MAKEPATCH 0x00009534
0:
   li r3, 1
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
MAKEPATCH 0x00009540
0:
   nop
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
MAKEPATCH 0x0000957C
0:
   nop
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
MAKEPATCH 0x0000958C
0:
   nop
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
MAKEPATCH 0x000095B4
0:
   nop
   li r11, 1
9:

# ============================================================================
#	HvpCompareXGD2MediaID - Always return true
# ============================================================================
MAKEPATCH 0x0000A1D8
0:
   li r3, 1
   blr
9:

.set j_XeCryptAesKey,0xCDE8

# ============================================================================
# 	xex aes key for dev signed support
# 	Fixes bad signature
#	Overwrites the status STATUS_IMAGE_CHECKSUM_MISMATCH - C0000221
#
# All this patch does is allow for devkit signed xex files
# as a fallback if the call to XeCryptBnQwBeSigVerify fails (rc = 0).
#
# To allow for unsigned retail xex support on retail kernels, DashLaunch hooks
# XexpLoadImage and XexpVerifyXexHeaders and pokes the instruction in the
# HV to change the fallback decryption key
#
# (Look in the DashLaunch changelog- these hooks were added in V3.0)
# ============================================================================
MAKEPATCH 0x00003DC8
0:
   # This section overwrites a check on the return value of XeCryptBnQwBeSigVerify disabling STATUS_IMAGE_CHECKSUM_MISMATCH - C0000221
   cmpldi cr6, r28, 0   # Value set from r4 being passed to main function being patched
   beq cr6, loc_3dfc    # Branch if zero. This is how it's handled by the function normally when XeCryptBnQwBeSigVerify returns non-zero

   cmpwi cr6, r3, 0     # Check the return value of XeCryptBnQwBeSigVerify performed just before these patches
   bne cr6, loc_3de4    # Branch when non-zero

   li r4, 0xf0          # Address of Devkit XEX2 AES key that has been set to all zero.
   b loc_3df4
   nop

   # Everything below remains unchanged??? Maybe it's just here to make it easier to create branches when compiling???
loc_3de4:
   cmplwi cr6, r29, 0
   addi r4, r31, 0x440
   bne cr6, loc_3df4
   li r4, 0x54          # Address of Retail XEX2 AES key - 20 B1 85 A5 9D 28 FD C3 40 58 3F BB 08 96 BF 91

loc_3df4:
   mr r3, r28
   MAKEBRANCHL j_XeCryptAesKey

loc_3dfc:
   li r31, 0
9:

# ============================================================================
# 	HvxImageTransformImageKey - Disables a conditional branch
# ============================================================================
MAKEPATCH 0x00005E90
0:
   nop
9:

# ============================================================================
# 	HvxCreateImageMapping hash check
# ============================================================================
MAKEPATCH 0x000040A8
0:
   li r3, 0
9:

# ============================================================================
# 	HvxCreateImageMapping HV XEX region check 
# ============================================================================
MAKEPATCH 0x000042F0
0:
   nop
9:

#
# kernel patches :)
#

#=============================================================================
# Patches XexpLoadXexHeaders to ignore xex media type check
#=============================================================================
KMAKEPATCH 0x8007718C
0:
   b 0x10 
9:

KMAKEPATCH 0x80077190
0:
   nop
   nop
   nop
9:

#=============================================================================
# Patches branch to RtlImageXexHeaderString within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x80077298
0:
   li r3, 0
9:

#=============================================================================
# Patch within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x800772EC
0:
   li r11, 0
9:

#=============================================================================
# Patch within SfcxInspectLargeDataBlock
#=============================================================================
KMAKEPATCH 0x8008CD80
0:
   li r23, 0x10
9:

#=============================================================================
# Patches to disable fatal error screen E66 (VdDisplayFatalError)
# Caused by DVD drive (ERROR_XSS_CDROM_COULD_NOT_CREATE_DEVICE)
#=============================================================================
KMAKEPATCH 0x8008FF10
0:
   li r3, 0
   nop
   nop
9:

#=============================================================================
# Patches XeKeysVerifyRSASignature
#=============================================================================
KMAKEPATCH 0x800EB230
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches _XeKeysRevokeIsValid
#=============================================================================
KMAKEPATCH 0x800EC158
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches _XeKeysRevokeIsRevoked
#=============================================================================
KMAKEPATCH 0x800EC1F8
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches XeKeysRevokeIsRevoked
#=============================================================================
KMAKEPATCH 0x800EC2C8 # XeKeysRevokeIsRevoked
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches XeKeysRevokeConvertError
#=============================================================================
KMAKEPATCH 0x800EC340 # XeKeysRevokeConvertError
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches XeKeysConsoleSignatureVerification
#=============================================================================
KMAKEPATCH 0x800ECBA0
0:
   cmplwi cr6, r5, 0
   li r3, 1
   beq cr6, 0x8
   stw r3, 0(r5)
   blr
9:

KMAKEPATCH 0x800ECBF0
0:
   li r3, 1
   KMAKEBRANCH(0x800ecc18)
9:

#=============================================================================
# Patches XeCryptBnQwBeSigVerify
#=============================================================================
KMAKEPATCH 0x800F1300
0:
   li r3, 1
   blr
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice
#
# Regular FreeBoot would have done the following at 0x80117E88
#     li r3, 1
#     blr
#
# However, that breaks compat with FATXPlorer formatted drives with a SS and
# "extra space"... this patch does full auth for retail for such drives but
# still allows generic drives by patching the error path to return TRUE
#============================================================================

#============================================================================
# Patch error handler in SataDiskAuthenticateDevice to return TRUE instead
# of FALSE
#============================================================================
KMAKEPATCH 0x80118028
0:
   li r3, 1
9:

#============================================================================
# Rather than calling VdDisplayFatalError to display an E69 (hehehehe),
# jump to the error handler in SataDiskAuthenticateDevice
#============================================================================
KMAKEPATCH 0x80117EC8
0:
   KMAKEBRANCH 0x80118028
9:

#============================================================================
# During Phase1 initialization, after we've loaded xam.xex, branch to free
# space so we can load launch.xex. This is a bit simpler of a function
# compared to what 17559 does... this is closer to what RGLoader does.
#============================================================================
.set Phase1PatchAddress, 0x80060F2C
.set XeKeysFreeSpace, 0x8011C9E0
.set XexLoadImage, 0x80078210

KMAKEPATCH Phase1PatchAddress
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
   KMAKEBRANCH (Phase1PatchAddress - 0x2C)

   # Do the instruction that the Phase1Initialization patch replaced
   # then branch back to the last instruction of Phase1Initialization
   li %r3, 0
   KMAKEBRANCH (Phase1PatchAddress + 0x4)
9:

#=============================================================================
# Patches XexGetModuleImportVersions
#=============================================================================
KMAKEPATCH 0x80078008
0:
   li r3, 0
9:

.long 0xffffffff
