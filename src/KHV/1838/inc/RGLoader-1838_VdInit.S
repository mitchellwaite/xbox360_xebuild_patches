# XeDK on Post-Y1 PRE-ALPHA
# PROGRESS REPORT:
#   Non-ATI GPUs and Y1 still mog the shit out of Rhea on Dolphin (1337 vs 230 FPS)

.set SHIVA, 0x10; .set XENON, 0x5811; # Zephyr.0 = Xenon Vittu?; Zephyr.1 = Xenon v3
.set RHEA, 0x5821; # Zephyr.2 = 58210001(?); Falcon/Opus/Elpiss = 58210002
.set ZEUS, 0x5831; # https://www.youtube.com/watch?v=LvSOOrAPk-U
.set VALHALLA, 0x5841; .set HANALESS, 0x5851

.set CON_REV, RHEA

# ASIC IDs - Pull from 17489 XDK @ 801E6FBC with a peek-poker
# Current bench systems
# Falcon  - 58210002
# Elpiss  - 58210002
# Tonka   - 58310011
# Trinity - 58410001

.set VdpGraphicsAsicID, 0x801133A0
.set VdIO, 0x7FC8 # 0x7FC80000

.set KSaveGPRLR, 0x800BDDE0
.set KRestoreGPRLR, 0x800BDE30

# r14 - r31
.macro KSaveRegsToSP Register
    .set SaveRegRef, KSaveGPRLR + (((\Register) - 14) * 4)
    KMAKEBRANCHL SaveRegRef
.endm

.macro KRestoreRegsFromSP Register
    .set RestoreRegRef, KRestoreGPRLR + (((\Register) - 14) * 4)
    KMAKEBRANCH RestoreRegRef
.endm

#.set KBouncyCastleAbyss, 0x8010A180
.set KBouncyCastleAbyss, 0x8010A220

.macro KRESERVETRAMPOLINE
    KMAKEPATCH KBouncyCastleAbyss
.endm

.macro KMAKETRAMPOLINE DAddress
    KMAKEHOOK \DAddress KBouncyCastleAbyss
    KRESERVETRAMPOLINE
.endm

# Remove me when you (ab)use LLVM
.macro KENDTRAMPOLINE SizeOfTrampoline
.set KBouncyCastleAbyss, KBouncyCastleAbyss + ((\SizeOfTrampoline) * 4)
.endm

# If you're in for the fun
.if CON_REV >= VALHALLA
.include "VdValhalla.S"
.endif

# Nothing for you! Come back one year
#.if CON_REV == HANALESS
#.include "VdHANAless.S"
#.endif

##############################################################################
# VdInitializeEDRAM - Thanks SK1080!
#
# NOTE: ASIC IDs are handled different under this kernel
# Only the major version of the GPU is used, ie: Rhea = 2; Zeus = 3
# No table was made prior to this, fuckups were made along the way 
##############################################################################
#.set EDRAMTiming, 0x1A # default
.if CON_REV >= ZEUS
.set EDRAMTiming, 0x15 # Zeus
.else
.set EDRAMTiming, 0x1E # Rhea
.endif
.set InitEDRAMRegs, 0x800AE9A4

.if CON_REV < VALHALLA
KMAKEPATCH InitEDRAMRegs
0:
    li        %r10, EDRAMTiming
9:
.else
KMAKEHOOK InitEDRAMRegs InitEDRAMRegs + 0xC
.endif # timing

.if CON_REV != HANALESS # Y2.5 and/or initial Rhea do not use this, this is gated by an IF (ASIC >= 58210002); check 
KMAKEPATCH 0x800AE9EC
0:
    li        %r4, 0x31
9:

KMAKEPATCH 0x800AEA3C
0:
    li        %r4, 0x31
9:
.endif # reg 4001h

###################################################################
# HSIO Training on Rhea
###################################################################
.set SBI_daughter_write_reg32, 0x800AD478 # (void*, u32, u32)
.set SBI_daughter_read_modify_write_reg32, 0x800AD7B0 # (void*, u32, u32, u32, u32)

.set ENABLE_HSIO_HACK, 0
.set ENABLE_HSIO_HACK0, 0
.set ENABLE_HSIO_HACK1, 0
.set ENABLE_HSIO_HACK2, 0
.set ENABLE_HSIO_HACK3, 0 # crashes frequently + introduces additional artifacting
.set ENABLE_HSIO_HACK4, 0

KMAKEPATCH 0x800AEA70
0:
    li        %r6, 0x11
9:

.if ENABLE_HSIO_HACK
.if ENABLE_HSIO_HACK0
KMAKETRAMPOLINE 0x800ADF28
0:
    lwz       %r11, 0x3C54(%r29)
.if 1
    rlwinm    %r11, %r11, 0, 23, 21
    stw       %r11, 0x3C54(%r29)
    eieio

    lwz       %r11, 0x3C54(%r29)
    rlwinm    %r11, %r11, 0, 22, 20
.else
    ori       %r11, %r11, 0x200
    stw       %r11, 0x3C54(%r29)
    eieio

    lwz       %r11, 0x3C54(%r29)
    ori       %r11, %r11, 0x400
.endif
    stw       %r11, 0x3C54(%r29)
    eieio

    mr        %r11, %r30
    KMAKEBRANCH 0x800ADF2C
9:
KENDTRAMPOLINE 0x10

.if 1 # UNSTABLE
.macro SetItr KAddr
KMAKEPATCH \KAddr
0:
    cmplwi    cr6, %r10, 0x14
