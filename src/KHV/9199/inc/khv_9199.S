# Fuck if I know if this is accurate :)

.include "macros.S"

# ============================================================================
#	Branch to HV flag fix function
# ============================================================================
MAKEPATCH 0x000019A0 # init hook
.set HvFlagFixerDone, (PatchAddr + (9f - 0f))
0:
	bla HvFlagFixer
9:

.ifdef jtag_vfuses
# ============================================================================
# For JTAGs only, we need to patch HvxStartupProcessors
#
# The following patch replaces (addis %r4, %r3, -3) with a branch to our custom
# function, the custom function will then branch back to the instruction
# after what we replaced
# ============================================================================
MAKEPATCH 0x00001C0C
.set FixHoldAddrDone, (PatchAddr + (9f - 0f))
0:
		ba      FixHoldAddr
9:
.endif

# ============================================================================
#   Setup Fuse Row Pointer to point at Virtual Fuses (ikari)
# ============================================================================
MAKEPATCH 0x00002078 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00006BE0 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00006D50 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00006E70 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000070E0 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x00007230 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x000072F0 # vfuse
0:
	bla FixFusesAddr
9:

MAKEPATCH 0x0007590 # vfuse
0:
	bla FixFusesAddr
9:

# ============================================================================
#   Change Increment and Range Check of Fuse Row Pointer (ikari)
# ============================================================================
MAKEPATCH 0x0000208C # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00006C10 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00006D80 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00006EA0 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00007110 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x00007260 # vfuse
0:
	addi %r11, %r11, 1
	cmplwi cr6, %r11, 0xc
9:

MAKEPATCH 0x0000731C # vfuse
0:							
	addi %r11, %r11, 1		
	sldi %r9, %r9, 3			
	cmpwi cr6, %r11, 0xc		
9:							

MAKEPATCH 0x000075BC # vfuse
0:
	addi %r11, %r11, 1	
	sldi %r9, %r9, 3		
	cmpwi cr6, %r11, 0xc	
9:


MAKEPATCH 0x000000F0 # devkit Xex Key
0:
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
	.long 0x00000000
9:

MAKEPATCH 0x00001420 # unneccesary patch to extend the syscall table
0:
	cmplwi %r0, 0x7c
9:

# ============================================================================
#   hv tlb_rpn set command location (cOz)
# TODO: replace this with Brent or Grim's memory protection patch
# ============================================================================
MAKEPATCH 0x0000114C 
0:
	ba 0x1570
9:

MAKEPATCH 0x00001570
0:
	li %r4, 7
	andc %r1, %r1, %r4
	mtspr 0x3b5, %r1
	ba 0x1150
9:

#============================================================================
#   disable LDV check                                                        
#============================================================================
MAKEPATCH 0x00002AD8
0:
	nop
9:

#============================================================================
# Disable HvxBlowFuses                                                  
#============================================================================
MAKEPATCH 0x00007680
0:
	li %r3, 1
	blr 
9:

# ============================================================================
# HvxLoadImageData - ignores return of SHA memdiff (for devkit xex)
# ============================================================================
MAKEPATCH 0x000043B4
0:
	nop 
	nop 
9:

#============================================================================
# HvxResolveImports - removes min version check in hv  (0xC0000059)
#============================================================================
MAKEPATCH 0x00004A98 # HvxResolveImports
0:
	nop
9:

MAKEPATCH 0x00004AA4 # HvxResolveImports
0:
	nop
9:

.set HvpGetFlashBase,0x998	
.set CopyBy64,0x78C

.set RealHvxGetVersions,0x2030
.set Hv_setmemprot,0x1570
.set HV_memcpy,0xED20

MAKEPATCH 0x0000F568

.set HvFlagFixer, PatchAddr
.set FixFusesAddr, (PatchAddr + (1f - 0f))

.ifdef jtag_vfuses
	.set FixHoldAddr, (PatchAddr + (2f - 0f))
.endif

