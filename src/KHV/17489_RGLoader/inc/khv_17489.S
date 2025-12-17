.include "macros.S"
.set rgloader, 1

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

#
# Additional patches for RGLoader
# Based on the patch set in https://github.com/GoobyCorp/Xbox-360-Crypto/tree/master/Patches/RGL/17559-dev
#
.ifdef rgloader

# ============================================================================
# Retail XEX2 AES key
# ============================================================================
	MAKEPATCH 0x000000F0
0:
	.long 0x20B185A5
	.long 0x9D28FDC3
	.long 0x40583FBB
	.long 0x0896BF91
9:

# ============================================================================
# 	Enable retail xex decryption
# ============================================================================
	MAKEPATCH 0x00029C4C
0:
	b       0x10   #;//skip signature check for retail consoles. (allow patched xex)
9:
	MAKEPATCH 0x00029C70
0:
	li      %r4,  0xF0   #;//patch XexAes key to retail one at 0xF0
9:

# ============================================================================
#       HvxSecuity Functions  (sets machine acct flags)
# ============================================================================
	MAKEPATCH 0x00006C58  #;// HvxSecurityGetActivated
0:
	li     %r3, 0
	blr
9:
	MAKEPATCH 0x00006B98  #;// HvxSecurityGetDetected
0:
	li     %r3, 0
	blr
9:
	MAKEPATCH 0x00006BE8  #;// HvxSecuritySetActivated
0:
	li     %r3, 0
	blr
9:
	MAKEPATCH 0x00006B00  #;// HvxSecuritySetDetected
0:
	li     %r3, 0
	blr
9:
	MAKEPATCH 0x00006CA8  #;// HvxSecuritySetStat
0:
	li     %r3, 0
	blr
9:
	MAKEPATCH 0x00006D08
0:
	li  %r3, 0
	blr
9:
	MAKEPATCH 0x00006C48  #;// HvxSecuritySetActivated
0:
	li  %r3, 0
	blr
9:

# ============================================================================
#   Patch XEX flag
# ============================================================================
	MAKEPATCH 0x000072F0
0:
	li %r3, 0
9:
	MAKEPATCH 0x000076A0
0:
	li %r4, 0x8
	li %r3, 0
9:

# ============================================================================
#	HV Patch blow fuses              
# ============================================================================
	MAKEPATCH 0x0000A1C8
0:
	li %r3, 1 
	blr
9:

# ============================================================================
#   DVDAuth2 retail key
#     note: should stay constant
# ============================================================================
MAKEPATCH 0x00010D08
0:
	.long 0xD1E3B33A
	.long 0x6C1EF770
	.long 0x5F6DE93B
	.long 0xB6C0DC71
9:

# ============================================================================
#	HvxDvdAuthRecordXControl  Remove signature check
# ============================================================================
	MAKEPATCH 0x00026C04
0:
	li  %r3, 1
9:

# ============================================================================
#   HV DAE
# ============================================================================
	MAKEPATCH 0x00029018
0:
	li    %r3, 0
9:

# ============================================================================
#	HvxSetImagePageTableEntry memory addr check
# ============================================================================
	MAKEPATCH 0x00029E28
0:
	nop
9:

# ============================================================================
#	HvxCreateImageMapping hash check
# ============================================================================
	MAKEPATCH 0x0002C82C
0:
	b  0x10
9:

# ============================================================================
#	HvxCreateImageMapping HV XEX region check 
# ============================================================================
	MAKEPATCH 0x0002C924
0:
	nop
9:

# ============================================================================
#	HvxExpansionInstall sig check
# ============================================================================
    MAKEPATCH 0x00030BAC
0:
    nop
9:

#------------
#=============================================================================
# Kernel patches
#=============================================================================
#------------

# ============================================================================
#       Fix controller desync bug that still exists..  
# ============================================================================
	KMAKEPATCH 0x801287F4
0:
	ori		%r9, %r9, 8
	stb		%r9, 0x6F(%r31)
9:

# ============================================================================
#	XexpVerifyXexHeaders
# ============================================================================
	KMAKEPATCH 0x800A0994
0:
	li   %r3,  1 
9:
	KMAKEPATCH 0x800A09F0
0:
	nop
9:

# ============================================================================
#	XexpVerifyMinimumVersion
# ============================================================================
	KMAKEPATCH 0x800A17B0
0:
	li   %r3,  0
9:

# ============================================================================
#	XexpLoadFile
# ============================================================================
	KMAKEPATCH 0x8009EE78
0:
	li   %r3,  1
9:

# ============================================================================
#	SataCdRomActivateHCDFRuntimePatch  
#       patch out blacklisted drives for XGD3 discs (zero ExpUpdateModule)
# ============================================================================
	KMAKEPATCH 0x800C51E8
0:
	li   %r11, 0
9:
	KMAKEPATCH 0x800C5210
0:
	li   %r11, 0
9:

# ============================================================================
#   SataCdRomAuthenticationExSequence
# ============================================================================
	KMAKEPATCH 0x800C57D8
0:
	b   0x38
9:

# ============================================================================
#	SataCdRomVerifyDVDX2AuthoringSignature
# ============================================================================
	KMAKEPATCH 0x800C3788
0:
	li   %r3, 1
9:

# ============================================================================
#	SataDiskAuthenticateDevice
# ============================================================================
	KMAKEPATCH 0x801B0C98 
0:
	li   %r3, 1
9:

# ============================================================================
#	XeKeysVerifyRSASignature
# ============================================================================
	KMAKEPATCH 0x8014A128
0:
	nop
9:
	KMAKEPATCH 0x8014A028
0:
	li    %r3, 1
	blr
9:
	KMAKEPATCH 0x8014A15C
0:
	li   %r3, 1
9:

# ============================================================================
#	XeKeysVerifyPIRSSignature
# ============================================================================
	KMAKEPATCH 0x8014A1FC
0:
	li    %r3, 1
9:

# ============================================================================
#	XeKeysConsoleSignatureVerification
#       patch flag check  & always return 1
# ============================================================================
	KMAKEPATCH 0x8014C35C
0:
	li   %r3, 1
9:
	KMAKEPATCH 0x8014C344
0:
	li   %r3, 1
9:
	KMAKEPATCH 0x8014C364
0:
	li   %r3, 1
9:

# ============================================================================
#	XexDeltaDecompressHeaders
#       remove hash check
# ============================================================================
	KMAKEPATCH 0x800A6494
0:
	li   %r3, 0x14
9:

# ============================================================================
#	XexpLoadCompressedImage
#       remove hash check
# ============================================================================
	KMAKEPATCH 0x800A5BDC
0:
	li   %r3, 0x14
9:

# ============================================================================
#	XexpLoadDeltaCompressedImage
#       remove hash check
# ============================================================================
	KMAKEPATCH 0x800A628C
0:
	li   %r3, 0x14
9:

# ============================================================================
#	XexpVerifyMediaType
# ============================================================================
	KMAKEPATCH 0x8009EEDC
0:
	li   %r3,  1
9:

# ============================================================================
#	VdpDelayExecution
# ============================================================================
	KMAKEPATCH 0x800F4B2C
0:
	nop
9:
	KMAKEPATCH 0x800F4B38
0:
	nop
9:

# ============================================================================
#	XexpVerifyDeviceId 
#       always return 0
# ============================================================================
	KMAKEPATCH 0x800A0DB8
0:
	li   %r3, 0
9:
	KMAKEPATCH 0x800A0FC4
0:
	li   %r3, 0
9:

# ============================================================================
#	StfsMapNewBlock hash mismatch
# ============================================================================
	KMAKEPATCH 0x800E22CC
0:
	b    0x34  #patch to unconditional branch
9:

# ============================================================================
#	StfsNonCachedRead
#       remove hash check (nop out bne)
# ============================================================================
	KMAKEPATCH 0x800E45E0
0:
	nop
9:

# ============================================================================
#	SvodMapNewBlock hash mismatch 
# ============================================================================
	KMAKEPATCH 0x80193BE8
0:
	b 0x30  #patch to unconditional branch
9:

# ============================================================================
#	SvodPartiallyCachedRead hash mismatch
# ============================================================================
	KMAKEPATCH 0x80193FFC
0:
	nop
9:

# ============================================================================
#	XeKeysSecurityLoadSettings - ignore
# ============================================================================
	KMAKEPATCH 0x800816C0
0:
	nop
9:

# ============================================================================
#	XexpScanImageCodeSection - ignore
# ============================================================================
	KMAKEPATCH 0x8009FD90
0:
	b 0x5C
9:

# ============================================================================
#	Set KdpRetryCount and KdNetRetryCount to 1
#      (faster boot speed due to smaller kd timeout)
# ============================================================================

.set  KdpRetryCount,    0x801DD80C   #default value is 5
.set  KdNetRetryCount,  0x801DD81C   #default value is 3

	KMAKEPATCH KdpRetryCount
0:
	.long 0x00000001  #patch to 1 retry
9:

	KMAKEPATCH KdNetRetryCount
0:
	.long 0x00000001  #patch to 1 retry
9:

# ============================================================================
#	Remove fcrt.bin hash check
# ============================================================================
	MAKEPATCH 0x000264F0
0:
	li    %r3, 1
9:

# ============================================================================
#	Disable memory protection on devkits
# ============================================================================
	MAKEPATCH 0x000011BC
0:
	ba  0x15F0
9:

	MAKEPATCH 0x000015F0
0:
	li  %r4, 7
	.long 0x7C212078
	.long 0x7C35EBA6
	ba 0x11C0
9:

	MAKEPATCH 0x00030090
0:
	ori       %r4, %r4, 0x1B0
9:

# ============================================================================
#	Ignore heap allocation errors
# ============================================================================
    KMAKEPATCH 0x800AF5CC
0:
	nop
9:

    KMAKEPATCH 0x8009FE50
0:
	nop
9:

# ============================================================================
#	Hypervisor Peek Poking on RGL  (freeboot type access using syscall 0)
# ============================================================================

#;//Set these to the addresses of functions in the HV
.set oldHvxGetVer, 0x1B98
.set memcpy, 0xA4E0
.set sysCallTable, 0x15EC0
#;//Set this to empty space (usually zero space after jump codes (ex: b180 XeCryptUidEccEncode_0 from 16537))
.set newHvxGetVer, 0xB328

	MAKEPATCH sysCallTable
0:
	.long   newHvxGetVer
9:

#;// HvxExecute  Params( 0x72627472, 4, (QWORD)srcAddr, (QWORD)destAddr, (QWORD) lenInBytes)  will jump to destAddr after memcpy
#;// MemCpy      Params( 0x72627472, 5, (QWORD)srcAddr, (QWORD)destAddr, (QWORD) lenInBytes)
	MAKEPATCH newHvxGetVer
0:
	#;//check if secret key is right..
	lis       %r11, 0x7262 #;// 0x72627472
	ori       %r11, %r11, 0x7472 #;// 0x72627472
	cmplw     cr6, %r3, %r11
	beq       cr6, checkOpType
	ba        oldHvxGetVer

checkOpType:                             
	cmplwi    cr6, %r4, 4
	bgt       cr6, doMemCpy
	beq       cr6, hvxExecuteCode
	li        %r5, 0x15F0
	lis       %r6, 0x3880 #;//0x38800007
	cmplwi    cr6, %r4, 2
	bne       cr6, loc_B5C0
	ori       %r6, %r6, 7 #;//0x38800007
	b         loc_B5C8

loc_B5C0:
	cmplwi    cr6, %r4, 3
	bne       cr6, loc_B5E0

loc_B5C8:
	li        %r0, 0
	stw       %r6, 0(%r5)
	dcbst     %r0, %r5
	icbi      %r0, %r5
	sync
	isync

loc_B5E0:
	li        %r3, 1
	blr

