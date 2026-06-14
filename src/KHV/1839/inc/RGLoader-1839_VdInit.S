# XeDK on Post-Y1 PRE-ALPHA thanks to Scar (kavkazsila)
# PROGRESS REPORT:
#  Rhea will fail to train edram sometimes, but yolo restart the console and it's fine

.set SHIVA, 0x10; .set XENON, 0x5811; # Zephyr.0 = Xenon Vittu?; Zephyr.1 = Xenon v3
.set RHEA, 0x5821; # Zephyr.2 = 58210001(?); Falcon/Opus/Elpiss = 58210002
.set ZEUS, 0x5831; # https://www.youtube.com/watch?v=LvSOOrAPk-U
.set VALHALLA, 0x5841; .set HANALESS, 0x5851

# ASIC IDs - Pull from 17489 XDK @ 801E6FBC with a peek-poker
# Current bench systems
# Falcon  - 58210002
# Elpiss  - 58210002
# Tonka   - 58310011
# Trinity - 58410001

.set VdpGraphicsAsicID, 0x801133A0
.set VdIO, 0x7FC8 # 0x7FC80000

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
# VdInitializeEDRAM - Thanks SK1080!
#
# NOTE: ASIC IDs are handled different under this kernel
# Only the major version of the GPU is used, ie: Rhea = 2; Zeus = 3
# No table was made prior to this, fuckups were made along the way 
##############################################################################
.set InitEDRAMRegs, 0x800AE9A4
.set VdDisplayFatalError, 0x800A8DF8
KMAKETRAMPOLINE InitEDRAMRegs
0:
   # Load the actual ASIC ID from RAM
   lis %r4, -0x7FEF
   lwz %r3, 0x33A0(%r4)

   # Check for Y1 (ASIC ID 0x11)
   cmplwi cr6, %r3, 0x11
   bne cr6, not_a_y1

   # Y1 edram timing = 0x1A
   li %r10, 0x1A
   KMAKEBRANCH InitEDRAMRegs + 4

not_a_y1:
   # We're running something *other* than a Y1.
   # The upper 16 bits will contain the Xenos ID
   srwi %r3, %r3, 16

   # Check for Rhea (Xenos ID 0x5821)
   cmplwi cr6, %r3, 0x5821
   bne cr6, check_gunga

   # It's a rhea GPU, set the edram timing and jump back
   li %r10, 0x1E
   KMAKEBRANCH InitEDRAMRegs + 4

check_gunga:
   # Check for Gunga (Xenos ID 0x5831)
   cmplwi cr6, %r3, 0x5831

   # If it's not a Rhea, and not a Gunga, we're kind of fucked.
   # It's probably a slim which is unsupported (for now) so throw an E78
   bne cr6, throw_e78

   # Zeus/Kronos timing
   li %r10, 0x15
   KMAKEBRANCH InitEDRAMRegs + 4

throw_e78:
   # Call VdDisplayFatalError at 0x800A8DF8 to throw an E78 (unsupported GPU) error
   lis %r3, 1
   ori %r3, %r3, 0x244E
   KMAKEBRANCHL VdDisplayFatalError
9:
KENDTRAMPOLINE 0x12

# .if CON_REV != HANALESS # Y2.5 and/or initial Rhea do not use this, this is gated by an IF (ASIC >= 58210002); check 
KMAKEPATCH 0x800AE9EC
0:
    li        %r4, 0x31
9:

KMAKEPATCH 0x800AEA3C
0:
    li        %r4, 0x31
9:

###################################################################
# VdEnableDisableClockGating
###################################################################
.set VdEnableDisableClockGating, 0x800A9D78
KMAKEPATCH VdEnableDisableClockGating
0:
    lis       %r10, VdIO

    # Load the actual ASIC ID from RAM
    lis %r4, -0x7FEF
    lwz %r3, 0x33A0(%r4)

    # Check for Y1, we really don't need any of this since Y1 is officially supported
    cmplwi cr6, %r3, 0x11
    bne cr6, rhea_clock

    # Y1 clock gating bitset = 0x04000300
    lis %r11, 0x400
    ori %r11, %r11, 0x300
    b store_bitset_0

