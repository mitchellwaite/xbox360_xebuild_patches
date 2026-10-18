.include "macros.S"


MAKEPATCH 0x0000189C # init
0:
	bla HvFlagFixer
9:

MAKEPATCH 0x00001E68 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00001E7C # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00008A80 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00008AB0 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00008BF0 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00008C20 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00008D10 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00008D40 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00008F80 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00008FB0 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x000090D0 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00009100 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009190 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000091BC # vfuse
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00009430 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x0000945C # vfuse
0:
	addi %r11, %r11, 1
	sldi %r9, %r9, 3
	cmpwi cr6, %r11, 0xc
9:

#============================================================================
# pbkey xex2key ensure all zeroes                                            
#============================================================================
MAKEPATCH 0x000000F0 # devkit xex key
0:
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
9:

# Memory protection patch
# TODO replace this!
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

#;============================================================================
#;   disable LDV check                                                        
#;============================================================================
MAKEPATCH 0x00002B04 # machine check
0:
	nop
9:

MAKEPATCH 0x00009520 # HvxLockL2 
0:
	li %r3, 1
	blr
9:

#============================================================================
# HvxLoadImageData - ignores return of SHA memdiff (for devkit xex)
#============================================================================
MAKEPATCH 0x0002A14C # HvxLoadImageData
0:
	nop 
	nop 
9:

#============================================================================
# HvxResolveImports - removes min version check in hv  (0xC0000059)           
# 00004980 blt     cr6, version_mismatch                                      
# 0000498C blt     cr6, version_mismatch                                      
#============================================================================
MAKEPATCH 0x0002A8C0 # HvxResolveImports
0:
	nop 
9:

MAKEPATCH 0x0002A8CC # HvxResolveImports
0:
	nop 
9:

.set HvpGetFlashBase,0x68C	
.set CopyBy64,0x484
.set resumeInit,0x2D8
.set RealHvxGetVersions,0x1E20
.set Hv_setmemprot,0x154C
.set HV_memcpy,0x9820

MAKEPATCH 0x0000A474
.set HvFlagFixer, PatchAddr
.set FixFusesAddr, (PatchAddr + (1f - 0f))

.ifdef jtag_vfuses
	.set FixHoldAddr, (PatchAddr + (2f - 0f))
.endif

.set PrintChar, (PatchAddr + (3f - 0f))
.set Syscall0_Backdoor, (PatchAddr + (5f - 0f))
0:
   # HvFlagFixer
	mflr %r8

	# Clear flags
	lhz %r3, 6(%r0) 								
	li %r4, 0x21									
	andc %r3, %r3, %r4 							
	sth %r3, 6(%r0) 								

	bla HvpGetFlashBase					

# JTAGs always store their vfuses at 0x95000
.ifdef jtag_vfuses
   oris %r4, %r3, 9
   ori %r4, %r4, 0x5000
.else
	lwz %r4, 0x64(%r3) 							
	lwz %r5, 0x70(%r3) 							
	add %r3, %r3, %r4 								
	add %r4, %r3, %r5 								
.endif

	# copy the vfuses
	lis %r3, 1 									
	addi %r3, %r3, -0x60					
	li %r5, 0xc 									
	bla CopyBy64

	li %r3, '!'									
	bla PrintChar 		 							
	li %r3, '\n'								
	bla PrintChar								
	mtlr %r8

	# We patched a bl to a function, branch to that function now					
	ba resumeInit

# FixFusesAddr
1:
	lis %r3, 1 									
	addi %r3, %r3, -0x60					
	blr 										

.ifdef jtag_vfuses
2:
	lis     %r4, 0x8000
	rldicr  %r4, %r4, 32, 31
	oris    %r4, %r4, 0x100
	ori     %r4, %r4, 0x3080 	#; 0x80000000_01003080 - had to patch freeboot.bin
	ba      FixHoldAddrDone
.endif

# PrintChar		
3:	
	lis %r4, -0x8000 							
	ori %r4, %r4, 0x200 							
	sldi %r4, %r4, 0x20 							
	oris %r4, %r4, 0xea00 						
	slwi %r3, %r3, 0x18 							
	stw %r3, 0x1014(%r4) 							
uartwaitloop:
	lwz %r3, 0x1018(%r4) 							
	rlwinm. %r3, %r3, 0, 6, 6 					
	beq uartwaitloop						
	blr 										

# The famous syscall 0 backdoor
5:
	lis %r11, 0x7262 							
	ori %r11, %r11, 0x7472 						
	cmplw cr6, %r3, %r11 							
	beq cr6, checkOpType			
	ba RealHvxGetVersions		
			
checkOpType: 									
	cmplwi cr6, %r4, 4 							
	bgt cr6, doMemCpy				
	beq cr6, hvxExecuteCode 			
	li %r5, Hv_setmemprot 			
	lis %r6, 0x3880

	cmplwi cr6, %r4, 2 							
	bne cr6, checkforMemProtectOn		
	ori %r6, %r6, 7 								
	b setMemProtections		
			
