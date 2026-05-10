
##############################################################################
# VdInitializeEDRAM
##############################################################################
KMAKEHOOK 0x800AE9C4 0x800AEA60 # SBI Register 4000h pre-read bail

#############################################
# HSIO Training
#############################################
.set HSIOKSBBail, 0x800ADE74

KMAKEHOOK HSIOKSBBail 0x800AE814

##############################################################################
# VdInitializeANA
##############################################################################
.set VdpWriteI2CBusUlong, 0x800B31E0
.set HalSendSMCMessage, 0x80065368
.set keMemcpy, 0x800BDF30

.set SMBusIn, 0x50
.set SMBusOut, 0x60
.set VdpWriteXDVOUlong, KBouncyCastleAbyss

KRESERVETRAMPOLINE
0:
    mflr      %r12
    KSaveRegsToSP 28
    stwu      %r1, -0x60(%r1)

    mr        %r29, %r4
    mr        %r28, %r3
    mr        %r11, %r29
    cmplwi    %cr6, %r3, 0xFF
    ble       %cr6, WriteUlong

    li        %r5, 4
    srwi      %r10, %r11, 24
    addi      %r4, %r1, 0x50
    rlwimi    %r10, %r11, 24, 16, 23
    rlwimi    %r10, %r11, 8, 8, 15
    insrwi    %r10, %r11, 8, 0
    stw       %r10, 0x50(%r1)
    bl        VdpWriteI2CBus
    b         VdWriteXDVOExit

WriteUlong:
    mr        %r5, %r29
    mr        %r4, %r28
    li        %r3, 0xE0
    KMAKEBRANCHL VdpWriteI2CBusUlong

VdWriteXDVOExit:
    addi      %r1, %r1, 0x60
    KRestoreRegsFromSP 28
    .long 0

##############################################################################

VdpWriteI2CBus:
    mflr      %r12
    stw       %r12, -8(%r1)
    std       %r30, -0x18(%r1)
    std       %r31, -0x10(%r1)
    stwu      %r1, -0x90(%r1)

    mr        %r31, %r3

    addi      %r11, %r1, SMBusIn
    li        %r30, 0
    subfic    %r10, %r31, 0x1FF
    addi      %r9, %r5, 1
    subfe     %r10, %r10, %r10
    addi      %r3, %r1, SMBusIn + 7
    std       %r30, 0(%r11)
    rlwinm    %r10, %r10, 0, 29, 29
    std       %r30, 8(%r11)
    lbz       %r11, SMBusIn + 3(%r1)
    addi      %r10, %r10, 0x39
    lbz       %r8, SMBusIn + 1(%r1)
    ori       %r11, %r11, 0x80
    stb       %r31, SMBusIn + 6(%r1)
    insrwi    %r8, %r9, 4, 24
    insrwi    %r11, %r10, 7, 25
    li        %r10, 0x11
    stb       %r8, SMBusIn + 1(%r1)
    stb       %r11, SMBusIn + 3(%r1)
    stb       %r10, SMBusIn(%r1)
    KMAKEBRANCHL keMemcpy

    # lockless, we don't have HDMI
    addi      %r4, %r1, SMBusOut
    addi      %r3, %r1, SMBusIn
    KMAKEBRANCHL HalSendSMCMessage
    lbz       %r3, 0x61(%r1)

    addi      %r1, %r1, 0x90
    lwz       %r12, -8(%r1)
    mtlr      %r12
    ld        %r30, -0x18(%r1)
    ld        %r31, -0x10(%r1)
    blr
9:
KENDTRAMPOLINE 0x4E

.macro WriteTimingHook KAddr Arg1Reg
.set EOBDest, (\KAddr + 0x24)
KMAKEPATCH \KAddr
0:
    mr        %r4, \Arg1Reg
    mr        %r3, %r11
    KMAKEBRANCHL VdpWriteXDVOUlong
    KMAKEBRANCH EOBDest
9:
.endm

WriteTimingHook 0x800B3348 8
WriteTimingHook 0x800B33C4 10
WriteTimingHook 0x800B3434 10
WriteTimingHook 0x800B34A4 10
WriteTimingHook 0x800B3514 10
WriteTimingHook 0x800B3580 10
WriteTimingHook 0x800B35D4 9
