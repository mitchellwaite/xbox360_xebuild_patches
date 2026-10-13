# Fuck if I know if this is accurate :)

.include "macros.S"

# ============================================================================
#	Branch to HV flag fix function
# ============================================================================
MAKEPATCH 0x000019A0
0:
	bla HvFlagFixer
9:

# ============================================================================
# Vfuse patches for the HV
# ============================================================================
MAKEPATCH 0x00002AA0
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00002AB4
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000073E8
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00007418
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00007558
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00007588
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00007678
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000076A8
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000078E8
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00007918
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00007A3C
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00007A68
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

# ============================================================================
#	Devkit XEX2 AES key
# ============================================================================
MAKEPATCH 0x000000F0
0:
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
9:

# ============================================================================
# These patches modify the common instruction/data storage interrupt handler
# routines to make all image memory RWX and all heap memory executable. This
# is an improved version of the old patch which now honors page protections
# on heap memory allowing this patch to be enabled at all times even when the
# back compat emulator is running.
#
# Thanks to grimdoomer for providing these!
# ============================================================================
MAKEPATCH 0x00001070
0:
   andi.    %r4, %r4, 0xA        # PTE & (V-D-) = clear NoExecute and ReadOnly
9:

MAKEPATCH 0x0000108C
0:
   andi.    %r4, %r4, 0xA        # PTE & (V-D-) = clear NoExecute and ReadOnly
9:

MAKEPATCH 0x00001268
0:
   andi.    %r4, %r4, 0xA        # PTE & (V-D-) = clear NoExecute and ReadOnly
9:

# ============================================================================
# Disable HvxBlowFuses
# ============================================================================
MAKEPATCH 0x00007C40
0:
	li %r3, 1
	blr
9:

# ============================================================================
#	HvxLoadImageData - nop's out a sig check
# ============================================================================
MAKEPATCH 0x00004DC4
0:
	nop
	nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
MAKEPATCH 0x000054A8
0:
	nop
9:

MAKEPATCH 0x000054B4
0:
	nop
9:

# ============================================================================
#	HV Flag Fixer and other utilities
# ============================================================================

.set HvpGetFlashBaseAddress, 0x998
.set XeCryptCopyQwVec, 0x78C
.set HvxGetVersions, 0x2A58
.set HV_memcpy, 0xCAE0

MAKEPATCH 0x0000D328
.set HvFlagFixer, PatchAddr
.set FixFusesAddr, (PatchAddr + (1f - 0f))

.ifdef jtag_vfuses
   .set FixHoldAddr, (PatchAddr + (2f - 0f))
.endif

.set PrintChar, (PatchAddr + (3f - 0f))
.set HV_PP_Syscall0, (PatchAddr + (5f - 0f))
0:
	mflr %r8
	lhz %r3, 6(0)
	li %r4, 0x21
	andc %r3, %r3, %r4
	sth %r3, 6(0)

	bla HvpGetFlashBaseAddress

.ifdef jtag_vfuses
   # JTAGs use virtual fuses too!
   # They're always at address 0x95000, don't need to
   # do any patch slot size/count calculations 
   oris %r4, %r3, 9
   ori %r4, %r4, 0x5000
   nop
   nop
