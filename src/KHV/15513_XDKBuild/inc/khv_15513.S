.include "macros.S"

#============================================================================
#   Patches for Hypervisor 21256.18_17489
#============================================================================

.set HV_FlagFixer, 0xB188
.set FixFusesAddr, 0xB400
.set HV_HvpGetFlashBaseAddress, 0x0000068C
.set HV_HvpFlashCopy, 0x00000484

#============================================================================
#  HV Patch Console Seq check
#============================================================================
MAKEPATCH 0x00006C30
0:
   nop  
9: 
    
MAKEPATCH 0x00006C40
0:
   nop  
9:

# ============================================================================
# 	Bypass CB check
# ============================================================================
MAKEPATCH 0x00006A24
0:
   li %r3, 1 
9:

# ============================================================================
# 	Bypass CD check
# ============================================================================
MAKEPATCH 0x00006BE4
0:
   li %r3, 0 
9:

# ============================================================================
# 	NOP MachineCheck
# ============================================================================
MAKEPATCH 0x00006C68
0:
   nop
    li %r11, 0
9:

# ============================================================================
#	HvxLoadImageData - nop's out a sig check?
# ============================================================================
MAKEPATCH 0x0002A3D4
0:
	nop
	nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
MAKEPATCH 0x0002AB48
0:
	nop
9:

# ============================================================================
#	HvxResolveImports
#	Bypass STATUS_REVISION_MISMATCH - C0000059
# ============================================================================
# 00 02 AA 8C 00 00 00 01 60 00 00 00
MAKEPATCH 0x0002AB54
0:
	nop
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
KMAKEPATCH 0x800A2C18
0:
   li     %r3,  1
9:

KMAKEPATCH 0x800A0C7C
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

MAKEPATCH 0x00001BF4
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:

MAKEPATCH 0x000079D0
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x000079F0
0:
    addi    %r11, %r11, 0x0001
9:

MAKEPATCH 0x000079FC
0:
    cmplwi  %cr6, %r11, 0x000c
9:


MAKEPATCH 0x00008DD0
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x00008E00
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:


MAKEPATCH 0x00008F70
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x00008FA0
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:

MAKEPATCH 0x000090C4
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x000090F4
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:

MAKEPATCH 0x000093F0
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x00009420
0:
    addi    %r11, %r11, 0x0001
    cmplwi  %cr6, %r11, 0x000c
9:

MAKEPATCH 0x0000977C
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x000097AC
0:
    addi    %r11, %r11, 0x0001
    sldi    %r9, %r9, 3
    cmpwi   %cr6, %r11, 0x000c
9:

MAKEPATCH 0x00009A78
0:
    bla     FixFusesAddr
9:

MAKEPATCH 0x00009AA4
0:
    addi    %r11, %r11, 0x0001
    sldi    %r9, %r9, 3
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

# ============================================================================
# Syscall 0 Backdoor (FreeBoot, RGL, etc.)
# ============================================================================
.set oldHvxGetVer, 0x1B98
.set newHvxGetVer, 0xB328
.set memcpy, 0x9E80
.set sysCallTable, 0x15AD0

MAKEPATCH sysCallTable
0:
	.long   newHvxGetVer
9:

#;// HvxExecute  Params( 0x72627472, 4, (QWORD)srcAddr, (QWORD)destAddr, (QWORD) lenInBytes)  will jump to destAddr after memcpy
#;// MemCpy      Params( 0x72627472, 5, (QWORD)srcAddr, (QWORD)destAddr, (QWORD) lenInBytes)
MAKEPATCH newHvxGetVer
0:
   # check if secret key is right (0x72627472)
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
	lis       %r6, 0x3880 #;//0x38800000
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
#	The li %r4, 7 in this is modified by the syscall0 backdoor 
#	to toggle the memory protection state.
#	ENABLED = 0x38800000 (li r4, 0) || DISABLED = 0x38800007 (li r4, 7)
# 
#  We'll leave it enabled by default
# ============================================================================
MAKEPATCH 0x000011BC
0:
	ba  0x15F0
9:

MAKEPATCH 0x000015F0
0:
	li  %r4, 0
	andc %r1, %r1, %r4
	mtspr 0x3b5, %r1
	ba 0x11C0
9:

MAKEPATCH 0x00030090
0:
	ori       %r4, %r4, 0x1B0
9:

# ============================================================================
# usbdsec patch
# ============================================================================
.set UsbdIsDeviceAuthenticated, 0x80104B18
.set WgcAddDevice_bne, 0x801309E4
.set WgcAddDevice_BranchLocation, 0x10
.set WgcBindToUserNop, 0x8012F9E0

KMAKEPATCH UsbdIsDeviceAuthenticated
0:
   li %r3, 1
   blr
9:

KMAKEPATCH WgcAddDevice_bne
0:
   b WgcAddDevice_BranchLocation
9:

KMAKEPATCH WgcBindToUserNop
0:
   nop
9:

# ============================================================================
# Patch SataDiskAuthenticateDevice
# ============================================================================

# goto error path instead of VdDisplayFatalError
KMAKEPATCH 0x8019ABB4
0:
   KMAKEBRANCH 0x8019ACD0
9:

# patch the error path to return a success
KMAKEPATCH 0x8019ACD0
0:
   li %r3, 1
9:

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