9:
.endm

KMAKEPATCH 0x800ADF3C
0:
    cmplwi    cr6, %r11, 0x14
9:

KMAKEPATCH 0x800AE8A8
0:
    cmplwi    cr6, %r19, 0x14
9:

KMAKEPATCH 0x800AE978
0:
    cmplwi    cr6, %r30, 0x14
9:

SetItr 0x800AD554 # SBI_daughter_read_reg32
SetItr 0x800AD580
SetItr 0x800AD5AC
SetItr 0x800AD5D8
SetItr 0x800AD498 # SBI_daughter_write_reg32
SetItr 0x800AD4C4
SetItr 0x800AD4F4
SetItr 0x800AD520
.endif # UNSTABLE
.endif # ENABLE_HSIO_HACK0

.if ENABLE_HSIO_HACK1
KMAKEHOOK 0x800ADFE8 0x800AE07C
.if 0
KMAKEPATCH 0x800AE090
0:
    cmplwi    cr6, %r10, 0x14
9:
.endif
.endif # ENABLE_HSIO_HACK1

.if ENABLE_HSIO_HACK2
KMAKEPATCH 0x800AD94C
0:
    li        %r4, 0x5002
    mr        %r3, %r30
    
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r11, %r11, %r7
    slwi      %r11, %r7, 2
    or        %r5, %r11, %r7
    stw       %r5, 0x50(%r1)
    KMAKEBRANCHL SBI_daughter_write_reg32
    KMAKEBRANCH 0x800ADA24
9:
.endif # ENABLE_HSIO_HACK2

.if ENABLE_HSIO_HACK3
.if 0 # UNSTABLE
KMAKETRAMPOLINE 0x800AE2B4
0:  
    addi      %r10, %r1, 0x230 # 1F0h = C1; 230h = Rhea

    mr        %r5, %r30
    mr        %r28, %r30
    addi      %r27, %r1, 0x60

RegReadLoop:
    lwz       %r11, 0(%r27)
    addi      %r27, %r27, 4
    slwi      %r11, %r11, 2
    lwzx      %r11, %r11, %r10
    clrlwi    %r11, %r11, 30
    slw       %r11, %r11, %r28
    addi      %r28, %r28, 2
    or        %r5, %r11, %r5
    cmpwi     cr6, %r28, 0x12
    blt       cr6, RegReadLoop

    li        %r4, 0x5002
    mr        %r3, %r28
    KMAKEBRANCHL SBI_daughter_write_reg32
    KMAKEBRANCH 0x800AE2F4
9:
KENDTRAMPOLINE 0xD
.else
KMAKEPATCH 0x800AE2C0
0:
    #addi      %r10, %r1, 0x1F0 # C1
    addi      %r10, %r1, 0x230 # post-Rhea

    #addi      %r9, %r1, 0x2D0 # C1 - 9199
    #addi      %r9, %r1, 0x310 # post-Rhea - 9199
9:
.endif # UNSTABLE
.endif # ENABLE_HSIO_HACK3

.endif # ENABLE_HSIO_HACK

###################################################################
# VdEnableDisableClockGating
###################################################################
.set VdEnableDisableClockGating, 0x800A9D78

#.set ClockGatingBitset0, 0x84003300 # Shiva
#.set ClockGatingBitset0, 0x4000300 # C1; default
.set ClockGatingBitset1, 0x180002

.if CON_REV == ZEUS
.set ClockGatingBitset0, 0x947FF386 # Zeus
.set ClockGatingBitset1, 0x3FC7C2
.elseif CON_REV >= RHEA
.set ClockGatingBitset0, 0x4400380 # Rhea
.endif

KMAKEPATCH VdEnableDisableClockGating
0:
    lis       %r10, VdIO
.if 1 #CON_REV != ZEUS
    lis       %r11, ClockGatingBitset0@h
    ori       %r11, %r11, ClockGatingBitset0@l
.else
    lis       %r11, 0x440
    ori       %r11, %r11, 0x380 # 0x4400380
    oris      %r11, %r11, 0x903F
    ori       %r11, %r11, 0xF006 # Zeus = 0x947FF386
.endif
    stw       %r11, 0x204(%r10)
    eieio

    lis       %r11, ClockGatingBitset1@h
    ori       %r11, %r11, ClockGatingBitset1@l

    stw       %r11, 0x208(%r10)
    eieio
    blr
9:

##############################################################################
# VdOneTimeDeviceInitialize
##############################################################################
.set VdOneTimeDeviceInitializeEpilogue, 0x800FE02C
KMAKETRAMPOLINE VdOneTimeDeviceInitializeEpilogue
0:
    lwz       %r9, 0x4F0(%r31) # %r31 = VdIO
.if CON_REV >= ZEUS
    lis       %r10, 0x408
    lis       %r11, -0x710 # 0xF8F00000
    ori       %r10, %r10, 0x1100 # 0x4081100
.else
    lis       %r10, 4
    lis       %r11, -0x10 # 0xFFF00000
    ori       %r10, %r10, 0x100 # 0x40100
.endif 
    ori       %r11, %r11, 0xFFFF
    and       %r11, %r11, %r9
    or        %r11, %r11, %r10
    stw       %r11, 0x4F0(%r31)
    eieio

    addi      %r1, %r1, 0x170
    KMAKEBRANCH VdOneTimeDeviceInitializeEpilogue + 4
9:
KENDTRAMPOLINE 0x14

KMAKEPATCH 0x800A86DC
0:
    li %r3, 0x11
9:
