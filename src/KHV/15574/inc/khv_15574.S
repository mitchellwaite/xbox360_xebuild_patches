.include "macros.S"

MAKEPATCH 0x00001880 # init hook
0:
	bla 0xadec
9:

.ifdef jtag_vfuses
#============================================================================
#   Change Thread Hold Address      addis   %r4, %r3, -3                     
#============================================================================
MAKEPATCH 0x00000C60
.set FixHoldAddrDone, (PatchAddr + (9f - 0f))
0:
	ba      FixHoldAddr
9:
.endif

MAKEPATCH 0x00001E78 # vfuse
0:
	bla FixFusesAddr
9:

#============================================================================
#   Setup Fuse Row Pointer to point at Virtual Fuses                         
#   Change Increment and Range Check of Fuse Row Pointer                     
#============================================================================
MAKEPATCH 0x00001E8C # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000090A8 # vfuse
0: 
	bla FixFusesAddr
9:

MAKEPATCH 0x000090D8 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009248 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00009278 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009398 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000093C8 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009638 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00009668 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000099A8 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000099D8 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009A68 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00009A98 # vfuse
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009D68 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00009D94 # vfuse
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

#============================================================================
# devkit xex key                            
#============================================================================
MAKEPATCH 0x000000F0
0:
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
9:

# This is the memory protection patch. TODO we have to replace this with
# Grim's memory protection patch that doesn't need toggling for xefu
MAKEPATCH 0x000011BC
0:
	ba 0x154c
9:

MAKEPATCH 0x0000154C
0:
	li %r4, 7
	andc %r1, %r1, %r4
	mtspr 0x3b5, %r1
	ba 0x11c0
9:

#============================================================================
#   disable LDV check                                                        
#============================================================================
MAKEPATCH 0x00002BE4
0:
	nop
9:

#============================================================================
# disable hvxblowfuses                                                       
#============================================================================
MAKEPATCH 0x00009E58
0:
	li %r3, 1
	blr 
9:

#============================================================================
# HvxLoadImageData - ignores return of SHA memdiff (for devkit xex)          
#============================================================================
MAKEPATCH 0x0002A26C
0:
	nop 
	nop 
9:

#============================================================================
# HvxResolveImports - removes min version check in hv  (0xC0000059)           
# 00004980 blt     cr6, version_mismatch                                      
# 0000498C blt     cr6, version_mismatch                                      
#============================================================================
MAKEPATCH 0x0002A9E0
0:
	nop 
9:

MAKEPATCH 0x0002A9EC
0:
	nop 
9:

MAKEPATCH 0x0000ADEC

.set HvFlagFixer, PatchAddr
.set FixFusesAddr, (PatchAddr + (1f - 0f))

.ifdef jtag_vfuses
	.set FixHoldAddr, (PatchAddr + (2f - 0f))
.endif

.set PrintChar, (PatchAddr + (3f - 0f))
.set Syscall_0_Backdoor, (PatchAddr + (5f - 0f))

.set RealHvxGetVersions, 0x00001E30
.set HvpMemCpy,				0x0000A180

0:
	mflr    %r8											# 0xADEC
	lhz     %r3, 6(0)									# 0xADF0
	li      %r4, 0x21									# 0xADF4
	andc    %r3, %r3, %r4									# 0xADF8
	sth     %r3, 6(0)									# 0xADFC
	bla     0x68c    # HvpGetFlashBase					# 0xAE00
	lwz     %r4, 0x64(%r3)								# 0xAE04
	lwz     %r5, 0x70(%r3)								# 0xAE08
	add     %r3, %r3, %r4									# 0xAE0C
	add     %r4, %r3, %r5									# 0xAE10
	lis     %r3, 1										# 0xAE14
	addi    %r3, %r3, -0x60								# 0xAE18
	li      %r5, 0xc										# 0xAE1C
	bla     0x484    # CopyBy64							# 0xAE20
	li      %r3, 0x21									# 0xAE24
	bla     0xAE48										# 0xAE28
	li      %r3, 0xA										# 0xAE2C
	bla     0xAE48										# 0xAE30
	mtlr    %r8											# 0xAE34
	ba      0x2d8    # resume init sequence				# 0xAE38

# FixFusesAddr
1:
	lis     %r3, 1										# 0xAE3C
	addi    %r3, %r3, -0x60								# 0xAE40
	blr													# 0xAE44

.ifdef jtag_vfuses
2:
	lis     %r4, 0x8000
	rldicr  %r4, %r4, 32, 31
	oris    %r4, %r4, 0x100
	ori     %r4, %r4, 0x3080 	# 0x80000000_01003080 - had to patch freeboot.bin
	ba      FixHoldAddrDone
.endif

# PrintChar
3:
	lis     %r4, -0x8000									# 0xAE48
	ori     %r4, %r4, 0x200								# 0xAE4C
	sldi    %r4, %r4, 0x20								# 0xAE50
	oris    %r4, %r4, 0xEA00								# 0xAE54
	slwi    %r3, %r3, 0x18								# 0xAE58
	stw     %r3, 0x1014(%r4)								# 0xAE5C

uartwaitloop:		
	lwz     %r3, 0x1018(%r4)								# 0xAE60
	rlwinm. %r3, %r3, 0, 6, 6								# 0xAE64
	beq uartwaitloop									# 0xAE68
	blr													# 0xAE6C

# The syscall 0 backdoor
5:
	lis     %r11, 0x7262									# 0xAE70
	ori     %r11, %r11, 0x7472							# 0xAE74
	cmplw   cr6, %r3, %r11								# 0xAE78
	beq     cr6, checkOpType	# 0xAE7C
	ba      RealHvxGetVersions

checkOpType:
	cmplwi  cr6, %r4, 4									# 0xAE84
	bgt cr6, doMemCpy
	beq cr6, hvxExecuteCode 
	li      %r5, 0x154c  # Hv_setmemprot					# 0xAE90
	lis     %r6, 0x3880									# 0xAE94
	cmplwi  cr6, %r4, 2									# 0xAE98
	bne cr6, checkforMemProtectOn
	ori     %r6, %r6, 7									# 0xAEA0
	b setMemProtections

checkforMemProtectOn:
	cmplwi  cr6, %r4, 3									# 0xAEA8
	bne cr6, returnOne

setMemProtections:
	li      %r0, 0										# 0xAEB0
	stw     %r6, 0(%r5)									# 0xAEB4
	dcbst   0, %r5										# 0xAEB8
	icbi    0, %r5										# 0xAEBC
	sync												# 0xAEC0
	isync												# 0xAEC4

returnOne:
	li      %r3, 1										# 0xAEC8
	blr													# 0xAECC

hvxExecuteCode:
	mflr    %r12											# 0xAED0
	std     %r12, -8(%r1)									# 0xAED4
	stdu    %r1, -0x10(%r1)								# 0xAED8
	mtlr    %r5											# 0xAEDC
	mtctr   %r7											# 0xAEE0

cpyLoop:
	lwz     %r4, 0(%r6)									# 0xAEE4
	stw     %r4, 0(%r5)									# 0xAEE8
	dcbst   0, %r5										# 0xAEEC
	icbi    0, %r5										# 0xAEF0
	sync												# 0xAEF4
	isync												# 0xAEF8
	addi    %r5, %r5, 4									# 0xAEFC
	addi    %r6, %r6, 4									# 0xAF00
	bdnz cpyLoop										# 0xAF04
	blr													# 0xAF08
	addi    %r1, %r1, 0x10								# 0xAF0C
	ld      %r12, -8(%r1)									# 0xAF10
	mtlr    %r12											# 0xAF14
	blr													# 0xAF18

doMemCpy:
	cmplwi  cr6, %r4, 5									# 0xAF1C
	bne cr6, returnTwo
	mr      %r3, %r6										# 0xAF24
	mr      %r4, %r5										# 0xAF28
	mr      %r5, %r7										# 0xAF2C
	ba      HvpMemCpy    # HV_memcpy						# 0xAF30
					
