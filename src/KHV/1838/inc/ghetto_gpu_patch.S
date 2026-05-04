# This is a ghetto GPU patch for 1838 that tries to do the same thing as the ghetto GPU patch for 1888
# but it doesn't really work

#============================================================================
# Patch VdpOneTimeDeviceInitialize to spoof the GPU ID to avoid E78
#============================================================================

# NOP out a breakpoint in VdpOneTimeDeviceInitialize
KMAKEPATCH 0x800FDF14
0:
   nop
9:

# Spoof the ASIC ID
KMAKEPATCH 0x800FDF40
0:
    li %r11, 0x11 #Prod GPU
9:

#============================================================================
# Patch VdInitializeEdram to set edram timing, otherwise graphics will look screwy
#============================================================================
KMAKEPATCH 0x800AE9A4
0:
.ifdef patch_gpu_zeus
   li %r10, 0x15 # Zeus/Kronos timing
.endif

.ifdef patch_gpu_rhea
   li %r10, 0x1E # Rhea timing
.endif
9:

KMAKEPATCH 0x800AE9EC
0:
   li %r4, 0x31
9:

KMAKEPATCH 0x800AEA3C
0:
   li %r4, 0x31
9:
