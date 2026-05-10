
##############################################################################
# VdInitializeEDRAM
##############################################################################
#KMAKEHOOK 0x800AE9A4 0x800AE9B0 # done by main source
#KMAKEHOOK 0x800AE9C4 0x800AEA60 # SBI Register 4000h pre-read bail

#############################################
# HSIO Training - SBI Daughter Reg
#############################################
.set HSIOValhallaBail, 0x800ADF64

.if CON_REV == VALHALLA
KMAKEHOOK HSIOValhallaBail HSIOValhallaBail + 8
.endif

##############################################################################
# VdEnableDisablePowerSavingMode
##############################################################################
KMAKEHOOK 0x800A9D38 0x800A9D58

#############################################
# VdClockRegisterConfig
#############################################
.set VdpUpdateValhallaClockRegister, KBouncyCastleAbyss
.set KeStallExecutionProcessor, 0x8006E628
KRESERVETRAMPOLINE
0:
    mflr      %r12
    KSaveRegsToSP 28
    stwu      %r1, -0x80(%r1)

    lis       %r10, 0x1FF2
    add       %r11, %r4, %r10
    slwi      %r31, %r11, 2
    lwz       %r11, 0(%r31)
    rlwinm    %r11, %r11, 0, 9, 6
    stw       %r11, 0(%r31)
    eieio

    lwz       %r9, 0(%r31)
    sync

    add       %r10, %r3, %r10
    slwi      %r9, %r8, 9
    slwi      %r30, %r10, 2
    or        %r9, %r9, %r5
    slwi      %r10, %r6, 4
    slwi      %r29, %r9, 2
    or        %r10, %r10, %r7
    rlwinm    %r11, %r11, 0, 30, 20
    slwi      %r10, %r10, 2
    stw       %r29, 0(%r30)
    or        %r28, %r10, %r11
    eieio

    stw       %r28, 0(%r31)
    eieio

    lwz       %r11, 0(%r31)
    sync

    li        %r3, 0x3E8
    KMAKEBRANCHL KeStallExecutionProcessor
    ori       %r11, %r29, 1
    stw       %r11, 0(%r30)
    eieio

    lwz       %r11, 0(%r30)
    sync

    li        %r3, 0x3E8
    KMAKEBRANCHL KeStallExecutionProcessor
    oris      %r11, %r28, 0x100
    stw       %r11, 0(%r31)
    eieio

    lwz       %r11, 0(%r31)
    sync

    addi      %r1, %r1, 0x80
    KRestoreRegsFromSP 28
9:
KENDTRAMPOLINE 0x2C

.set ClockRegisterPatch, 0x800FDDE0
KMAKETRAMPOLINE ClockRegisterPatch
0:
    lis       %r8, 1
    li        %r7, 2
    ori       %r8, %r8, 0x40B1 # 0x140B1
    li        %r6, 0xE
    li        %r5, 0x8D
    li        %r4, 0x86
    li        %r3, 0x91
    KMAKEBRANCHL VdpUpdateValhallaClockRegister

    lis       %r31, VdIO
    lwz       %r11, 0x218(%r31)
    clrrwi    %r11, %r11, 1
    KMAKEBRANCH ClockRegisterPatch + 0x3C # 0x800FDE1C
9:
KENDTRAMPOLINE 0x10