returnTwo:					
	li      %r3, 2										# 0xAF34
	blr													# 0xAF38
9:

MAKEPATCH 0x00015B70 # syscall 0
0:
	.long Syscall_0_Backdoor
9:

#============================================================================
# HvxSecuritySetDetected                                                    
#============================================================================
MAKEPATCH 0x00006578
0:
	li %r3, 0
	blr 
9:

#============================================================================
# HvxSecurityGetDetected                                                     
#============================================================================
MAKEPATCH 0x00006608
0:
	li %r3, 0
	blr 
9:

#============================================================================
# HvxSecuritySetActivated                                                    
#============================================================================
MAKEPATCH 0x00006650 # HvxSecuritySetActivated
0:
	li %r3, 0
	blr 
9:

#============================================================================
# HvxSecurityGetActivated                                                    
#============================================================================
MAKEPATCH 0x000066B8 # HvxSecurityGetActivated
0:
	li %r3, 0
	blr 
9:

#============================================================================
# XeKeysSecuritySetStat    HvxSecuritySetStat                                
#============================================================================
MAKEPATCH 0x00006700
0:
	li %r3, 0
	blr 
9:

#============================================================================
# don't limit what keys can be gotton from hv         search 0x1150010       
#============================================================================
MAKEPATCH 0x00007A6C #  HvxKeysRsaPrvCrypt
0:
	MAKEBRANCH 0x7a9c
9:

#============================================================================
#   disable CBA sig validation                                               
#============================================================================
MAKEPATCH 0x00006A64
0:
	li %r3, 1
9: 

MAKEPATCH 0x00006B94
0:
	nop
9:

#============================================================================
#   disable CBB hash memcmp                                                  
#============================================================================
MAKEPATCH 0x00006C10
0:
	li %r3, 0
9:

#============================================================================
#   disable machine check on bConsoleType                                    
#============================================================================
MAKEPATCH 0x00006C5C
0:
	nop
9:

#============================================================================
#   disable machine check on bConsoleSequence                                
#============================================================================
MAKEPATCH 0x00006C6C
0:
	nop
9:

#============================================================================
#   disable machine check on wConsoleSequenceAllow, force console to detect as retail                          
#============================================================================
MAKEPATCH 0x00006C94
0:
	nop 
	li %r11, 1
9:

#============================================================================
# locked memcmp Run GOD Content   
# HvpCompareXGD2MediaID                                           
#============================================================================
MAKEPATCH 0x00024CB8 
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#;   00026450 bla       HvpPkcs1Verify - disable fcrt signature check
# HvpDvdDecryptFcrt        
#;============================================================================
MAKEPATCH 0x00026450
0:
	li %r3, 1
9:

#============================================================================
# Patch signature check and load as retail if invalid (Ant)                  
#============================================================================
MAKEPATCH 0x00029A68
.set HvCryptAesKey, 0x200F8
0:
	# Check if AES Ctx is NULL
	cmpldi  cr6, %r28, 0		# first instruction after sig check
	beq     cr6, xex_ret_zero

	# Check to see if signature was valid
	cmpwi   cr6, %r3, 0
	bne     cr6, xex_proc_key

	# Devkit signature invalid so load as retail
	li      %r4, 0xF0
	b       xex_setkey
	nop
xex_proc_key:
	cmplwi	cr6, %r29, 0
	addi	%r4, %r31, 0x440
	bne		cr6, xex_setkey
	li		%r4, 0x54   # pbKey
xex_setkey:
	mr		%r3, %r28       # pAesState
	MAKEBRANCHL HvCryptAesKey
xex_ret_zero:
	li		%r31, 0			# original instruction, make sure this lines up
9:

#============================================================================
# HvxImageTransformImageKey remove type check                              
#============================================================================
MAKEPATCH 0x0002B6D0 # HvxImageTransformImageKey
0:
	nop 
9:

#============================================================================
# needed when patching out revoke Check from xex image header in xam     
# HvxCreateImageMapping 0xC8003004                                           
#============================================================================
MAKEPATCH 0x0002BFE8 # HvxCreateImageMapping
0:
	li %r3, 0
9:

#============================================================================
# HvxCreateImageMapping - Remove XEX Region Check 0xC0050001                 
#============================================================================
MAKEPATCH 0x0002C280 # HvxCreateImageMapping
0:
	nop 
9:

#============================================================================
# HvxExpansionInstall - if sig check fails pass it anyway, but don't use cpukey crypto
#============================================================================
MAKEPATCH 0x0003089C
0:
    bne       cr6, signedExp        # beq       cr6, return_C8007003
    li        %r29, 0                # lwz       r11, 8(r31)
signedExp:
    nop                            # cmplw     cr6, r11, r28
    nop                            # bgt       cr6, return_C8007003
9:

#============================================================================
# HvxExpansionInstall do_expansion_install check                             
#============================================================================
MAKEPATCH 0x000304E8 # HvpInstallExpansion
0:
	nop 
9:

#============================================================================
# HvxExpansionInstall do_expansion_install check                             
#============================================================================
MAKEPATCH 0x000304FC # HvpInstallExpansion
0:
	nop 
9:

# Kernel patches from here on

#============================================================================
# XexpConvertError - converts revoke all errors into OK                      
#============================================================================
KMAKEPATCH 0x8007AC80
0:
	li %r3, 0
	blr 
9:

#============================================================================
# XexpLoadXexHeaders/XexpVerifyMediaType - Disable Media Flags Check         
#============================================================================
KMAKEPATCH 0x8007B818
0:
	li %r3, 1
9:

#============================================================================
# XexpLoadFile - skip 0xC00000CC (BAD_NETWORK_NAME) error                    
# bl        RtlImageXexHeaderString                                          
#============================================================================
KMAKEPATCH 0x8007b928
0:
	li %r3, 0
9:

#============================================================================
# XexpLoadFile - skip 0xC000008B (resource not found) error                  
# lwz     %r11, 0x4C(%r25) # 0x40000000 bound path flag                      
#============================================================================
KMAKEPATCH 0x8007B990
0:
	li %r11, 0
9:

#============================================================================
# XexpLoadFile - skip 0xC000008B (resource not found) error                  
# lwz     %r11, 0x4C(%r25) # 0x20000000 bound device flag                    
#============================================================================
KMAKEPATCH 0x8007B9E0
0:
	li %r11, 0
9:

#============================================================================
# XexpLoadXexHeaders - 0xC0000059 revision mismatch                          
#============================================================================
KMAKEPATCH 0x8007C850
0:
	li %r3, 0
9:

#============================================================================
# fix sfcxmu corruption issues on jasper bigblock - use 008 or higher for retail
# SfcxInspectLargeDataBlock 80091C28 lbz %r23, 7(%r30) # r23 = kernelresv blocks
#============================================================================
KMAKEPATCH 0x80093FD8
0:
	li %r23, 0x10
9:

#============================================================================
# SataCdRomAuthenticationExInitialize - disables AuthEx/AP25 on supp. drives 
#============================================================================
KMAKEPATCH 0x800988F8
0:
	cmplwi cr6, %r11, 0xff
9:

#============================================================================
# prevent E66 with XGD3 on some drives                                       
#============================================================================
KMAKEPATCH 0x800982DC
0:
	li %r3, 0
	nop 
	nop 
	nop 
	nop 
9:

#============================================================================
# XeKeysVerifyRSASignature Disable PIRS/LIVE Signature Check                 
#============================================================================
KMAKEPATCH 0x80109A80
0:
	li %r3, 1
	blr 
9:

#============================================================================
# XeKeysSecurityConvertError										          
#============================================================================
KMAKEPATCH 0x8010A578
0:
	li %r3, 0
	blr 
9:

#============================================================================
# XeKeysDvdAuthExConvertError										          
#============================================================================
KMAKEPATCH 0x8010A858
0:
	li %r3, 0
	blr 
9:

#============================================================================
# _XeKeysRevokeIsValid                                                       
#============================================================================
KMAKEPATCH 0x8010AD20
0:
	li %r3, 1
	blr 
9:

#============================================================================
# _XeKeysRevokeIsRevoked (for dynamicUpdate)      **1**                      
#============================================================================
KMAKEPATCH 0x8010AED8
0:
	li %r3, 0
	blr 
9:

#============================================================================
#  XeKeysRevokeIsRevoked                                                     
#============================================================================
KMAKEPATCH 0x8010AF28
0:
	li %r3, 0
	blr 
9:

#============================================================================
# XeKeysRevokeIsDeviceRevoked - usb device revocation (natal needs)          
#============================================================================
KMAKEPATCH 0x8010B068
0:
	li %r3, 0
	blr 
9:

#============================================================================
# XeKeysRevokeConvertError - converts revoke all errors into OK              
#============================================================================
KMAKEPATCH 0x8010B1E8
0:
	li %r3, 0
	blr 
9:

#============================================================================
# mid XeKeysConsoleSignatureVerification - skip sig check           
#============================================================================
KMAKEPATCH 0x8010BD60
.set csig_return, 0x8010BD88
0:
	li 		%r3, 1
	KMAKEBRANCH csig_return
9:

#============================================================================
# XeCryptBnQwBeSigVerify needed for LIVE/PIRS execution                      
#============================================================================
KMAKEPATCH 0x801106B0
0:
	li %r3, 1
	blr 
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice
#
# Regular FreeBoot would have done the following at 0x00156D70
#     li %r3, 1
#     blr
#
# However, that breaks compat with FATXPlorer formatted drives with a SS and
# "extra space"... this patch does full auth for retail for such drives but
# still allows generic drives by patching the error path to return TRUE
#
# Note: XeKeysVerifyRSASignature at 0x80106DF0 is used here to verify the
# security sector, it's patched out so we don't need to do anything else
#============================================================================

#============================================================================
# Rather than calling VdDisplayFatalError to display an E69 (hehehehe),
# jump to the error handler in SataDiskAuthenticateDevice
#============================================================================
KMAKEPATCH 0x80156DB0
0:
   KMAKEBRANCH 0x80156EA0
9:

#============================================================================
# Patch error handler in SataDiskAuthenticateDevice to return TRUE instead
# of FALSE
#============================================================================
KMAKEPATCH 0x80156EA0
0:
   li %r3, 1
9:

# The standard XeBuild patch for 15574 puts this in spare space inside SataDiskAuthenticateDevice
# Since we don't patch out SataDiskAuthenticateDevice fully anymore, this is moved to waste space
# after XeCryptBnQwBeSigVerify... hopefully that's fine

KMAKEPATCH 0x801106B8
.set HookDest, PatchAddr
.set XexLoadImage, (0x8007CA60-KBASE) 	# XexLoadImage
.set XamLoadedHook, (0x8006138C-KBASE) 	# Phase1Initialization
.set HookFileName, (RealAddr+(1f-0f))
0:
	bge     loadmod            		# once xam loads successfully,
									# try and start another module from hdd
	blr                             # if xam fails to load, then let the
									# normal process of recording argon
									# error and showing E7x screen commence

loadmod:
	lis     %r3, HookFileName@h
	lis     %r5, 0x0                # minver
	li      %r4, 0x0
	ori     %r4, %r4, 8             # mod flag
	ori    	%r3, %r3, HookFileName@l    # address of path to xex dll
	li      %r6, 0
	MAKEBRANCHL XexLoadImage
	li		%r3, 0					# just in case!
	MAKEBRANCH (XamLoadedHook+0x10)
1:
	.string "\\Device\\Flash\\launch.xex"
	.byte 0
	.align 2
9:

#============================================================================
# the instruction following xam loading in phase1init (mr %r31, %r3)         
#============================================================================
MAKEPATCH XamLoadedHook	# NOTE this one is not kpatch
0:
	MAKEBRANCHL HookDest
9:


.long 0xffffffff
