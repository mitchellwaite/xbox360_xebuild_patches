# Fuck if I know if this is accurate :)

.include "macros.S"

# Start of the syscall table. This is where the address of the real HvxGetVersions (Syscall0) function is found
.set Syscall_Table, 0x15FD0

# Real HV Functions
.set HV_HvxGetVersions,0x1cc8
.set HV_memcpy, 0xa880
.set HV_PrintDotDest, 0x2d8
.set HV_XeCryptAesKey, 0x200f8
.set HV_HvpGetFlashBaseAddress, 0x68C
.set HV_HvpFlashCopy, 0x484

.set HV_FlagFixer, 0xB510
.set HV_setmemprot, 0x154c

# Functions within the patches, some of these change depending on what
# features are enabled.
.ifdef vfuses
   .set FixFusesAddr, 0xB560
   .set PrintChar, 0xB56C
   .set HV_PP_Syscall0, 0xB594
.else
   .set PrintChar, 0xB53C
   .set HV_PP_Syscall0, 0xB564
.endif

# ============================================================================
#	Branch to HV flag fix function???
# ============================================================================
# 00 00 18 80 00 00 00 01 48 00 B5 13
MAKEPATCH 0x1880
0:
	bla HV_FlagFixer
9:

# ============================================================================
# Vfuse patches for the HV
# ============================================================================
.ifdef vfuses
MAKEPATCH 0x000071EC
0:
	nop
9:

MAKEPATCH 0x00001D10
0:
	bla 0xb560
9:

MAKEPATCH 0x00001D24
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009778
0:
	bla 0xb560
9:

MAKEPATCH 0x000097A8
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009918
0:
	bla 0xb560
9:

MAKEPATCH 0x00009948
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009A68
0:
	bla 0xb560
9:

MAKEPATCH 0x00009A98
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009D08
0:
	bla 0xb560
9:

MAKEPATCH 0x00009D38
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x0000A078
0:
	bla 0xb560
9:

MAKEPATCH 0x0000A0A8
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x0000A138
0:
	bla 0xb560
9:

MAKEPATCH 0x0000A168
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

MAKEPATCH 0x0000A470
0:
	bla 0xb560
9:

MAKEPATCH 0x0000A49C
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

.endif
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
MAKEPATCH 0x11BC
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
	mtspr 0x3b5, %r1      # .long 0x7C35EBA6
	ba 0x11c0
9:

# ============================================================================
#	??? nop's something out
# ============================================================================
# 00 00 31 20 00 00 00 01 60 00 00 00
MAKEPATCH 0x3120
0:
	nop
9:

# ============================================================================
# 	Disable fuse blowing ???
# ============================================================================
# 00 00 A5 60 00 00 00 02 38 60 00 01 4E 80 00 20
MAKEPATCH 0x0000A560
0:
	li %r3, 1
	blr
9:

# ============================================================================
#	HvxLoadImageData - nop's out a sig check?
# ============================================================================
# 00 02 A3 0C 00 00 00 02 60 00 00 00 60 00 00 00
MAKEPATCH 0x0002A30C
0:
	nop
	nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 80 00 00 00 01 60 00 00 00
MAKEPATCH 0x0002AA80
0:
	nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 8C 00 00 00 01 60 00 00 00
MAKEPATCH 0x0002AA8C
0:
	nop
9:

# ============================================================================
#	HV Flag Fixer??? branched from 0x1880
#	Followed by HV Syscall0 PeekPoke backdoor starting at 0xB594
# ============================================================================
MAKEPATCH HV_FlagFixer
0:
	mflr %r8
	lhz %r3, 6(0)
	li %r4, 0x21
	andc %r3, %r3, %r4
	sth %r3, 6(0)

   # This is the vfuse loading code
   # Seems like it's smart enough to look
   # at 0x64 and 0x70 (patch slot addr and size)
   # to determine where to find the vfuses... XDKbuild
   # hardcodes this to 0xE0000 which is kind of stupid IMO
.ifdef vfuses
	bla HV_HvpGetFlashBaseAddress
	lwz %r4, 0x64(%r3) # 0x64 in NAND is the patch slot address
	lwz %r5, 0x70(%r3) # 0x70 in NAND is the patch slot size
	add %r3, %r3, %r4
	add %r4, %r3, %r5

	lis %r3, 1
	subi %r3, %r3, 0x60
   # 0x60 bytes, 0xC 64bit vals to copy
	li %r5, 0xc
	bla HV_HvpFlashCopy
.endif

	li %r3, '!'
	bla PrintChar
	li %r3, '\n'
	bla PrintChar
	mtlr %r8
	ba HV_PrintDotDest

# ---------------------------------------------------
# FixFusesAddr
# 0xB560 w/ vfuses
# TODO figure out how to calculate this automatically
# ---------------------------------------------------
.ifdef vfuses
	lis %r3, 1
	subi %r3, %r3, 0x60
	blr
.endif

# ---------------------------------------------------
# PrintChar
# 0xB56C w/ vfuses
# 0xB53C w/o vfuses
# TODO figure out how to calculate this automatically
# ---------------------------------------------------
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 0xea00
	slwi %r3, %r3, 0x18
	stw %r3, 0x1014(%r4)

charwait:
	lwz %r3, 0x1018(%r4)
	rlwinm. %r3, %r3, 0, 6, 6
	beq charwait
	blr

# ---------------------------------------------------
# HV_PP_Syscall0 (syscall 0 backdoor)
# 0xB594 w/ vfuses
# 0xB564 w/o vfuses
# TODO figure out how to calculate this automatically
# ---------------------------------------------------
	lis %r11, 0x7262                  # Freeboot syscall key - 0x72627472 "rbtr" 1st half
	ori %r11, %r11, 0x7472             # 2nd half

	cmplw cr6, %r3, %r11               # Check for the magic key 0x72627472
	beq cr6, checkOpType             # Branch to checkOpType if matches - 0xb578
	ba HV_HvxGetVersions             # If not, branch back to the real HvxGetVersions

checkOpType:  # 0xB5A8
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

MAKEPATCH Syscall_Table
0:
	.long HV_PP_Syscall0
9:

# ============================================================================
#       HvxSecurity Functions  (sets machine acct flags)
# ============================================================================
# 00 00 6B B0 00 00 00 02 38 60 00 00 4E 80 00 20
MAKEPATCH 0x00006BB0
0:
	li %r3, 0
	blr
9:

# 00 00 6C 48 00 00 00 02 38 60 00 00 4E 80 00 20
# HvxSecurityGetDetected
MAKEPATCH 0x00006C48
0:
	li %r3, 0
	blr
9:

# 00 00 6C 98 00 00 00 02 38 60 00 00 4E 80 00 20
# HvxSecuritySetActivated
MAKEPATCH 0x00006C98
0:
	li %r3, 0
	blr
9:

# 00 00 6D 08 00 00 00 02 38 60 00 00 4E 80 00 20
# HvxSecurityGetActivated
MAKEPATCH 0x00006D08
0:
	li %r3, 0
	blr
9:

# 00 00 6D 58 00 00 00 02 38 60 00 00 4E 80 00 20
# HvxSecuritySetStat
MAKEPATCH 0x00006D58
0:
	li %r3, 0
	blr
9:

# ============================================================================
#	HvxKeysGetKey - Allow access to all XeKeys properties
# ============================================================================
# 00 00 81 3C 00 00 00 01 48 00 00 30
MAKEPATCH 0x0000813C
0:
	b 0x30
9:

# ============================================================================
# 	Bypass CB sig check - Replaces call to XeCryptBnQwBeSigVerify
# ============================================================================
# 00 00 70 BC 00 00 00 01 38 60 00 01
MAKEPATCH 0x000070BC
0:
	li %r3, 1
9:

# ============================================================================
# 	Bypass CD check
# ============================================================================
# 00 00 72 68 00 00 00 01 38 60 00 00
MAKEPATCH 0x00007268
0:
	li %r3, 0
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
# 00 00 72 B4 00 00 00 01 60 00 00 00
MAKEPATCH 0x000072B4
0:
	nop
9:

# ============================================================================
#	NOP MachineCheck
# ============================================================================
# 00 00 72 C4 00 00 00 01 60 00 00 00
MAKEPATCH 0x000072C4
0:
	nop
9:

# ============================================================================
#	NOP MachineCheck
# ============================================================================
# 00 00 72 EC 00 00 00 02 60 00 00 00 39 60 00 01
MAKEPATCH 0x000072EC
0:
	nop
	li %r11, 1
9:

# ============================================================================
#	HvpCompareXGD2MediaID - Always return true
# ============================================================================
# 00 02 4D 58 00 00 00 02 38 60 00 01 4E 80 00 20
MAKEPATCH 0x00024D58
0:
	li %r3, 1
	blr
9:

# ============================================================================
# 	HvpDvdDecryptFcrt - Disable check
#	Replaces HvpPkcs1Verify branch
# ============================================================================
# 00 02 64 F0 00 00 00 01 38 60 00 01
MAKEPATCH 0x000264F0
0:
	li %r3, 1
9:

# ============================================================================
# 	Something related to xex aes key for dev signed support???
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
#
# ============================================================================
# 00 02 9B 08 00 00 00 0E 2B 3C 00 00 41 9A 00 30 2F 03 00 00 40 9A 00 10
# 38 80 00 F0 48 00 00 18 60 00 00 00 2B 1D 00 00 38 9F 04 40 40 9A 00 08 
# 38 80 00 54 7F 83 E3 78 4B FF 65 C1 3B E0 00 00
MAKEPATCH 0x00029B08
0:
   # This section overwrites a check on the return value of XeCryptBnQwBeSigVerify disabling STATUS_IMAGE_CHECKSUM_MISMATCH - C0000221
	cmpldi cr6, %r28, 0         # Value set from r4 being passed to main function being patched
	beq cr6, loc_29b3c         # Branch if zero. This is how it's handled by the function normally when XeCryptBnQwBeSigVerify returns non-zero

	cmpwi cr6, %r3, 0           # Check the return value of XeCryptBnQwBeSigVerify performed just before these patches
	bne cr6, loc_29B24         # Branch when non-zero

	li %r4, 0xf0                # Address of Devkit XEX2 AES key that has been set to all zero.
	b loc_29b34
	nop

   # Everything below remains unchanged??? Maybe it's just here to make it easier to create branches when compiling???
   # At 0x29B24 here. This section is normally performed here just after the r28 check
loc_29B24:
	cmplwi cr6, %r29, 0
	addi %r4, %r31, 0x440
	bne cr6, loc_29b34
	li %r4, 0x54                # Address of Retail XEX2 AES key - 20 B1 85 A5 9D 28 FD C3 40 58 3F BB 08 96 BF 91

loc_29b34:
	mr %r3, %r28
	bl 0xffffffffffff65c0       # Branch to 0x200f8 XeCryptAesKey

loc_29b3c:
	li %r31, 0
9:

# ============================================================================
# 	HvxImageTransformImageKey - Disables a conditional branch
# ============================================================================
# 00 02 B7 78 00 00 00 01 60 00 00 00
MAKEPATCH 0x0002B778
0:
	nop
9:

# ============================================================================
# 	HvxCreateImageMapping hash check
# ============================================================================
# 00 02 CA E8 00 00 00 01 38 60 00 00
MAKEPATCH 0x0002CAE8
0:
	li %r3, 0
9:

# ============================================================================
# 	HvxCreateImageMapping HV XEX region check 
# ============================================================================
# 00 02 CD D8 00 00 00 01 60 00 00 00
MAKEPATCH 0x0002CDD8
0:
	nop
9:

# ============================================================================
# 	HvxExpansionInstall - Disable conditional branch after XeCryptBnQwBeSigVerify
# ============================================================================	
# 00 03 08 9C 00 00 00 04 40 9A 00 08 3B A0 00 00 60 00 00 00 60 00 00 00
MAKEPATCH 0x0003089C
0:
	bne cr6, loc_2b8
	li %r29, 0

loc_2b8:
	nop
	nop
9:

# ============================================================================
#	HvpInstallExpansion - Disable XeKeysStatus check
# ============================================================================
# 00 03 04 E8 00 00 00 01 60 00 00 00
MAKEPATCH 0x000304E8
0:
	nop
9:

# ============================================================================
#	HvpInstallExpansion - Disable KV Restricted Privs check
# ============================================================================
# 00 03 04 FC 00 00 00 01 60 00 00 00
MAKEPATCH 0x000304FC
0:
	nop
9:

#============================================================================
# Patches XexpConvertError
#============================================================================
# 00 07 B9 20 00 00 00 02 38 60 00 00 4E 80 00 20
KMAKEPATCH 0x8007B920
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches branch to XexpVerifyMediaType within XexpLoadXexHeaders
#=============================================================================
# 00 07 C4 B8 00 00 00 01 38 60 00 01
KMAKEPATCH 0x8007C4B8
0:
	li %r3, 1