.set PrintChar, (PatchAddr + (3f - 0f))
.set HV_PP_Syscall0, (PatchAddr + (5f - 0f))

0:

	mflr %r8 							# 0xF568
	lhz %r3, 6(%r0) 							# 0xF56C 
	li %r4, 0x21							# 0xF570 	# set bitmask to 0x21 for flags (was 0x1, was conflating this with some other issue at the time)
	andc %r3, %r3, %r4 						# 0xF574
	sth %r3, 6(%r0) 	 						# 0xF578

	bla HvpGetFlashBase # 0x998					# 0xF57C

.ifdef jtag_vfuses
   oris %r4, %r3, 9
   ori %r4, %r4, 0x5000
.else
	lwz %r4, 0x64(%r3) 						# 0xF580	# reading/building vfuse addr from flash
	lwz %r5, 0x70(%r3) 						# 0xF584	# reading/building vfuse addr from flash; flash base + e0000
	add %r3, %r3, %r4 							# 0xF588 
	add %r4, %r3, %r5 							# 0xF58C
.endif

	lis %r3, 1 							# 0xF590
	addi %r3, %r3, -0x60	 					# 0xF594	
	li %r5, 0xc 							# 0xF598
	bla CopyBy64 	# 0x78C						# 0xF59C
	li %r3, '!'							# 0xF5A0 
	bla PrintChar 		 					# 0xF5A4
	li %r3, '\n'							# 0xF5A8
	bla PrintChar 							# 0xF5AC
	mtlr %r8  							# 0xF5B0	

	# TODO we don't actually do the instruction we replaced with this patch

	ba HvFlagFixerDone 	# 0x19A4 					# 0xF5B4

# FixFusesAddr
1:
	lis %r3, 1 							# 0xF5B8
	addi %r3, %r3, -0x60 						# 0xF5BC
	blr 								# 0xF5C0

.ifdef jtag_vfuses
2:
		lis     %r4, 0x8000
		rldicr  %r4, %r4, 32, 31
		oris    %r4, %r4, 0x0020
		ba      FixHoldAddrDone
.endif

# PrintChar
3:
	lis %r4, -0x8000 						# 0xF5C4 #post output
	ori %r4, %r4, 0x200 						# 0xF5C8
	sldi %r4, %r4, 0x20 						# 0xF5CC
	oris %r4, %r4, 0xea00 						# 0xF5D0
	slwi %r3, %r3, 0x18 						# 0xF5D4
	stw %r3, 0x1014(%r4) 						# 0xF5D8

waitloop:
	lwz %r3, 0x1018(%r4) 						# 0xF5DC
	rlwinm. %r3, %r3, 0, 6, 6 					# 0xF5E0
	beq waitloop 						# 0xF5E4
	blr 								# 0xF5E8

# Syscall 0 backdoor
5:	
	lis %r11, 0x7262 						# 0xF5EC # magic key
	ori %r11, %r11, 0x7472 						# 0xF5F0
	cmplw cr6, %r3, %r11 						# 0xF5F4
	beq cr6, checkOpType		# 0xF600			# 0xF5F8
	ba RealHvxGetVersions 		# 0x2030			# 0xF5FC

checkOpType: 								
	cmplwi cr6, %r4, 4 						# 0xF600
	bgt cr6, doMemCpy 	# 0xF698				# 0xF604
	beq cr6, hvxExecuteCode 	# 0xF64C				# 0xF608
	li %r5, Hv_setmemprot 	# 0x1570				# 0xF60C
	lis %r6, 0x3880 							# 0xF610
	cmplwi cr6, %r4, 2 						# 0xF614
	bne cr6, checkforMemProtectOn # 0xF624				# 0xF618
	ori %r6, %r6, 7 							# 0xF61C
	b setMemProtections   # 0xF62C				# 0xF620
	
checkforMemProtectOn: 							
	cmplwi cr6, %r4, 3 						# 0xF624
	bne cr6, returnOne 	# 0xF644				# 0xF628
	