checkforMemProtectOn: 							
	cmplwi cr6, %r4, 3 							
	bne cr6, returnOne 			
			
setMemProtections: 							
	li %r0, 0 									
	stw %r6, 0(%r5) 								
	dcbst 0, %r5 								
	icbi 0, %r5 									
	sync  										
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

#============================================================================
# patch syscall 0 to jump to hook  
#============================================================================
MAKEPATCH 0x00015980
0:
	.long Syscall0_Backdoor
9:

#;============================================================================
#; HvxSecuritySetDetected                                                     
#;============================================================================
MAKEPATCH 0x00006250
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; HvxSecurityGetDetected                                                     
#;============================================================================
MAKEPATCH 0x000062E0
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; HvxSecuritySetActivated                                                    
#;============================================================================
MAKEPATCH 0x00006328
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; HvxSecurityGetActivated                                                    
#;============================================================================
MAKEPATCH 0x00006390
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XeKeysSecuritySetStat                                                      
#;============================================================================
MAKEPATCH 0x000063D8 
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; don't limit what keys can be gotton from hv         search 0x1150010       
#;============================================================================
MAKEPATCH 0x00007650 #  HvxKeysRsaPrvCrypt
0:
	MAKEBRANCH 0x7680
9:

MAKEPATCH 0x000066C8 # CB check
0:
	li %r3, 1
9:

#;============================================================================
#;   disable CBA sig validation                                               
#;============================================================================
MAKEPATCH 0x000066D0
0:
	nop 
9:

#;============================================================================
#;   disable CBB hash memcmp                                                  
#;============================================================================
MAKEPATCH 0x00006884
0:
	li %r3, 0
9:

#============================================================================
#   disable machine check on bConsoleType                                    
#============================================================================
MAKEPATCH 0x000068D0 # machinecheck
0:
	nop
9:

#============================================================================
#   disable machine check on bConsoleSequence                                
#============================================================================
MAKEPATCH 0x000068E0
0:
	nop
9:

#============================================================================
#   disable machine check on wConsoleSequenceAllow, force console to detect as retail                          
#============================================================================
MAKEPATCH 0x00006904
0:
	nop 
	li %r11, 1
9:	

#;============================================================================
#; locked memcmp Run GOD Content                                              
#;============================================================================
MAKEPATCH 0x00024B98 # HvpCompareXGD2MediaID
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#; Patch signature check and load as retail if invalid (Ant)
#;============================================================================
MAKEPATCH 0x00029948
	.set HvCryptAesKey, 0x200F8
0:
	#; Check if AES Ctx is NULL
	cmpldi  cr6, %r28, 0		#; first instruction after sig check
	beq     cr6, xex_ret_zero

	#; Check to see if signature was valid
	cmpwi   cr6, %r3, 0
	bne     cr6, xex_proc_key

	#; Devkit signature invalid so load as retail
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
	li		%r31, 0			#; original instruction, make sure this lines up
9:

#;============================================================================
#; needed when patching out Revocation Check from xex image header in xam     
#; HvxCreateImageMapping 0xC8003004                                           
#;============================================================================
MAKEPATCH 0x0002BE20
0:
	li %r3, 0
9:

#;============================================================================
#; HvxCreateImageMapping - Remove XEX Region Check                            
#;============================================================================
MAKEPATCH 0x0002C0B8  # HvxCreateImageMapping
0:
	nop 
9:

#;============================================================================
#; HvxExpansionInstall - if sig check fails pass it anyway, but don't use cpukey crypto
#;============================================================================
MAKEPATCH 0x0003089C # HvxInstallExpansion
0:
	bne cr6, signedExp
	li %r29, 0
signedExp:
	nop 
	nop 
9:

#;============================================================================
#; HvxExpansionInstall do_expansion_install check                             
#;============================================================================
MAKEPATCH 0x000304E8 # HvpInstallExpansion
0:
	nop 
9:

#;============================================================================
#; HvxExpansionInstall do_expansion_install check                             
#;============================================================================
MAKEPATCH 0x000304FC # HvpInstallExpansion
0:
	nop 
9:

# kernel patches

#;============================================================================
#; XexpConvertError - converts revoke all errors into OK              
#;============================================================================
KMAKEPATCH 0x8007AC80
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XexpLoadXexHeaders - disable min version check, Disable Media Flags Check  
#;============================================================================
KMAKEPATCH 0x8007B818 # XexpLoadXexHeaders
0:
	li %r3, 1
9:

#============================================================================
# XexpLoadFile - skip 0xC00000CC (BAD_NETWORK_NAME) error                    
# bl        RtlImageXexHeaderString                                          
#============================================================================
KMAKEPATCH 0x8007B928
0:
	li %r3, 0
9:

#;============================================================================
#; XexpLoadFile - skip 0xC000008B (resource not found) error                  
#; lwz     %r11, 0x4C(%r25) # 0x40000000 bound path flag                      
#;============================================================================
KMAKEPATCH 0x8007B990
0:
	li %r11, 0
9:

#;============================================================================
#; XexpLoadFile - skip 0xC000008B (resource not found) error                  
#; lwz     %r11, 0x4C(%r25) # 0x20000000 bound device flag                    
#;============================================================================
KMAKEPATCH 0x8007B9E0 # XexpLoadFile
0:
	li %r11, 0
9:

#;============================================================================
#; XexpLoadXexHeaders - 0xC0000059 revision mismatch                          
#;============================================================================
KMAKEPATCH 0x8007C850
0:
	li %r3, 0
9:

#;============================================================================
#; fix sfcxmu corruption issues on jasper bigblock - use 008 or higher for retail
#; SfcxInspectLargeDataBlock 80091C28 lbz %r23, 7(%r30) #; r23 = kernelresv blocks
#;============================================================================
KMAKEPATCH 0x80093F28 # SfcxInspectLargeDataBlock
0:
	li %r23, 0x10
9:

#;============================================================================
#; SataCdRomAuthenticationExInitialize - disables AuthEx/AP25 on supp. drives 
#;============================================================================
KMAKEPATCH 0x800987E0 # SataCdRomAP25Initialize
0:
	cmplwi cr6, %r11, 0xff
9:

#;============================================================================
#; prevent E66 with XGD3 on some drives                                       
#;============================================================================
KMAKEPATCH 0x800981C4
0:
	li %r3, 0
	nop 
	nop 
	nop 
	nop 
9:

#;============================================================================
#; XeKeysVerifyRSASignature Disable PIRS/LIVE Signature Check                 
#;============================================================================
KMAKEPATCH 0x80106DF0
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#; XeKeysSecurityConvertError										          
#;============================================================================
KMAKEPATCH 0x801078E8
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XeKeysDvdAuthExConvertError										          
#;============================================================================
KMAKEPATCH 0x80107BC8
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; _XeKeysRevokeIsValid                                                       
#;============================================================================
KMAKEPATCH 0x80108090
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#; _XeKeysRevokeIsRevoked (for dynamicUpdate)      **1**                      
#;============================================================================
KMAKEPATCH 0x80108248
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#;  XeKeysRevokeIsRevoked                                                     
#;============================================================================
KMAKEPATCH 0x80108298
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XeKeysRevokeIsDeviceRevoked - usb device revocation (natal needs)          
#;============================================================================
KMAKEPATCH 0x801083D8
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XeKeysRevokeConvertError - converts revoke all errors into OK              
#;============================================================================
KMAKEPATCH 0x80108558
0:
	li %r3, 0
	blr 
9:

#;============================================================================
#; XeCryptBnQwBeSigVerify needed for LIVE/PIRS execution                      
#;============================================================================
KMAKEPATCH 0x8010D980
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#; mid XeKeysConsoleSignatureVerification - skip sig check                    
#;============================================================================
KMAKEPATCH 0x80109040
0:
	li %r3, 1
	KMAKEBRANCH 0x80109068
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice
#
# Regular FreeBoot would have done the following at 0x8014B160
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
KMAKEPATCH 0x8014B1A0
0:
   KMAKEBRANCH 0x8014B290
9:

#============================================================================
# Patch error handler in SataDiskAuthenticateDevice to return TRUE instead
# of FALSE
#============================================================================
KMAKEPATCH 0x8014B290
0:
   li %r3, 1
9:

#;============================================================================
#; start launch.xex if present                                                
#;============================================================================
KMAKEPATCH 0x8014EE00
	.set HookDest, PatchAddr
	.set XexLoadImage, (0x8007CA60-KBASE) 	#; XexLoadImage
	.set XamLoadedHook, (0x80061388-KBASE) 	#; Phase1Initialization
	.set HookFileName, (RealAddr+(1f-0f))
0:
	mr      %r30, %r3               #; instruction replaced to get here,
									#; the load result of xam moved from %r3
	cmpwi   cr6, %r30, 0
	blt     cr6, xamfailed
	beq     cr6, loadmod            #; once xam loads successfully,
									#; try and start another module from hdd

xamfailed:
	blr                             #; if xam fails to load, then let the
									#; normal process of recording argon
									#; error and showing E7x screen commence
loadmod:
	lis     %r3, HookFileName@h
	lis     %r5, 0x0                #; minver
	li      %r4, 0x0
	ori     %r4, %r4, 8             #; mod flag
	ori    	%r3, %r3, HookFileName@l    #; address of path to xex dll
	li      %r6, 0
	MAKEBRANCHL XexLoadImage
	li		%r30, 0					#; just in case!
	MAKEBRANCH (XamLoadedHook+4)
1:
	#;.string "\\Device\\Harddisk0\\Partition1\\launch.xex"
	.string "\\Device\\Flash\\launch.xex"
	.byte 0
	.align 2
9:

#;============================================================================
#; the instruction following xam loading in phase1init (mr %r31, %r3)         
#;============================================================================
MAKEPATCH XamLoadedHook	#; NOTE this one is not kpatch
0:
	MAKEBRANCHL HookDest
9:

.long 0xffffffff