9:

#=============================================================================
# Patches branch to RtlImageXexHeaderString within XexpLoadFile
#=============================================================================
# 00 07 C5 E8 00 00 00 01 38 60 00 00
KMAKEPATCH 0x8007C5E8
0:
	li %r3, 0
9:

#=============================================================================
# Patch within XexpLoadFile
#=============================================================================
# 00 07 C6 34 00 00 00 01 39 60 00 00
KMAKEPATCH 0x8007C634
0:
	li %r11, 0
9:

#=============================================================================
# Patch within XexpLoadFile
#=============================================================================
# 00 07 C6 84 00 00 00 01 39 60 00 00
KMAKEPATCH 0x8007C684
0:
	li %r11, 0
9:

#=============================================================================
# Patches XexpVerifyMinimumVersion
#=============================================================================
# 00 07 AF 08 00 00 00 02 38 60 00 00 4E 80 00 20
KMAKEPATCH 0x8007AF08
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patch within SfcxInspectLargeDataBlock
#=============================================================================
# 00 09 4F 78 00 00 00 01 3A E0 00 10
KMAKEPATCH 0x80094F78
0:
	li %r23, 0x10
9:

#=============================================================================
# Patch within SataCdRomAuthenticationExInitialize
#=============================================================================
# 00 09 98 D0 00 00 00 01 2B 0B 00 FF
KMAKEPATCH 0x800998D0
0:
	cmplwi cr6, %r11, 0xff
9:


#=============================================================================
# Patches to disable fatal error screen E66 (VdDisplayFatalError)
# Caused by DVD drive (ERROR_XSS_CDROM_COULD_NOT_CREATE_DEVICE)
#=============================================================================
# 00 09 92 B4 00 00 00 05 38 60 00 00 60 00 00 00 60 00 00 00 60 00 00 00 60 00 00 00
KMAKEPATCH 0x800992B4
0:
	li %r3, 0
	nop
	nop
	nop
	nop
9:

#=============================================================================
# Patches XeKeysVerifyRSASignature
#=============================================================================
# 00 10 9C 90 00 00 00 02 38 60 00 01 4E 80 00 20
KMAKEPATCH 0x80109C90
0:
	li %r3, 1
	blr
9:

#=============================================================================
# Patches XeKeysSecurityConvertError
#=============================================================================
# 00 10 A7 88 00 00 00 02 38 60 00 00 4E 80 00 20
KMAKEPATCH 0x8010A788
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches XeKeysDvdAuthExConvertError
#=============================================================================
# 00 10 AA 68 00 00 00 02 38 60 00 00 4E 80 00 20 
KMAKEPATCH 0x8010AA68
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches _XeKeysRevokeIsValid
#=============================================================================
# 00 10 AF 30 00 00 00 02 38 60 00 01 4E 80 00 20 
KMAKEPATCH 0x8010AF30
0:
	li %r3, 1
	blr
9:

#=============================================================================
# Patches XeKeysRevokeIsRevoked
#=============================================================================
# 00 10 B1 38 00 00 00 02 38 60 00 00 4E 80 00 20 
KMAKEPATCH 0x8010B138
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches _XeKeysRevokeIsRevoked
#=============================================================================
# 00 10 B0 E8 00 00 00 02 38 60 00 00 4E 80 00 20 
KMAKEPATCH 0x8010B0E8
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches XeKeysRevokeIsDeviceRevoked
#=============================================================================
# 00 10 B2 78 00 00 00 02 38 60 00 00 4E 80 00 20 
KMAKEPATCH 0x8010B278
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches XeKeysRevokeConvertError
#=============================================================================
# 00 10 B3 F8 00 00 00 02 38 60 00 00 4E 80 00 20
KMAKEPATCH 0x8010B3F8
0:
	li %r3, 0
	blr
9:

#=============================================================================
# Patches XeKeysConsoleSignatureVerification
#=============================================================================
# 00 10 BF 20 00 00 00 05 2B 05 00 00 38 60 00 01 41 9A 00 08 90 65 00 00 4E 80 00 20
KMAKEPATCH 0x8010BF20
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
# 00 11 19 90 00 00 00 02 38 60 00 01 4E 80 00 20
KMAKEPATCH 0x80111990
0:
	li %r3, 1
	blr