.else
	lwz %r4, 0x64 (%r3)
	lwz %r5, 0x70 (%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
.endif

	lis %r3, 1
	addi %r3, %r3, -0x60
	li %r5, 0xc
	bla XeCryptCopyQwVec

	li %r3, '!'
	bla PrintChar

	li %r3, '\n'
	bla PrintChar

	mtlr %r8
	ba 0x19a4

# FixFusesAddr
1:
	lis %r3, 1
	addi %r3, %r3, -0x60
	blr

.ifdef jtag_vfuses
# FixHoldAddr
2:
   lis %r4, -0x8000
   sldi %r4, %r4, 0x20
   oris %r4, %r4, 0x100
   ori %r4, %r4, 0x3080
   ba (HV_StartProcPatchAddr + 4)
.endif

# PrintChar
3:
	lis %r4, -0x8000
	ori %r4, %r4, 0x200
	sldi %r4, %r4, 0x20
	oris %r4, %r4, 0xea00
	slwi %r3, %r3, 0x18
	stw %r3, 0x1014 (%r4)
uartwaitloop:
	lwz %r3, 0x1018 (%r4)
	rlwinm. %r3, %r3, 0, 6, 6
	beq uartwaitloop
	blr

# Syscall 0 backdoor
5:
   lis %r11, 0x7262         # Freeboot syscall key - 0x72627472 "rbtr" 1st half
   ori %r11, %r11, 0x7472    # 2nd half
   cmplw cr6, %r3, %r11      # Check for the magic key
   beq cr6, checkOpType		# Branch to checkOpType at 0xD018 if it matches
   ba HvxGetVersions 		# Otherwise branch to the real HvxGetVersions (0x2A48)

checkOpType: # 0xD018
   cmplwi cr6, %r4, 4             # Check for 4, aka hvxExecute
   bgt cr6, doMemCpy 	         # >4 must be MemCpy (0xD0B0)
   beq cr6, hvxExecuteCode 	   # If it matches, must be hvxExecute
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
   sync
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
   bne cr6, returnTwo
   mr %r3, %r6
   mr %r4, %r5
   mr %r5, %r7
   ba HV_memcpy

returnTwo:
   li %r3, 2
   blr
9:

# ============================================================================
# Patch syscall table with address of our fake Syscall0 backdoor
# ============================================================================
MAKEPATCH 0x00001CD4
0:
	.long HV_PP_Syscall0
9:

.ifdef jtag_vfuses
# ============================================================================
# For JTAGs only, we need to patch HvxStartupProcessors
#
# The following patch replaces (addis %r4, %r3, -3) with a branch to our custom
# function, the custom function will then branch back to the instruction
# after what we replaced
# ============================================================================
.set HV_StartProcPatchAddr, 0x1C4C

MAKEPATCH HV_StartProcPatchAddr
0:
   ba FixHoldAddr
9:
.endif

# ============================================================================
#       HvxSecurity Functions  (sets machine acct flags)
# ============================================================================
MAKEPATCH 0x00009300 # HvxSecuritySetDetected
0:
	li %r3, 0
	blr
9:

MAKEPATCH 0x000093C8 # HvxSecurityGetDetected
0:
	li %r3, 0
	blr
9:

MAKEPATCH 0x00009410 # HvxSecuritySetActivated
0:
	li %r3, 0
	blr
9:

MAKEPATCH 0x000094B8 # HvxSecurityGetActivated
0:
	li %r3, 0
	blr
9:

MAKEPATCH 0x0000982C # CB sig check
0:
	li %r3, 1
9:

MAKEPATCH 0x00009838 # machinecheck
0:
	nop
9:

MAKEPATCH 0x00009874 # machinecheck
0:
	nop
9:

MAKEPATCH 0x00009884 # machinecheck
0:
	nop
9:

MAKEPATCH 0x000098AC  # machinecheck
0:
	nop
	li %r11, 1
9:

# ============================================================================
#	HvxKeysRsaPrvCrypt - Allow access to all XeKeys properties
# ============================================================================
MAKEPATCH 0x0000A2E8
0:
	MAKEBRANCH 0xA318
9:

# ============================================================================
#	HvpCompareXGD2MediaID - Always return true
# ============================================================================
MAKEPATCH 0x0000A4D0
0:
	li %r3, 1
	blr
9:

# ============================================================================
# 	xex aes key for dev signed support
# 	Fixes bad signature
#	Overwrites the status STATUS_IMAGE_CHECKSUM_MISMATCH - C0000221
#
# All this patch does is allow for devkit signed xex files
# as a fallback if the call to XeCryptBnQwBeSigVerify fails  (rc = 0).
#
# To allow for unsigned retail xex support on retail kernels, DashLaunch hooks
# XexpLoadImage and XexpVerifyXexHeaders and pokes the instruction in the
# HV to change the fallback decryption key
#
# (Look in the DashLaunch changelog- these hooks were added in V3.0)
# ============================================================================

.set j_XeCryptAesKey, 0xD190

MAKEPATCH 0x00003EE0
0:
	cmpldi cr6, %r28, 0
	beq cr6, xex_ret_zero

	cmpwi cr6, %r3, 0
	bne cr6, xex_proc_key
	li %r4, 0xf0
	b xex_setkey
	nop

xex_proc_key:
	cmplwi cr6, %r29, 0
	addi %r4, %r31, 0x440
	bne cr6, xex_setkey
	li %r4, 0x54

xex_setkey:
	mr %r3, %r28
	MAKEBRANCHL j_XeCryptAesKey

xex_ret_zero:
	li %r31, 0
9:

# ============================================================================
# 	HvxCreateImageMapping hash check
# ============================================================================
MAKEPATCH 0x000041C0
0:
	li %r3, 0
9:

# ============================================================================
# 	HvxCreateImageMapping HV XEX region check 
# ============================================================================
MAKEPATCH 0x00004458
0:
	nop
9:

# Kernel Patches

#=============================================================================
# Patches XexpLoadXexHeaders to ignore xex media type check
#=============================================================================

KMAKEPATCH 0x800776A4  
0:
	KMAKEBRANCH 0x800776b4
9:

KMAKEPATCH 0x800776A8 
0:
	nop 
	nop 
	nop 
9:

#=============================================================================
# Patches XeKeysVerifyRSASignature
#=============================================================================
KMAKEPATCH 0x800ECB40
0:
	li %r3, 1
	blr
9:

KMAKEPATCH 0x800EDAD8 # _XeKeysRevokeIsValid
0:
	li %r3, 1
	blr
9:

KMAKEPATCH 0x800EDB78 # _XeKeysRevokeIsRevoked
0:
	li %r3, 1
	blr
9:

KMAKEPATCH 0x800EDC48 # XeKeysRevokeIsRevoked
0:
	li %r3, 0
	blr
9:

KMAKEPATCH 0x800EDCC0 # XeKeysRevokeConvertError
0:
	li %r3, 0
	blr
9:

KMAKEPATCH 0x800F2CA0 # XeCryptBnQwBeSigVerify_0
0:
	li %r3, 1
	blr
9:

#=============================================================================
# Patches XeKeysConsoleSignatureVerification
#=============================================================================
KMAKEPATCH 0x800EE528 # XeKeysConsoleSignatureVerification
0:
	cmplwi cr6, %r5, 0
	li %r3, 1
	beq cr6, 0x8
	stw %r3, 0(%r5)
	blr
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice
#
# Regular FreeBoot would have done the following at 0x8011A6B8
#     li %r3, 1
#     blr
#
# However, that breaks compat with FATXPlorer formatted drives with a SS and
# "extra space"... this patch does full auth for retail for such drives but
# still allows generic drives by patching the error path to return TRUE
#============================================================================

# Rather than throwing an E69, branch to the error path of SataDiskAuthenticateDevice
KMAKEPATCH 0x8011A6F8
0:
	KMAKEBRANCH 0x8011A858
9:

# Patch out XeCryptBnDwLePkcs1Verify to always report the security sector as "Verified"
KMAKEPATCH 0x8011A81C
0:
	li %r3, 1
9:

# Patch the error handler of SataDiskAuthenticateDevice to return "Device authenticated"
KMAKEPATCH 0x8011A858
0:
	li %r3, 1
9:

#=============================================================================
# Patches XexGetModuleImportVersions
#=============================================================================
KMAKEPATCH 0x80078190
0:
	li %r3, 0
9:

#=============================================================================
# Patch within SfcxInspectLargeDataBlock
#
# Resolves MU corruption by increasing the number of reserved blocks?
#=============================================================================
MAKEPATCH 0x0008CEB8
0:
	li %r23, 0x10
9:

#=============================================================================
# Patches within XexpLoadFile
#=============================================================================
KMAKEPATCH 0x800777B0
0:
	li %r3, 0
9:

KMAKEPATCH 0x80077804
0:
	li %r11, 0
9:

#=============================================================================
# Patches SataCdRomAP25Initialize to disable E66 error
#=============================================================================
MAKEPATCH 0x000902D4
0:
	KMAKEBRANCH 0x800902EC
9:

# ============================================================================
# HvFixKeys patch for zero fuse consoles
# ============================================================================
MAKEPATCH 0x00003434
0:
	nop
9:

MAKEPATCH 0x00000018
0:
    .long 0x81300D49
    .long 0xC232F145
9:

#============================================================================
# usbdsec patch by @InvoxiPlayGames that allows for 3rd party Xinput devices
#============================================================================

# patches UsbdIsDeviceAuthenticated to report all devices as authenticated
KMAKEPATCH 0x800C7128
0:
   li %r3, 1
   blr
9:

# patches inside WgcAddDevice to allow for more leniency on the interface descriptor
KMAKEPATCH 0x800E618C
0:
   b 0x4
9:

# done with patch section
.long 0xffffffff