hvxExecuteCode:
	mfspr   %r12, lr
	std     %r12, -8(%r1)
	stdu    %r1, -0x10(%r1)
	mtspr   lr, %r5
	mtspr   ctr, %r7

cpyLoop:
	lwz       %r4, 0(%r6)
	stw       %r4, 0(%r5)
	dcbst     %r0, %r5
	icbi      %r0, %r5
	sync
	isync
	addi      %r5, %r5, 4
	addi      %r6, %r6, 4
	bdnz      cpyLoop
	blr
	addi      %r1, %r1, 0x10
	ld        %r12, -8(%r1)
	mtspr   lr, %r12
	blr

doMemCpy:
	cmplwi    cr6, %r4, 5
	bne       cr6, loc_B610
	mr        %r3, %r6
	mr        %r4, %r5
	mr        %r5, %r7
	ba        memcpy

loc_B610:
	li        %r3, 2
	blr
9:

# ============================================================================
#	Load RGLoader.xex after XAM
# ============================================================================

.set ldBranchAddr, 0x80081AC8
.set loaderFuncAddr, 0x801C1774 #;//empty space
.set XexLoadImage, 0x800A3F08

	KMAKEPATCH loaderFuncAddr
0:
	.set strPath, (loaderFuncAddr + 0x20)
	
	lis   %r11, strPath@h
	ori  %r3, %r11, strPath@l
	li %r4, 8
	li %r5, 0
	li %r6, 0
	KMAKEBRANCHL XexLoadImage

	li  %r3, 0
	KMAKEBRANCH (ldBranchAddr+4)
1:
    .string "\\Device\\Flash\\RGLoader.xex\0"
2:
	.align 2
9:

	KMAKEPATCH ldBranchAddr
0:
	KMAKEBRANCHL loaderFuncAddr
9:

# ============================================================================
# Spoof kernel to 17559
# ============================================================================
.set KRNL_VER, 17559

# ============================================================================
#	Disable panic on failed to resolve import
# ============================================================================
	MAKEPATCH 0x0002ACE8
0:
	nop
	nop
	nop
	nop
9:

	MAKEPATCH 0x00000002
0:
	.short KRNL_VER
	.short 0
9:

	MAKEPATCH 0x00001B98
0:
	lis     %r11, 0x0760
	lis     %r10, KRNL_VER
9:

	MAKEPATCH 0x00000010
0:
	.short 0x0760
	.short 0
9:

	KMAKEPATCH 0x80040460
0:
	.short KRNL_VER
	.short 0
9:

	KMAKEPATCH 0x80040468
0:                                      
	.short 0x0760
	.short 0
9:

	MAKEPATCH 0x0002ADB0
0:
	nop
9:

	MAKEPATCH 0x0002ADC0
0:
	nop
9:

	MAKEPATCH 0x0002AE18
0:
	nop
9:

# ============================================================================
#	Fill unresolved ordinals with li r3, 0 ; blr
# ============================================================================
	MAKEPATCH 0x0002AE7C
0:
	bla       0xB208
9:

	MAKEPATCH 0x0000B208
0:
	lwz       %r9, 0x20C(%r1)
	lwz       %r10, 0x74(%r1)
	cmplw     cr6, %r10, %r9
	blt       cr6, 0x18
	lwz       %r10, 0x78(%r1)
	lwz       %r9, 0x208(%r1)
	cmplw     cr6, %r9, %r10
	bge       cr6, 0x8
	lis       %r11, 0x3860
	stw       %r11, 0(%r30)   #;//do what we patched..
	blr
9:

	MAKEPATCH 0x0002AEEC
0:
	bla       0xB2F8
9:

	MAKEPATCH 0x0000B2F8
0:
	clrlwi    %r10, %r29, 16
	cmplwi    cr6, %r10, 0
	bne       cr6, 0xC
	lis       %r29, 0x4E80
	ori       %r29, %r29, 0x20
	stw       %r29, 0(%r11)   #;//do what we patched..
	blr
9:

.endif

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