9:

#=============================================================================
# Patch within MassConfigureTransferCable (Skips hdd security sector verification???)
#=============================================================================
# 00 0E 17 54 00 00 00 01 48 00 00 54
KMAKEPATCH 0x800E1754
0:
	b 0x54
9:

#=============================================================================
# Patch within MassConfigureTransferCable
#=============================================================================
# 00 0E 17 CC 00 00 00 03 83 5C 00 98 60 00 00 00 60 00 00 00
KMAKEPATCH 0x800E17CC
0:
	lwz %r26, 0x98(%r28)
	nop
	nop
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice (Disables hdd security sector verification)
#============================================================================
# 00 15 D9 D8 00 00 00 02 38 60 00 01 4E 80 00 20
KMAKEPATCH 0x8015D9D8
0:
	li %r3, 1
	blr
9:

#=============================================================================
# Patches here use the space available within XeKeysConsoleSignatureVerification
# due to it being patched out earlier and no longer used.
#============================================================================
# 00 10 BF 40 00 00 00 2C 40 98 00 08 4E 80 00 20 3C 60 80 10 3C A0 00 00
# 38 80 00 00 60 84 00 08 60 63 BF D0 38 C0 00 00 4B F7 18 61 38 60 00 00
# 3C 80 80 10 60 84 BF EC 4C 00 01 2C 90 64 00 00 4B F5 54 64 38 A1 00 54
# 3C E0 80 10 60 E7 BF EC 81 07 00 00 4C 00 01 2C 2B 08 00 00 41 9A 00 0C
# 7F FF FB 78 4B FF FF EC 4E 80 00 20 2B 03 00 14 40 9A 00 24 3C E0 80 10
# 60 E7 BF EC 81 07 00 00 4C 00 01 2C 2B 08 00 00 41 9A 00 0C 7F FF FB 78
# 4B FF FF EC 4B FF C4 44 5C 44 65 76 69 63 65 5C 46 6C 61 73 68 5C 6C 61
# 75 6E 63 68 2E 78 65 78 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 
# 12 34 56 78
KMAKEPATCH 0x8010BF40
0:
   #=============================================================================
   # Branched here from a patch in Phase1Initialization
   # Checks if xam was loaded successfully.
   # Branches to launch.xex loader if successful
   #=============================================================================
	bge cr6, 0x8 # If xam was loaded successfully branch to the function that loads launch.xex at 0x8010bf48 below. Original patch decompiled as 0x10bf48
	blr

   #=============================================================================
   # Branched here from patch above
   # launch.xex loader
   # we're at 0x8010bf48 at this point
   #=============================================================================
# XexLoadImage Setup
	lis %r3, 0x8010         # Set r3 to address of launch.xex path string 0x8010bfd0 - 1st half
	lis %r5, 0               # Set r5 (MinimumVersion)
	li %r4, 0               # Set r4 (ModuleTypeFlags) - 1st half
	ori %r4, %r4, 8         # Set r4 (ModuleTypeFlags) - 2nd half
	ori %r3, %r3, 0xbfd0      # Set r3 to address of launch.xex path string 0x8010bfd0 - 2nd half
	li %r6, 0                # Set r6 (pHandle)

# Run XexLoadImage    
	bl 0xfffffffffff71860    # 0x8007d7c0 - XexLoadImage - Attempt to load launch.xex. Note there is no check for whether this was successful
# Signify this has completed
	li %r3, 0                # Set r3 to zero
	lis %r4, 0x8010         # Set r4 to the address other functions check for completion (0x8010bfec) - 1st half - (The 0x12345678 after the launch.xex path)
	ori %r4, %r4, 0xbfec      # Set r4 to the address other functions check for completion (0x8010bfec) - 2nd half
	isync
	stw %r3, 0(%r4)           # Sets value at the address to zero so signify completion to allow other functions to act accordingly
	b 0xfffffffffff55464      # 0x800613dc - Branches back to Phase1Initialization to continue. This is where it would have branched to originally if xam was loaded without these patches

   #=============================================================================
   # Branched here from a patch in XexLoadExecutable
   # we're at 0x8010BF7C at this point
   #=============================================================================
	addi %r5, %r1, 0x54
# Set the address to check
	lis %r7, 0x8010         # Set r7 to the address to check for completion (0x8010bfec) - 1st half - (The 0x12345678 after the launch.xex path)
	ori %r7, %r7, 0xbfec      # Set r7 to the address to check for completion (0x8010bfec) - 2nd half
# Check value is zero loop - We're at 0x8010bf88
	lwz %r8, 0(%r7)           # Stores the current value at the address in r8 - Jumps back here until the value is zero
	isync
	cmplwi cr6, %r8, 0       # Checks if value is zero - This would signify the launch.xex loader has ran and therefore set the value to zero
	beq cr6, 0xC            # If true branch to the blr at 0x8010bfa0. Original patch decompiled as 0x10bfa0
	mr %r31, %r31
	b 0xffffffffffffffec              # Branches back to the storing the value for rechecking 0x8010bf88
	blr                     # Check returned true so return

   #=============================================================================
   # Branched here from a patch in XeKeysGetKeyProperties
   # we're at 0x8010BFA4 at this point
   #=============================================================================
	cmplwi cr6, %r3, 0x14
	bne cr6, 0x24           # If false, skip everything and branch to the complete branch at 0x8010bfcc. Original patch decompiled as 0x10bfcc
# Set the address to check
	lis %r7, 0x8010         # Set r7 to the address to check for completion (0x8010bfec) - 1st half - (The 0x12345678 after the launch.xex path)
	ori %r7, %r7, 0xbfec      # Set r7 to the address to check for completion (0x8010bfec) - 2nd half
# Check value is zero loop - We're at 0x8010bfb4
	lwz %r8, 0(%r7)           # Stores the current value at the address in r8 - Jumps back here until the value is zero
	isync
	cmplwi cr6, %r8, 0       # Checks if value is zero - This would signify the launch.xex loader has ran and therefore set the value to zero
	beq cr6, 0xC            # If true branch to the complete branch at 0x8010bfcc. Original patch decompiled as 0x10bfcc
	mr %r31, %r31
	b 0xffffffffffffffec              # Branches back to the storing the value for rechecking at 0x8010bfb4
# Check has completed successfully
	b 0xffffffffffffc444              # 0x80108410 - HvxKeysGetKeyProperties (not _HvxKeysGenerateRandomKey. naming by script outdated ????)

   #=============================================================================
   # launch.xex path string - \Device\Flash\launch.xex
   # we're at 0x8010bfd0 at this point
   #=============================================================================
   .long 0x5C446576    
   .long 0x6963655C    
   .long 0x466C6173    
   .long 0x685C6C61    
   .long 0x756E6368    
   .long 0x2E786578
   .long 0

   #=============================================================================
   # Functions above will loop until this is set to zero when loading launch.xex
   # we're at 0x8010bfec at this point
   #=============================================================================
	.long 0x12345678
9:

#=============================================================================
# Patch within Phase1Initialization
# Branch to check if xam was loaded
# This is the first part of the launch.xex loader
#============================================================================
# 00 06 13 CC 00 00 00 01 48 0A AB 75
KMAKEPATCH 0x800613CC
0:
	bl 0xaab74
9:

#=============================================================================
# Patch within XexLoadExecutable
#============================================================================
# 00 07 D7 F8 00 00 00 01 48 08 E7 85
KMAKEPATCH 0x8007D7F8
0:
	bl 0x8e784  # 0x8010bf7c
9:

#=============================================================================
# Patches XeKeysGetKeyProperties to branch to a custom function
#============================================================================
# 00 10 8E 70 00 00 00 01 48 00 31 34
KMAKEPATCH 0x80108E70 
0:
	b 0x3134    # 0x8010bfa4
9:

# ===================================
# These bits are in the premade RGH3 glitch2m images
# nointmu and nohdmiwait are enabled by default
# ===================================
.ifdef rgh3_patches

# nohdmiwait patch
MAKEPATCH 0x0015BC80
0:
	b 0x4c
9:

# nointmu patch
MAKEPATCH 0x0008E098
0:
	lis %r10, 0x6000
9:

MAKEPATCH 0x000E25A8
0:
	lis %r10, 0x6000
9:

MAKEPATCH 0x0008F3F8
0:
	blr
9:
.endif

# done with patch section

#============================================================================
.long 0xFFFFFFFF
.end
#============================================================================
