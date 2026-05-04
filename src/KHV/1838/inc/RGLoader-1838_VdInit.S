# K.I.S.S. Variant, not final just yet
#
# Thanks to Scar (kavkazsila) on discord for these!
#
.set SHIVA, 0x10; .set XENON, 0x5811; .set ZEPHYR, 0x5821; .set FALCON, 0x5831
.set GUNGA, 0x5832 # KERNEL& 5632 (Recovery) XDK& 5632; https://www.youtube.com/watch?v=LvSOOrAPk-U
.set JASPER, 0x5841; .set VALHALLA, 0x5851

.set CON_REV, FALCON

.set VdpGraphicsAsicID, 0x801133A0
.set VdIO, 0x7FC8 # 0x7FC80000

# No KSB DAC support :S
.set USE_SHADOWBOOT_HOOKS, 0

#.set KBouncyCastleAbyss, 0x8010A120
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

##############################################################################
# VdOneTimeDeviceInitialize
##############################################################################
.set VdOneTimeDeviceInitializeEpilogue, 0x800FE02C
KMAKETRAMPOLINE VdOneTimeDeviceInitializeEpilogue
0:
    lwz       %r9, 0x4F0(%r31) # %r31 = VdIO
.if CON_REV >= FALCON
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

##############################################################################
# VdInitializeEDRAM - Thanks SK1080!
#
# Note: The same patches that spoof the ASIC ID in 1888 do NOT work at the
# moment for 1838. Investigation tbd
##############################################################################
.if CON_REV >= JASPER
.set EDRAMTiming, 0x15 # Zeus; here for shock value
.else
.set EDRAMTiming, 0x1E # Rhea
#.set EDRAMTiming, 0x1A # default
.endif
.set InitEDRAMRegs, 0x800AE9A4

.if CON_REV < JASPER
KMAKEPATCH InitEDRAMRegs
0:
    li        %r10, EDRAMTiming
9:
.else
KMAKEHOOK InitEDRAMRegs InitEDRAMRegs + 0xC
.endif # timing
.if 1
KMAKEPATCH 0x800AE9EC
0:
    li        %r4, 0x31
9:

KMAKEPATCH 0x800AEA3C
0:
    li        %r4, 0x31
9:
.endif # reg 4001h

##############################################################################
# VdEnableDisablePowerSavingMode - Post-Zeus
##############################################################################
.if CON_REV >= JASPER
KMAKEHOOK 0x800A9D38 0x800A9D58
.endif

###################################################################
# VdEnableDisableClockGating
###################################################################
.set VdEnableDisableClockGating, 0x800A9D78

#.set ClockGatingBitset0, 0x84003300 # Shiva
.set ClockGatingBitset1, 0x180002
.if CON_REV == FALCON
.set ClockGatingBitset0, 0x947FF386 # Falcon
.set ClockGatingBitset1, 0x3FC7C2
.elseif CON_REV < ZEPHYR
.set ClockGatingBitset0, 0x4000300 # Xenon
.else
.set ClockGatingBitset0, 0x4400380 # Zephyr
.endif

.if CON_REV != FALCON
KMAKEPATCH VdEnableDisableClockGating
0:
    lis       %r10, VdIO
    lis       %r11, ClockGatingBitset0@h
    ori       %r11, %r11, ClockGatingBitset0@l
    stw       %r11, 0x204(%r10)
    eieio

    lis       %r11, ClockGatingBitset1@h
    ori       %r11, %r11, ClockGatingBitset1@l
    stw       %r11, 0x208(%r10)
    eieio
    blr
9:
.else
KMAKEPATCH VdEnableDisableClockGating
0:
    lis       %r10, VdIO
    lis       %r11, 0x440
    ori       %r11, %r11, 0x380 # 0x4400380
    oris      %r11, %r11, 0x903F
    ori       %r11, %r11, 0xF006 # Rhea = 0x947FF386
    stw       %r11, 0x204(%r10)
    eieio

    lis       %r11, 0x3F
    ori       %r11, %r11, 0xC7C2 # 0x3FC7C2
    stw       %r11, 0x208(%r10)
    eieio
    blr
9:
.endif