setMemProtections: 							
	li %r0, 0 							# 0xF62C
	stw %r6, 0(%r5) 							# 0xF630
	dcbst 0, %r5 							# 0xF634
	icbi 0, %r5 							# 0xF638
	sync  								# 0xF63C
	isync  								# 0xF640

returnOne: 								
	li %r3, 1 							# 0xF644
	blr 								# 0xF648

hvxExecuteCode: 							
	mflr %r12 							# 0xF64C
	std %r12, -8(%r1) 						# 0xF650
	stdu %r1, -0x10(%r1) 						# 0xF654
	mtlr %r5 							# 0xF658
	mtctr %r7 							# 0xF65C

cpyLoop: 								
	lwz %r4, 0(%r6) 							# 0xF660
	stw %r4, 0(%r5) 							# 0xF664
	dcbst 0, %r5 							# 0xF668
	icbi 0, %r5 							# 0xF66C
	sync 								# 0xF670
	isync 								# 0xF674
	addi %r5, %r5, 4 							# 0xF678
	addi %r6, %r6, 4 							# 0xF67C
	bdnz cpyLoop	# 0xF660				# 0xF680
	blr 								# 0xF684
	addi %r1, %r1, 0x10 						# 0xF688
	ld %r12, -8(%r1) 							# 0xF68C
	mtlr %r12 							# 0xF690
	blr 								# 0xF694

doMemCpy:	 							
	cmplwi cr6, %r4, 5 						# 0xF698
	bne cr6, returnTwo 	#0xF6C0					# 0xF69C
	mr %r3, %r6 							# 0xF6A0
	mr %r4, %r5 							# 0xF6A4
	mr %r5, %r7 							# 0xF6A8
	ba HV_memcpy 	# 0xED20					# 0xF6AC

returnTwo: 								
	li %r3, 2 							# 0xF6B0
	blr 								# 0xF6B4
9:

MAKEPATCH 0x00001C98 # Replace Syscall0 with our own 
0:
	.long HV_PP_Syscall0
9:

# ============================================================================
#   HvxSecuritySetDetected (Redline99)
# ============================================================================
MAKEPATCH 0x00008DB8
0:
	li %r3, 0
	blr 
9:

# ============================================================================
#   HvxSecurityGetDetected (Redline99)
# ============================================================================
MAKEPATCH 0x00008E80
0:
	li %r3, 0
	blr 
9:

# ============================================================================
#   HvxSecuritySetActivated (Redline99)
# ============================================================================
MAKEPATCH 0x00008EC8
0:
	li %r3, 0
	blr 
9:

# ============================================================================
#   HvxSecurityGetActivated
# ============================================================================
MAKEPATCH 0x00008F70
0:
	li %r3, 0
	blr 
9:

# ============================================================================
#   XeKeysSecuritySetStat (Redline99) HvxSecuritySetStat
# ============================================================================
MAKEPATCH 0x00008FB8
0:
	blr 
9:

#============================================================================
#   disable CBA sig validation                                               
#============================================================================
MAKEPATCH 0x00009300 # CB check?
0:
	li %r3, 1
9:

#============================================================================
#   disable CBB hash memcmp                                                  
#============================================================================
MAKEPATCH 0x0000940C 
0:
    nop               
9:

#============================================================================
#   disable machine check on bConsoleType                                    
#============================================================================
MAKEPATCH 0x000094CC
0:
    nop
9:


MAKEPATCH 0x000094C0 # CD check?
0:
	li %r3, 0
9:

#============================================================================
#   disable machine check on bConsoleType                                    
#============================================================================
MAKEPATCH 0x0000950C
0:
	nop 
9:

#============================================================================
#   disable machine check on bConsoleSequence                                
#============================================================================
MAKEPATCH 0x0000951C
0:
	nop 
9:

#============================================================================
#   disable machine check on wConsoleSequenceAllow, force console to detect as retail                          
#============================================================================
MAKEPATCH 0x00009544
0:
	nop 
	li %r11, 1
9:

#;============================================================================
#; don't limit what keys can be gotton from hv
#;============================================================================
MAKEPATCH 0x0000A078 # HvxKeysRsaPrvCrypt
0:
	MAKEBRANCH 0xa0a8
9:

# ============================================================================
#   Run GOD Content
# HvpCompareXGD2MediaID
# ============================================================================
MAKEPATCH 0x0000A260
0:
	li %r3, 1
	blr 
9:

#;============================================================================
#; HvxExpansionInstall - pass mfg sig check                                   
#;============================================================================
MAKEPATCH 0x0000EAA8 # HvxInstallExpansion
0:
	li %r3, 1
9:

#============================================================================
#   HvxImageTransformImageKey remove type check                              
#============================================================================
MAKEPATCH 0x000055E8
0:
	nop
9:	

# ============================================================================
#   Allow Unsigned XEX Execution (ikari)
# ============================================================================
.set HvCryptAesKey, 0xF3D0

MAKEPATCH 0x000034D0
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
	MAKEBRANCHL HvCryptAesKey

xex_ret_zero:
	li %r31, 0
9:

#;============================================================================
#; needed when patching out Revocation Check from xex image header in xam     
#; HvxCreateImageMapping 0xC8003004                                           
#;============================================================================
MAKEPATCH 0x000037B0 # HvxCreateImageMapping
0:
	li %r3, 0
9:

# ============================================================================
#   HvxCreateImageMapping - Remove XEX Region Check (cOz)
# ============================================================================
MAKEPATCH 0x00003A48 # HvxCreateImageMapping
0:
	nop 
9:


# Kernel Patches

# ============================================================================
#   Disable Media Flags Check 0x800785e4
# ============================================================================
KMAKEPATCH 0x800785E4 # XexpLoadXexHeaders 
0:
	b 0x10
9:

# ============================================================================
#   XexpLoadXexHeaders - disable min version check 0x800785E8
# ============================================================================
KMAKEPATCH 0x800785E8 # XexpLoadXexHeaders
0:
	nop 
	nop 
	nop 
9:

# ============================================================================
#   Disable PIRS/LIVE Signature Check (ikari)
# ============================================================================
KMAKEPATCH 0x800F6118 # XeKeysVerifyRSASignature 
0:
	li %r3, 1
	blr 
9:

# ============================================================================
#   _XeKeysRevokeIsValid 0x800f70c0
# ============================================================================
KMAKEPATCH 0x800F70C0 # _XeKeysRevokeIsValid 
0:
	li %r3, 1
	blr 
9:

# ============================================================================
#   _XeKeysRevokeIsRevoked (for dynamicUpdate) 0x800F7160
# ============================================================================
KMAKEPATCH 0x800F7160 # _XeKeysRevokeIsRevoked
0:
	li %r3, 1
	blr 
9:

# ============================================================================
#   XeKeysRevokeIsRevoked 0x800f7230
# ============================================================================
KMAKEPATCH 0x800F7230 # XeKeysRevokeIsRevoked
0:
	li %r3, 0
	blr 
9:

# ============================================================================
# XeKeysRevokeConvertError - converts revoke all errors into OK 0x800F72A8
# ============================================================================
KMAKEPATCH 0x800F72A8 # XeKeysRevokeConvertError
0:
	li %r3, 0
	blr 
9:

# ============================================================================
#   needed for LIVE/PIRS execution
# ============================================================================
KMAKEPATCH 0x800FC470 # XeCryptBnQwBeSigVerify_0
0:
	li %r3, 1
	blr 
9:

#=============================================================================
# Patches SataDiskAuthenticateDevice
#
# Regular FreeBoot would have done the following at 0x80128378
#     li %r3, 1
#     blr
#
# However, that breaks compat with FATXPlorer formatted drives with a SS and
# "extra space"... this patch does full auth for retail for such drives but
# still allows generic drives by patching the error path to return TRUE
#============================================================================

#============================================================================
# Rather than calling VdDisplayFatalError to display an E69 (hehehehe),
# jump to the error handler in SataDiskAuthenticateDevice
#============================================================================
KMAKEPATCH 0x801283B8
0:
   KMAKEBRANCH 0x80128518
9:

#============================================================================
# Patch the call to XeCryptBnDwLePkcs1Verify to always return SUCCESS
# when verifying the security sector
#============================================================================
KMAKEPATCH 0x801284DC
0:
   li %r3, 1
9:

#============================================================================
# Patch error handler in SataDiskAuthenticateDevice to return TRUE instead
# of FALSE
#============================================================================
KMAKEPATCH 0x80128518
0:
   li %r3, 1
9:

KMAKEPATCH 0x800F7D00 # XeKeysConsoleSignatureVerification 
0:
	cmplwi cr6, %r5, 0
	li %r3, 1
	beq cr6, 0x8
	stw %r3, 0(%r5)
	blr 
9:

#;============================================================================
#; start launch.xex if present                                                
#;============================================================================
KMAKEPATCH 0x8012D000 # Dashlaunch in empty spot
	.set HookDest, PatchAddr
	.set XexLoadImage, 0x800793d8
	.set XamLoadedHook, 0x80061154 	#; Phase1Initialization
	.set HookFileName, (RealAddr+(1f-0f))
0:
	mr %r31, %r3

	cmpwi cr6, %r31, 0
	blt cr6, xamfailed
	beq cr6, loadmod

xamfailed:
	blr

loadmod:
	lis %r3, -0x7fee
	ori %r3, %r3, 0xd038
	lis %r5, 0
	li %r4, 0
	ori %r4, %r4, 8
	li %r6, 0
	KMAKEBRANCHL XexLoadImage
	li %r31, 0
	KMAKEBRANCH (XamLoadedHook + 4)
1:
	#;.string "\\Device\\Harddisk0\\Partition1\\launch.xex"
	.string "\\Device\\Flash\\launch.xex"
	.byte 0
	.align 2
9:

KMAKEPATCH XamLoadedHook # Phase1init, branch to dashlaunch
0:
	MAKEBRANCHL HookDest
9:

#;============================================================================
#; XexpLoadXexHeaders - 0xC0000059 revision mismatch                          
#;============================================================================
KMAKEPATCH 0x800791C8 # XexGetModuleImportVersions
0:
	li %r3, 0
9:

# ============================================================================
# fix sfcxmu corruption issues on jasper bigblock - use 008 or higher for retail
# SfcxInspectLargeDataBlock 8008E060 lbz     %r23, 7(%r30) # r23 = kernelresv blocks
# ============================================================================
KMAKEPATCH 0x8008E060
0:
	li %r23, 0x10
9:

#============================================================================
# XexpLoadFile - skip 0xC00000CC (BAD_NETWORK_NAME) error                    
# bl        RtlImageXexHeaderString                                          
#============================================================================
KMAKEPATCH 0x800786F0 # XexpLoadFile
0:
	li %r3, 0
9:

#;============================================================================
#; XexpLoadFile - skip 0xC000008B (resource not found) error                  
#; lwz     %r11, 0x4C(%r25) # 0x40000000 bound path flag                      
#;============================================================================
KMAKEPATCH 0x80078744 # XexpLoadFile
0:
	li %r11, 0
9:

#;============================================================================
#; XexpLoadFile - skip 0xC000008B (resource not found) error                  
#; lwz     %r11, 0x4C(%r25) # 0x20000000 bound device flag                    
#;============================================================================
KMAKEPATCH 0x80078794 # # XexpLoadFile
0:
	li %r11, 0
9:

#;============================================================================
#; mid XeKeysConsoleSignatureVerification - skip sig check                    
#;============================================================================
KMAKEPATCH 0x800F7D50 #  XeKeysConsoleSignatureVerification probably redundant
0:
	li %r3, 1
	KMAKEBRANCH 0x800f7d78
9:

.long 0xffffffff