rhea_clock:
    # If it's not Y1, all we really care about is the upper 16 bits e.g. 0x5821, 0x5831, etc.
    srwi %r3, %r3, 16

    # Rhea clock gating bitset = 0x04400380
    lis       %r11, 0x440
    ori       %r11, %r11, 0x0380

    cmplwi cr6, %r3, 0x5821
    beq cr6, store_bitset_0 # zeus clock gating config uses the same bit set as rhea with stuff on top

zeus_clock:
    oris      %r11, %r11, 0x903F
    ori       %r11, %r11, 0xF006 # Zeus = 0x947FF386, 

store_bitset_0:
    stw       %r11, 0x204(%r10)
    eieio

    # Default "bitset 1" = 0x180002
    lis       %r11, 0x18
    ori       %r11, %r11, 0x2

    # If we're rhea or lesser, we're done
    cmplwi cr6, %r3, 0x5831
    blt store_bitset_1

    # Zeus bitset 1 = 0x3FC7C2
    lis %r11, 0x3F
    ori %r11, %r11, 0xC7C2

store_bitset_1:
    stw       %r11, 0x208(%r10)
    eieio
    blr
9:

##############################################################################
# VdOneTimeDeviceInitialize
##############################################################################
.set VdOneTimeDeviceInitializeEpilogue, 0x800FDFCC
KMAKETRAMPOLINE VdOneTimeDeviceInitializeEpilogue
0:
    # Load the actual ASIC ID from RAM
    lis %r4, -0x7FEF
    lwz %r3, 0x33A0(%r4)

    # Check for Y1, we really don't need any of this since Y1 is officially supported
    cmplwi cr6, %r3, 0x11
    beq cr6, all_done_epilogue

    # If it's not Y1, all we really care about is the upper 16 bits e.g. 0x5821, 0x5831, etc.
    srwi %r3, %r3, 16

    lwz       %r9, 0x4F0(%r31) # %r31 = VdIO

    cmplwi cr6, %r3, 0x5831
    blt cr6, its_a_rhea

    # We're running a graphics chip thats zeus or later
    lis       %r10, 0x408
    lis       %r11, -0x710 # 0xF8F00000
    ori       %r10, %r10, 0x1100 # 0x4081100
    b old_macdonald

its_a_rhea:
    lis       %r10, 4
    lis       %r11, -0x10 # 0xFFF00000
    ori       %r10, %r10, 0x100 # 0x40100

old_macdonald:
    ori       %r11, %r11, 0xFFFF
    and       %r11, %r11, %r9
    or        %r11, %r11, %r10
    stw       %r11, 0x4F0(%r31)

    # and on this farm he had some PPC assembly...
    eieio

all_done_epilogue:

    # do what we patched
    addi      %r1, %r1, 0x170

    KMAKEBRANCH VdOneTimeDeviceInitializeEpilogue + 4
9:
KENDTRAMPOLINE 0x16

##############################################################################
# VdOneTimeDeviceInitialize
##############################################################################
.set VdOneTimeDeviceInitializeSetAsicId, 0x800FDEF0
KMAKETRAMPOLINE VdOneTimeDeviceInitializeSetAsicId
0:
   addi %r6, %r1, 0x52
   lhbrx %r5, 0, %r6
   clrlwi %r5, %r5, 16

   # When later kernels detect a Y1, they'll skip ORing the Xenos ID
   cmplwi cr6, %r5, 0x5811
   beq cr6, its_a_y1

   slwi %r5, %r5, 16
   or %r11, %r5, %r11

its_a_y1:
   stw %r11, 0x33A0(%r10)
   KMAKEBRANCH VdOneTimeDeviceInitializeSetAsicId + 4
9:
KENDTRAMPOLINE 0x10

##############################################################################
# VdGetGraphicsAsicID
# Return 0x11 (Y1 GPU)
##############################################################################
KMAKEPATCH 0x800A86DC
0:
    li %r3, 0x11
9:
