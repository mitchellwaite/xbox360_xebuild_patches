.include "macros.S"

# ============================================================================
#       ProfileEmbeddedContent::Validate
#       remove sig check
# ============================================================================
MAKEPATCH 0x81B4885C
0:
	nop
9:

MAKEPATCH 0x81B48870
0:
	nop
9:


# ============================================================================
#     XContent::OpenWorker
#         ignore license check
# ============================================================================
MAKEPATCH 0x81736820
0:
	nop
9:

# ============================================================================
#     CXNetLogonTask::GetNatType
#         patch out exceptions in NAT type
# ============================================================================
MAKEPATCH 0x81820E4C
0:
	nop
9:

MAKEPATCH 0x81820E78
0:
	nop
9:

MAKEPATCH 0x81821120
0:
	nop
9:

# ============================================================================
# Patches out DbgBreakPoint so the console doesn't freeze
# TODO: why isn't this a kernel patch
# ============================================================================
MAKEPATCH 0x800AF800
0:
	nop
9:

# ============================================================================
#     MmAllocateImageMemory / XamAllocBreakOnOutOfMemory
#         get rid of heap crash errors
# ============================================================================
MAKEPATCH 0x81D23350
0:
	.long 0x00000000
9:

# ============================================================================
# Patches XexpCreateDataTableEntry to NOP out a breakpoint
# ============================================================================
MAKEPATCH 0x8009FE50
0:
	nop
9:

# ============================================================================
# CXamTitleLoader::TitleLoaderPrepareRunPostLoadTasks
# Media Extended Authentication - fix dvd drives for jtags
# ============================================================================
MAKEPATCH 0x8175C8EC
0:
	b 0x10
9:

# ============================================================================
#     CDvdDrive::Authenticate
#         fix retail xex check for jtags
# ============================================================================
MAKEPATCH 0x8176D338
0:
   li  %r3, 0
   blr
9:

# ============================================================================
# CXNetLogonTask::CXNetLogonTask
# NOPs out a breakpoint and spoofs the client version
# Standard RGL just patches the instruction at 0x81823314
# ============================================================================
MAKEPATCH 0x81823310
0:
	nop
	li %r11, 0x4497
9:

# ============================================================================
# CXamUpdateManifest::IsXttValidAndCurrent
# Ignore result from XuiAuthenticateXTTSignature
# (stops the avatar update loop?)
# ============================================================================
MAKEPATCH 0x817BE360
0:
	nop
9:

MAKEPATCH 0x817BE394
0:
	MAKEBRANCH 0x817be3dc
9:

# ============================================================================
#       XContent::ContentMountPackage
#       ignore hash checks
# ============================================================================
MAKEPATCH 0x81734204
0:
	b 0x14
9:

MAKEPATCH 0x817342F4
0:
   b  0x14
9:

# ============================================================================
#       XContent::ContentOpenPackageFile
#       ignore hash check
# ============================================================================
MAKEPATCH 0x81733ACC
0:
	b -0xFC
9:

# done with patch section

#============================================================================
.long 0xFFFFFFFF
.end
#============================================================================