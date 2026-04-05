.include "macros.S"

# ============================================================================
#	XboxKrnlVersion
#       set to 17559
# ============================================================================
MAKEPATCH 0x80040460
0:
	.short 17559
   .short 0
9:

MAKEPATCH 0x80040468
0:
	.short 1888
	.short 0
9:

# ============================================================================
# We're patching out XwppTrace????
# ============================================================================
MAKEPATCH 0x818EDD8C
0:
	li %r3, 1
9:

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
# CXChalResp::CheckPkSig
# Ignore the result of XeCryptBnQwBeSigVerify and assume all challenge
# signatures are valid 
# ============================================================================
MAKEPATCH 0x81ABD33C
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
# CXrlConnection::Startup
# Spoofing client version 0x4497 == 17559
# ============================================================================
MAKEPATCH 0x81CB8B58
0:
	li %r6, 0x4497
9:

# ============================================================================
# DemandUpdateMgr::ConstructLatestManifestUrl
# Spoofing client version 0x4497 == 17559
# ============================================================================
MAKEPATCH 0x81744334
0:
	li %r6, 0x4497
9:

# ============================================================================
# aXosdUvUXex (string in xam memory space)
# change xosd -> xosc (load retail challenges?)
# ============================================================================
MAKEPATCH 0x8168A4EC
0:
	.long 0x786F7363
9:

# ============================================================================
# aXedlChalrespCU (string in xam memory space)
# change xosd -> xosc (load retail challenges?)
# ============================================================================
MAKEPATCH 0x8168A512
0:
	.long 0x786F7363
9:

# ============================================================================
# XamExecuteChallenge
# NOP out a call to MmGetPhysicalAddress
# ============================================================================
MAKEPATCH 0x8172BDC8
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
# XMsgStartIORequestEx
# Patches out a call to XamDbgPrint
# ============================================================================
MAKEPATCH 0x81761698
0:
	li %r3, 0
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
# XMsgInProcessCall
# Patches out a call to XamDbgPrint
# ============================================================================
MAKEPATCH 0x81761758
0:
	li %r3, 0
9:

# ============================================================================
# XMsgSystemProcessCall
# Patches out a call to XamDbgPrint
# ============================================================================
MAKEPATCH 0x817618D0
0:
	li %r3, 0
9:

# ============================================================================
# aDeviceHarddisk_9 - NULLs out the following string in xam memory space
# \\Device\\Harddisk0\\Partition1\\DEVKIT
# ============================================================================
MAKEPATCH 0x815F3E98
0:
	.long 0x00000000
9:

# ============================================================================
# XampFlashDashOverrideFileName
# Change the string to remove DEVKIT from the path
# \\Device\\Harddisk0\\Partition1\\override\\dash.xex
# ============================================================================
MAKEPATCH 0x815FD9CD
0:
   .string "override\\dash.xex\0"
   .align 2
9:

# ============================================================================
# CXnIp::IpLogonGetStatus
#
# Replaces some functions after XamExecuteChallenge with a call to
# HalReturnToFirmware - 0x4 = power off (hard) HalpRebootSystem
# ============================================================================
MAKEPATCH 0x818800B8
0:
	li %r3, 0x4
	MAKEBRANCHL 0x81d0fe2c
9:

# ============================================================================
# _g_ClientVersion__3U_XBOX_LIBRARY_VERSION__A
# Spoofing client version??? but i'd expect 4497 -> 17559
# ============================================================================
MAKEPATCH 0x81D275A4
0:
	.long 0x44970000
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
# aXboxLiveClient
# Spoofing client version string but i'd expect 0x37353539 -> 17559
# ============================================================================
MAKEPATCH 0x8168447E
0:
	.long 0x37353539
9:

# ============================================================================
# a20174890
# Spoofing client version string but i'd expect 0x37353539 -> 17559
# ============================================================================
MAKEPATCH 0x8167AEF9
0:
	.long 0x37353539
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

# ============================================================================
# DemandUpdateMgr::VerifyManifestBoundRevision
# Ignore manifest version mismatch
# ============================================================================
MAKEPATCH 0x81744598
0:
	MAKEBRANCH 0x817445a4
9:

# ============================================================================
# CXLiveQosHistory::RetrieveConfigSettings
# Ignore hive key error
# ============================================================================
MAKEPATCH 0x81ACCCE0
0:
	MAKEBRANCH 0x81acd038
9:

# ============================================================================
# CLiveHiveTable::ContinueDownload
# ??? branches somewhere else
# ============================================================================
MAKEPATCH 0x8175674C
0:
	MAKEBRANCH 0x81756774
9:

# ============================================================================
# Patches XamUserGetMembershipType
# Gold spoofing????
# ============================================================================
MAKEPATCH 0x817A5488
0:
	nop
	li %r3, 6
9:

# ============================================================================
# Patches XamUserGetMembershipTypeFromXUID
# Gold spoofing????
# ============================================================================
MAKEPATCH 0x817A54E4
0:
	nop
	li %r3, 6
9:

# done with patch section

#============================================================================
.long 0xFFFFFFFF
.end
#============================================================================