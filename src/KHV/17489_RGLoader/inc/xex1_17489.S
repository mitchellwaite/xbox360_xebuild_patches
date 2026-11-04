# ============================================================================
# XEX1, XEX% and XEX- loader support for the 17489 devkit kernel
#
# Lets the kernel load XEX1 executables (the format used by devkit build 1838), XEX%
# executables (build 1746) and XEX- executables (build 1640) alongside XEX2. Include this
# from khv_17489.S, before the patch list terminator, by defining xex1:
#
#     .set xex1, 1
#     .include "khv_17489.S"
#
# How it works
# ------------
# The optional header keys, data descriptors, page descriptors, import tables and
# export tables have the same format in XEX1 and XEX2.
# What differs is SecurityInfo, which grew by 0x1C bytes and had its fields
# shuffled, and where a couple of values live. So the headers are rewritten to
# XEX2 in memory, once, right as they enter XexpVerifyXexHeaders, and everything
# downstream just sees a devkit XEX2.
#
#                       XEX1 (1838)         XEX2 (17489)
#   Size                  +0x000              +0x000      grows by 0x1C
#   ImageSize             +0x004              +0x004
#   Signature             +0x008              +0x008      first word is a marker
#   InfoSize               n/a                +0x108      always 0x174
#   ImageFlags            +0x158              +0x10C      masked, see below
#   LoadAddress           +0x130              +0x110
#   ImageHash             +0x11C              +0x114
#   ImportTableCount      HVI in the image    +0x128      from the 0x103FF header
#   ImportDigest          HVI in the image    +0x12C      computed
#   MediaID               +0x144              +0x140
#   ImageKey              +0x134              +0x150
#   ExportTableAddress    0x10400 header      +0x160
#   HeaderHash            +0x108              +0x164      recomputed
#   GameRegion            +0x154              +0x178
#   AllowedMediaTypes     +0x160              +0x17C
#   PageDescriptorCount   +0x164              +0x180
#   Page descriptors      +0x168              +0x184
#
# Other checks that had to change
# -------------------------------
# Signature: RGLoader already skips the kernel's signature check. The conversion
#            puts a marker in the first word of Signature, which is how the display
#            and key checks tell a converted XEX1 apart. It's in the headers rather
#            than in a global because the same headers can be verified more than once.
# Versions:  HvxResolveImports rejects imports built against anything older than
#            the exporting module's minimum version. On 17489's kernel that's
#            2.0.1861.0, the XEX2 cutover, so every XEX1 fails it. RGLoader already
#            NOPs that check, but its HV hook at 0xB208 stubs those same old imports
#            with li r3, 0, so khv_17489.S also has to skip that. See there.
#
# Page descriptors
# ----------------
# The format is the same but they don't cover the same amount of image. In XEX2 a
# descriptor never goes past a 64KB boundary, and HvxLoadImageData fails anything
# that does. In XEX1 they're per section, and go up to 0x40 pages on Dolphin.exe.
# There isn't room in the headers for more descriptors, so Xex1LoadImageData makes
# an HV call for each 64KB instead.
#
# The hash of an XEX1 is the same SHA(page, descriptor) chain as XEX2, but it covers
# the whole descriptor, and a part of one can't match. So the check is patched out
# at 0x2A578. This also means images aren't verified for XEX2 when xex1 is defined,
# headers still are.
#
# Display
# -------
# D3D from 1838 calls VdSetDisplayMode with flag 0x40000000. On 1838 that writes to
# register 0x602C, but on 17489 it sets bit 0 of 0x7938 instead, and the screen stays
# black even though the title is rendering and the display is scanning out its front
# buffer. Xex1DisplayFlagGate ignores the flag while the running title is an XEX1,
# which it can tell from the marker in Signature.
#
# xam ordinals
# ------------
# xam reshuffled its exports after 1838, so an import can resolve to something else
# entirely. Ordinal 457 was XamCustomSetBannerImage and is now XamGetDefaultImage,
# which traps on the texture pointer and locks up the console in Project Gotham
# Racing 3. xex1RemapOrdinal fixes these up in HvxResolveImports, for xam import tables
# with a 2.0 version older than 1861, which is where XEX2 starts.
#
# The table comes from the export names of 1838's xamd (with its PDB) and 17489's. A few
# functions are gone, and those go to ordinal 1109, which is just li r3, 0; blr. Only
# the names were compared, not the arguments. XexGetProcedureAddress isn't covered.
#
# XEX%
# ----
# The same idea as XEX1, with SecurityInfo growing by 0x30 instead:
#
#                       XEX% (1746)         XEX2 (17489)
#   ImageFlags            +0x144              +0x10C
#   LoadAddress           +0x130              +0x110
#   ImageHash             +0x11C              +0x114
#   ImageKey              +0x134              +0x150
#   HeaderHash            +0x108              +0x164      recomputed
#   AllowedMediaTypes     +0x14C              +0x17C
#   PageDescriptorCount   +0x150              +0x180
#   Page descriptors      +0x154              +0x184
#
# There's no MediaID or GameRegion, so those become zeroes and 0xFFFFFFFF. +0x148 is the
# address of the HVI, not exports. It keeps the XEX1 marker in Signature, because it needs
# the same zero key and display flag handling. A few things only XEX% needs:
#
# Keys:      imports 0x102FF to 0x103FF, build versions 0x201FF to 0x200FF, TLS 0x10504
#            to 0x20104 and stack size 0x10400 to 0x20200, then the directory is sorted
#            again because RtlImageXexHeaderField binary searches it.
# Imports:   the tables have no module numbers or versions. Those get filled in by library
#            name, which breaks the digests, so the chain is rebuilt back to front. Version
#            is 2.0.1746.0, and that's what tells the HV which ordinals these are.
# Ordinals:  anything older than 2.0.1838 is treated as 1746 for now. Kernel ordinals nearly
#            all moved, so that table has every export. xam's only lists what moved. See
#            xex25_ordinals_17489.S. Removed functions go to XeKeysReserved666 and ordinal
#            1109, which are both li r3, 0; blr.
# ME init:   1746's D3D gets its ME init packet from VdGetDefaultMEInitCommand and submits
#            whatever comes back. It's gone on 17489, and returning nothing would leave the
#            GPU's micro engine without one, so it's put back at an empty export slot.
# Headers:   XAPI in these titles gets the headers from +0x50 of the module's loader entry
#            and passes them to RtlImageXexHeaderField. That moved to +0x58, and +0x50 is
#            now the timestamp, so these titles fault at startup. Their imports go to a
#            wrapper at another empty export slot, which swaps it for the real pointer.
# System command buffer: the struct VdGetSystemCommandBuffer fills in is 0x90 bytes on
#            1746 and 1814, and 0x94 on 17489, with a new word at +0x10. D3D reads it in
#            Swap, so these titles misread it and overrun their buffer once the HUD
#            queues one. These imports also go through wrappers at empty export slots.
# Engines:   D3D from 1746 calls VdInitializeEngines with only its version in r3. From 1814
#            on it also passes a callback and microcode pointers, which 17489 uses, so a
#            1746 title faults on whatever's left in those registers. Another wrapper
#            clears them when r3 is just the version, which gets the default microcode.
#
# Xex25Cave holds what only XEX% uses. It's past the 4KB page Xex1Cave is known to run in,
# so a problem with it can only affect XEX%. It's in the same 64KB page, and RGLoader's
# patches at 0x10E0 make image memory executable anyway.
#
# XEX-
# ----
# Build 1640. SecurityInfo grows by 0x44, and nothing in it lines up with later formats:
#
#                       XEX- (1640)         XEX2 (17489)
#   ImageSize             +0x130              +0x004
#   Signature             +0x004              +0x008      all zeroes, first word is the marker
#   HeaderHash            +0x104              +0x164      recomputed
#   ImageHash             +0x118              +0x114      all zeroes
#   LoadAddress           +0x12C              +0x110
#   PageDescriptorCount   +0x13C, 16 bits     +0x180
#   ImageFlags            +0x13E, 16 bits     +0x10C      shifted left by 16
#   Page descriptors      +0x140              +0x184
#
# There's no MediaID, key, region or media types, so those are zeroes, 0xFFFFFFFF, and what the
# 1814 Dolphin.exe has. It keeps the XEX1 marker, for the same reasons XEX% does. As well as that:
#
# Flags:     module flags mean something else. A title is 0x2 here and 0x1 later.
# Exec ID:   0x40006 has the title ID at +8, and XEX2 has it at +C. It's copied, not moved, because
#            XVerifySameFamily in the title still reads +8, and to XEX2 that's just a base version.
# Tables:    import tables are 0x24 bytes, with no VersionMin. Every one is rewritten, and whatever
#            comes after them moves. The HV won't take a table that crosses a page, and they
#            do once they've grown, so these get padding in front of them.
# Libraries: drivers.xex became part of the kernel and xnet.xex part of xam, so those names change,
#            and there are two tables with the same exporter. The version's bottom byte says which
#            library a table was, because the ordinals are that library's. See XEX2D_VERSION.
# Imports:   records are just the ordinal, in an import address slot in the image, with no module
#            byte. The HV rejects those at 0x2AD88, but it's what a data import looks like when
#            that byte is right, and that path does what these need. So the slots get rewritten to
#            00ss oooo with the final 17489 ordinal, just before the first HvxLoadImageData.
#            That's after the image is read and while it's still writable, and it doesn't touch
#            anything other formats run. Versions of 1861 and up skip the HV's remap.
# Ordinals:  xex2d_ordinals_17489.S, as ranges. Anything not in a range goes to the stub.
# Gamma:     D3D copies 256 words from what VdGetDefaultGammaTable returns. It's gone on 17489,
#            so it's put back at an empty export slot. ME init and engines share XEX%'s.
# System command buffer: 0x94 bytes like 17489, which makes it look the same, but the first five
#            words aren't. 1640 has { flag, address, size, front buffer, format } and 17489 has
#            { address, size, front buffer, format, new word }. All three functions need wrappers,
#            and XEX%'s can't be used. On a Xenos D3D only accepts a buffer with a flag of 0.
# Scaler:    17489's VdInitializeScalerCommandBuffer takes the hardware parameters as an extra
#            argument, where 1640's worked them out itself. A wrapper does that, using the
#            same internal function, and passes the stack arguments along one slot up.
# Startup:   these have no TLS or stack size headers. 1640's XexStartExecutable used 64 TLS slots,
#            with any TLS data from the PE's TLS directory, and a stack of SizeOfStackCommit from
#            the PE header. 17489's only looks for the headers, and without them a title gets
#            no TLS slots at all and a 16KB stack. So it does what 1640's did for these.
# GPU addresses: 1640's D3D makes them by clearing the top 3 bits of a virtual address, all over the
#            title. On 17489 the 4KB physical region at 0xE0000000 is 0x1000 further along than
#            that, so the GPU would run and write to the wrong memory. Nothing can fix up that many
#            places, so title allocations that would be 4KB pages get 64KB ones, which don't have an
#            offset. Only for XEX-, and only in the title process.
#
# D3D's read of 0x7FC80F00, which checks for an alpha kit, is only reached on an ASIC ID with the
# top bit set. 17489 returns 0x11, so it isn't. That also picks the Xenos path everywhere else.

# Things that don't need any changes, and why
# -------------------------------------------
# ImageKey:  every encrypted XEX1 checked uses the all-zero devkit key, so the HV has
#            to pick that key for them. The patch at 0x206DC only covers a malformed
#            public key, so a converted XEX1 can still fail the signature check at
#            0x29C14. RGLoader then picks the retail key, so khv_17489.S sends the
#            marker to the zero key.
# Imports:   the chain is hashed the same way in both formats, SHA(table + 4,
#            0x24 + 4 * ImportCount) with each table holding the digest of the
#            next. XEX1 keeps the first digest in the HVI, which is inside the
#            still encrypted image and not available here, so it gets computed
#            from the first table. Note that some tables have padding after the
#            imports which isn't hashed, so TableSize can't be used for this.
# Region:    titles have 0xFFFFFFFF, and system modules have 0 with the region free
#            flag (0x20000000), so both pass the check in HvxCreateImageMapping.
# Module numbers: the kernel's 0x45DC17E0 is the same in 1838, 1888 and 17489. xam's
#            0xFCA15C76 is the same in 6717 and 12611, and the XEX1s use it too.
#
# Making room
# -----------
# SecurityInfo is immediately followed by optional header data, and some XEX1s
# have fewer than 0x1C spare bytes at the end of their headers (SizeOfHeaders
# can't change, it's also the file offset of the image). All of those have a big
# gap before their last optional header though, as imports get aligned. So the
# data between the page descriptors and that last optional header is what moves,
# or everything up to the end of the headers when the gap isn't there. If neither
# has room the headers stay as they are and XexpVerifyXexHeaders rejects them.
# Imports are that last header in every XEX1 which has them, so they don't move,
# which matters because the HV won't take an import table that crosses a page.
#
# The HV also won't take an HvImageInfo which crosses a page. Headers are page
# aligned, so that only rules out SecurityInfo offsets above 0xE84. Real XEX1s
# have it directly after the directory, at about 0xB0.
#
# Limitations
# -----------
# - Only devkit signed XEX1 is covered. There's no retail XEX1 to test against.
# - Patch files (.xexp) won't apply. XEX1 uses header 0x405 and XEX2 uses 0x5FF.
# - Bound paths are still enforced like they are for XEX2, so XEX1 system modules
#   (dash, xam, etc) are only going to load from their own path.
# - XexTitleHash* traps on an import table with padding after the imports. Some XEX1s
#   have those (xshell, AudioConsole, xbdm, ...), but it isn't part of loading them.
# - This only gets an XEX1 loaded. Whether it then runs depends on the kernel and
#   xam APIs it imports behaving like the 1838 versions it was built against.
#
# Supporting older formats
# ------------------------
# XEX? and XEX0 don't have a SecurityInfo at all.
# ============================================================================

# ----------------------------------------------------------------------------
# 17489 specific addresses. Everything that needs to change to retarget this
# patch is in this block.
# ----------------------------------------------------------------------------

# Hook points
.set XexpVerifyXexHeaders_Hook, 0x800A08E0 # lwz r11, 0x10(r31), right after the prolog. r31 = headers
.set XexpLoadXexHeaders_Magic,  0x800A2DE4 # cmplw cr6, r11, r10 on the XEX2 magic
.set XexLoadImageHeaders_Magic, 0x800A0B94 # cmplw cr6, r11, r10 on the XEX2 magic
.set XexpLoadFile_LoadImageData, 0x800A3764 # bl HvxLoadImageData. r26 = headers, r30 = page descriptor
.set VdSetDisplayMode_Flag,     0x800F77C4 # rlwinm. r11, r26, 0, 1, 1. r26 = flags
.set XexStartExecutable_Tls,    0x800A41C8 # beq past KeSetTlsConfigurationProcess. r29 = loader entry, r30 = process, r31 = headers
.set XexStartExecutable_Stack,  0x800A41F4 # mr r4, r3 before KeSetDefaultKernelStackSizeProcess. r3 = the 0x20200 header
.set XEX_START_TLS_SKIP,        0x18       # from the return address of the hook on that beq, to where it goes
.set MmAllocatePhysicalMemoryEx_Protect, 0x800A75F4 # mr r25, r5. r5 = protect flags, LR is already saved

# Kernel functions
.set RtlImageXexHeaderField,    0x800B3530
.set XeCryptSha,                0x801556D8
.set HvxLoadImageData,          0x8009F8F0
.set VdGetSystemCommandBuffer,  0x800F8DD8
.set VdQuerySystemCommandBuffer, 0x800F8C80
.set VdInitializeEngines,       0x800F7F38
.set VdSetSystemCommandBuffer,  0x800F8D30
.set VdInitializeScalerCommandBuffer, 0x801023C8
.set VdpInternalScalerSetup,    0x80101778
.set HalAcquireAnaLock,         0x8008B2A0
.set HalReleaseAnaLock,         0x8008B308
.set KeSetTlsConfigurationProcess, 0x8009A6C0
.set RtlImageNtHeader,          0x800B3388
.set RtlImageDirectoryEntryToData, 0x800B3448

# Kernel variables
.set XexExecutableModuleHandle, 0x802080D4

# HV, in HvxLoadImageData: bne cr6 on the page hash not matching
.set HV_LoadImageData_HashCheck, 0x0002A578

# HV, in HvxResolveImports: slwi r11, r11, 2 on the index into the export table
.set HV_ResolveImports_Index,   0x0002ADC4

# Kernel export table, ordinal 1 is the first entry and values are relative to KernelBase
.set KernelExports,             0x8008002C
.set KernelBase,                0x80040000

# Empty space in the last page of .text, which ends at 0x801C1770. This is past the
# strings in sysroot_hdd.S at 0x801C1850 and RGLoader's patch at 0x801C1774, and is
# in the same 4KB page, so it's known to be mapped executable. Has until 0x801C2000.
.set Xex1Cave, 0x801C1900

# XEX% only, empty up to the data at 0x801D0030. See the top of this file.
.set Xex25Cave, 0x801C2000

# Empty HV space, past RGLoader's FixFuses at 0xB400. Has until 0xC000.
.set Xex1HvCave, 0xB500

# ----------------------------------------------------------------------------
# Format constants, these should not need to change between kernels
# ----------------------------------------------------------------------------
.set XEX_MAGIC_HI,    0x5845
.set XEX_MAGIC_XEX1,  0x5831
.set XEX_MAGIC_XEX2,  0x5832
.set XEX_MAGIC_XEX25, 0x5825
.set XEX_MAGIC_XEX2D, 0x582D

.set XAM_MODULE_NUMBER,    0xFCA15C76
.set KERNEL_MODULE_NUMBER, 0x45DC17E0
.set XBDM_MODULE_NUMBER,   0xECEB8109
.set XEX2_FIRST_BUILD,     1861
.set XEX1_FIRST_BUILD,     1838
.set XEX25_VERSION,        0x2006D200          # 2.0.1746.0
.set XEX2D_VERSION,        0x20074500          # 2.0.1861.k, k = which library's ordinals these are

# Empty slots in 17489's export table, for VdGetDefaultMEInitCommand and the wrappers
.set XEX25_MEINIT_ORDINAL, 757
.set XEX25_HEADERFIELD_ORDINAL, 898
.set XEX25_GETSYSTEMCB_ORDINAL, 903
.set XEX25_QUERYSYSTEMCB_ORDINAL, 908
.set XEX25_INITENGINES_ORDINAL, 910

.set XEX1_INFO_END,   0x168                 # end of the fixed part of XEX1 SecurityInfo
.set XEX1_GROWTH,     0x1C                  # sizeof(xex2::SecurityInfo) - sizeof(xex1::SecurityInfo)
.set XEX25_INFO_END,  0x154                 # end of the fixed part of XEX% SecurityInfo
.set XEX25_GROWTH,    0x30
.set XEX2D_INFO_END,  0x140                 # end of the fixed part of XEX- SecurityInfo
.set XEX2D_GROWTH,    0x44
.set XEX2_INFO_SIZE,  0x174                 # sizeof(xex2::HvImageInfo)

# What the bottom byte of a converted XEX- import table's version means
.set XEX2D_KIND_KERNEL,  0
.set XEX2D_KIND_DRIVERS, 1
.set XEX2D_KIND_XAM,     2
.set XEX2D_KIND_XNET,    3
.set XEX2D_KIND_XBDM,    4                  # same ordinals on 17489
.set XEX2D_KIND_OTHER,   5                  # no module number, the HV fails it with C0000225

# Xex2dFixImports' frame
.set XEX2D_MAX_TABLES,   16
.set XEX2D_OLD,          0x50               # where each table is now
.set XEX2D_NEW,          0x90               # where each table is going
.set XEX2D_KINDS,        0xD0               # kind of each library, by name index
.set XEX2D_NAMES,        0x110              # the new name table
.set XEX2D_MAX_NAMES,    0xC0               # each name grows by at most 4, so this fits in 0x100
.set XEX2D_FRAME,        0x220

# Xex2dInitializeScalerCommandBuffer's frame
.set XEX2D_SCALER_RESULT, 0x74
.set XEX2D_SCALER_REGS,  0x80
.set XEX2D_SCALER_HW,    0xA0               # _HARDWARE_SCALER_PARAMETERS
.set XEX2D_SCALER_FRAME, 0x640

# Copy of XEX1 SecurityInfo +0x108..+0x168, on the stack during the conversion
.set STASH,           0x50
.set STASH_START,     0x108
.set STASH_WORDS,     (XEX1_INFO_END - STASH_START) / 4
.set FRAME_SIZE,      0x100

# ============================================================================
# XEX% only. These come first because Xex1Cave's branches need their addresses.
# ============================================================================
KMAKEPATCH Xex25Cave
0:
   # ------------------------------------------------------------------------
   # Xex25FixHeaders - called by the conversion once there's room in the headers.
   # r1 = the conversion's frame, r31 = headers. Puts the fields into the stash where
   # the XEX1 ones are, so the rest of the conversion doesn't care about the format.
   # Then renames the optional headers and sorts the directory.
   # ------------------------------------------------------------------------
xex25FixHeaders:
   cmplwi   cr6, %r25, XEX2D_GROWTH
   beq      cr6, xex2dFixHeaders
   lwz      %r11, STASH + 0x144 - STASH_START(%r1)
   stw      %r11, STASH + 0x158 - STASH_START(%r1)
   lwz      %r11, STASH + 0x14C - STASH_START(%r1)
   stw      %r11, STASH + 0x160 - STASH_START(%r1)
   lwz      %r11, STASH + 0x150 - STASH_START(%r1)
   stw      %r11, STASH + 0x164 - STASH_START(%r1)
   li       %r11, -1
   stw      %r11, STASH + 0x154 - STASH_START(%r1)
   li       %r11, 0
   stw      %r11, STASH + 0x144 - STASH_START(%r1)
   stw      %r11, STASH + 0x148 - STASH_START(%r1)
   stw      %r11, STASH + 0x14C - STASH_START(%r1)
   stw      %r11, STASH + 0x150 - STASH_START(%r1)

xex25RenameKeys:
   mflr     %r12
   bl       xex25KeysEnd
   .long    0x102FF, 0x103FF
   .long    0x201FF, 0x200FF
   .long    0x10504, 0x20104
   .long    0x10400, 0x20200
xex25KeysEnd:
   mflr     %r7
   mtlr     %r12
   li       %r6, 4
xex25RenameKey:
   lwz      %r9, 0x14(%r31)
   mtctr    %r9
   addi     %r8, %r31, 0x18 - 8
   lwz      %r4, 0(%r7)
   lwz      %r3, 4(%r7)
   addi     %r7, %r7, 8
xex25RenameFind:
   lwzu     %r11, 8(%r8)
   cmplw    cr6, %r11, %r4
   bne      cr6, xex25RenameNext
   stw      %r3, 0(%r8)
xex25RenameNext:
   bdnz     xex25RenameFind
   addic.   %r6, %r6, -1
   bne      xex25RenameKey

   # Sort the directory. It's short and nearly in order already.
xex25Sort:
   li       %r5, 0
   lwz      %r9, 0x14(%r31)
   addi     %r9, %r9, -1
   cmplwi   cr6, %r9, 0
   beqlr    cr6
   mtctr    %r9
   addi     %r8, %r31, 0x18
xex25SortLoop:
   ld       %r11, 0(%r8)
   ld       %r10, 8(%r8)
   cmpld    cr6, %r11, %r10
   ble      cr6, xex25SortNext
   std      %r10, 0(%r8)
   std      %r11, 8(%r8)
   li       %r5, 1
xex25SortNext:
   addi     %r8, %r8, 8
   bdnz     xex25SortLoop
   cmplwi   cr6, %r5, 0
   bne      cr6, xex25Sort
   blr

   # ------------------------------------------------------------------------
   # Xex25FixImports - fills in each import table's module number and versions, then
   # rebuilds the digest chain from the last table back. The conversion computes
   # ImportDigest from the first table afterwards, the same as for XEX1.
   #
   # r26 = import descriptor or zero, r29 = SizeOfHeaders, r31 = headers. Uses r24, which
   # the conversion has finished with. Stops if a table isn't inside the headers, and
   # the HV then fails the title on its digest.
   #
   # r3 = next table, r4 = end of the headers, r5 = library names, r8 = this table
   # ------------------------------------------------------------------------
xex25FixImports:
   cmplwi   cr6, %r25, XEX2D_GROWTH
   beq      cr6, xex2dFixImports
   cmplwi   cr6, %r26, 0
   beqlr    cr6
   lwz      %r24, 8(%r26)
   cmplwi   cr6, %r24, 0
   beqlr    cr6
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -0x60(%r1)

   add      %r4, %r31, %r29
   lwz      %r3, 4(%r26)
   cmplw    cr6, %r3, %r29
   bgt      cr6, xex25ImportsDone
   addi     %r5, %r26, 0xC
   add      %r8, %r5, %r3
   mtctr    %r24
xex25ImportTable:
   subf     %r11, %r8, %r4
   cmpwi    cr6, %r11, 0x28
   blt      cr6, xex25ImportsDone
   lwz      %r3, 0(%r8)
   cmplwi   cr6, %r3, 0x28
   blt      cr6, xex25ImportsDone
   cmplw    cr6, %r3, %r11
   bgt      cr6, xex25ImportsDone
   lhz      %r6, 0x26(%r8)
   slwi     %r6, %r6, 2
   addi     %r6, %r6, 0x28
   cmplw    cr6, %r6, %r3
   bgt      cr6, xex25ImportsDone
   add      %r3, %r8, %r3

   # Names are null terminated and aligned to 4 bytes
   lbz      %r6, 0x25(%r8)
   mr       %r10, %r5
xex25FindName:
   cmplwi   cr6, %r6, 0
   beq      cr6, xex25HaveName
xex25SkipName:
   cmplw    cr6, %r10, %r4
   bge      cr6, xex25ImportsDone
   lbz      %r11, 0(%r10)
   addi     %r10, %r10, 1
   cmplwi   cr6, %r11, 0
   bne      cr6, xex25SkipName
   addi     %r10, %r10, 3
   clrrwi   %r10, %r10, 2
   addi     %r6, %r6, -1
   b        xex25FindName
xex25HaveName:
   addi     %r11, %r10, 3
   cmplw    cr6, %r11, %r4
   bge      cr6, xex25ImportsDone

   # Telling xam.xex, xboxkrnl.exe and xbdm.xex apart. A module number stays zero for
   # any other library, so the HV fails that title with C0000225.
   lbz      %r11, 0(%r10)
   cmplwi   cr6, %r11, 0x78                 # x
   bne      cr6, xex25NextTable
   lhz      %r10, 1(%r10)
   cmplwi   cr6, %r10, 0x616D               # am
   lis      %r11, XAM_MODULE_NUMBER@h
   ori      %r11, %r11, XAM_MODULE_NUMBER@l
   beq      cr6, xex25HaveModule
   cmplwi   cr6, %r10, 0x626F               # bo
   lis      %r11, KERNEL_MODULE_NUMBER@h
   ori      %r11, %r11, KERNEL_MODULE_NUMBER@l
   beq      cr6, xex25HaveModule
   cmplwi   cr6, %r10, 0x6264               # bd
   lis      %r11, XBDM_MODULE_NUMBER@h
   ori      %r11, %r11, XBDM_MODULE_NUMBER@l
   bne      cr6, xex25NextTable
xex25HaveModule:
   stw      %r11, 0x18(%r8)
   lis      %r11, XEX25_VERSION@h
   ori      %r11, %r11, XEX25_VERSION@l
   stw      %r11, 0x1C(%r8)
   stw      %r11, 0x20(%r8)
xex25NextTable:
   mr       %r8, %r3
   bdnz     xex25ImportTable

   # Each table holds the digest of the next. r24 = index of the table to hash.
xex25Chain:
   addic.   %r24, %r24, -1
   beq      xex25ImportsDone
   lwz      %r3, 4(%r26)
   add      %r8, %r26, %r3
   addi     %r8, %r8, 0xC
   mtctr    %r24
xex25ChainWalk:
   mr       %r9, %r8
   lwz      %r11, 0(%r8)
   add      %r8, %r8, %r11
   bdnz     xex25ChainWalk
   lhz      %r6, 0x26(%r8)
   slwi     %r6, %r6, 2
   addi     %r9, %r9, 4
   addi     %r3, %r8, 4
   li       %r4, 0x24
   addi     %r5, %r8, 0x28
   li       %r7, 0
   li       %r8, 0
   li       %r10, 0x14
   KMAKEBRANCHL XeCryptSha
   b        xex25Chain

xex25ImportsDone:
   addi     %r1, %r1, 0x60
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

   # ------------------------------------------------------------------------
   # VdGetDefaultMEInitCommand, the same as 1746's. r3 = buffer, r4 = its size in words.
   # Returns the number of words written, or zero if the buffer's too small.
   # ------------------------------------------------------------------------
xex25GetDefaultMEInitCommand:
   cmplwi   cr6, %r4, 0x40
   bge      cr6, xex25MEInitWrite
   li       %r3, 0
   blr
xex25MEInitWrite:
   lis      %r11, 0xC011
   ori      %r11, %r11, 0x4800
   stw      %r11, 0(%r3)
   li       %r11, 0x3FF
   stw      %r11, 4(%r3)
   li       %r11, 0
   stw      %r11, 8(%r3)
   addi     %r10, %r3, 0xC
   stw      %r11, 0(%r10)
   li       %r9, 8
   mtctr    %r9
   li       %r9, 0
xex25MEInitLoop:
   stwu     %r9, 4(%r10)
   addi     %r9, %r9, 0x80
   bdnz     xex25MEInitLoop
   li       %r9, 0x800
   stwu     %r9, 4(%r10)
   li       %r9, 7
   stwu     %r9, 4(%r10)
   li       %r9, 5
   mtctr    %r9
xex25MEInitZero:
   stwu     %r11, 4(%r10)
   bdnz     xex25MEInitZero
   sync
   subf     %r3, %r3, %r10
   addi     %r3, %r3, 4
   srawi    %r3, %r3, 2
   blr

   # ------------------------------------------------------------------------
   # RtlImageXexHeaderField for titles older than 1838. r3 = headers, r4 = key. These titles
   # read the headers from +0x50 of the module's loader entry, where 17489 has the
   # timestamp, so r3 is that value and the real function faults on it. Anything else
   # passes straight through.
   # ------------------------------------------------------------------------
xex25ImageXexHeaderField:
   lis      %r11, XexExecutableModuleHandle@ha
   lwz      %r11, XexExecutableModuleHandle@l(%r11)
   cmplwi   cr6, %r11, 0
   beq      cr6, xex25HeaderFieldCall
   lwz      %r10, 0x50(%r11)
   cmplw    cr6, %r3, %r10
   bne      cr6, xex25HeaderFieldCall
   lwz      %r3, 0x58(%r11)
xex25HeaderFieldCall:
   KMAKEBRANCH RtlImageXexHeaderField

   # ------------------------------------------------------------------------
   # VdGetSystemCommandBuffer and VdQuerySystemCommandBuffer for titles older than 1838.
   # r3 = the title's 0x90 byte struct, which Query allows to be null. Calls the real
   # function with a 0x94 byte one, then copies it back without the word at +0x10.
   # ------------------------------------------------------------------------
xex25GetSystemCommandBuffer:
   lis      %r12, VdGetSystemCommandBuffer@h
   ori      %r12, %r12, VdGetSystemCommandBuffer@l
   b        xex25SystemCommandBuffer
xex25QuerySystemCommandBuffer:
   lis      %r12, VdQuerySystemCommandBuffer@h
   ori      %r12, %r12, VdQuerySystemCommandBuffer@l
xex25SystemCommandBuffer:
   mflr     %r11
   stw      %r11, -8(%r1)
   std      %r31, -0x10(%r1)
   stwu     %r1, -0x100(%r1)
   mr       %r31, %r3
   cmplwi   cr6, %r3, 0
   beq      cr6, xex25SystemCommandCall
   addi     %r3, %r1, 0x50
xex25SystemCommandCall:
   mtctr    %r12
   bctrl
   cmplwi   cr6, %r31, 0
   beq      cr6, xex25SystemCommandDone
   addi     %r10, %r1, 0x50 - 4
   addi     %r9, %r31, -4
   li       %r8, 4
   mtctr    %r8
xex25SystemCommandHead:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex25SystemCommandHead
   addi     %r10, %r10, 4
   li       %r8, 0x20
   mtctr    %r8
xex25SystemCommandTail:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex25SystemCommandTail
xex25SystemCommandDone:
   addi     %r1, %r1, 0x100
   lwz      %r11, -8(%r1)
   mtlr     %r11
   ld       %r31, -0x10(%r1)
   blr

   # ------------------------------------------------------------------------
   # VdInitializeEngines for titles older than 1838. 1746's D3D only passes its version,
   # as 0x6D2 in r3. 1814's has the build in the top half and sets the rest, so it
   # passes straight through. r4 is a callback and r6 and r7 are microcode, and 17489
   # skips the callback and uses its own microcode when they're zero.
   # ------------------------------------------------------------------------
xex25InitializeEngines:
   lis      %r11, 1
   cmplw    cr6, %r3, %r11
   bge      cr6, xex25InitializeEnginesCall
   li       %r4, 0
   li       %r5, 0
   li       %r6, 0
   li       %r7, 0
xex25InitializeEnginesCall:
   KMAKEBRANCH VdInitializeEngines

   # ------------------------------------------------------------------------
   # Xex2dFixHeaders - the same job as Xex25FixHeaders, for XEX-. The ordering matters here,
   # because the stash is XEX-'s layout until this is done and the fields overlap.
   # ------------------------------------------------------------------------
xex2dFixHeaders:
   lwz      %r5, STASH + 0x12C - STASH_START(%r1)
   lwz      %r6, STASH + 0x130 - STASH_START(%r1)
   lhz      %r7, STASH + 0x13C - STASH_START(%r1)
   lhz      %r4, STASH + 0x13E - STASH_START(%r1)

   # ImageHash, back to front
   addi     %r9, %r1, STASH + 0x118 + 0x14 - STASH_START
   li       %r8, 5
   mtctr    %r8
xex2dHashMove:
   lwzu     %r11, -4(%r9)
   stw      %r11, 4(%r9)
   bdnz     xex2dHashMove

   stw      %r5, STASH + 0x130 - STASH_START(%r1)
   stw      %r6, 4(%r28)
   slwi     %r4, %r4, 16
   stw      %r4, STASH + 0x158 - STASH_START(%r1)
   stw      %r7, STASH + 0x164 - STASH_START(%r1)

   # Key and MediaID. Those two versions and the page descriptors were all that was in this space.
   addi     %r9, %r1, STASH + 0x134 - 4 - STASH_START
   li       %r8, 8
   mtctr    %r8
   li       %r11, 0
xex2dClearStash:
   stwu     %r11, 4(%r9)
   bdnz     xex2dClearStash
   stw      %r11, 0xC(%r28)                 # the XEX- marker only goes here if imports convert
   li       %r11, -1
   stw      %r11, STASH + 0x154 - STASH_START(%r1)
   lis      %r11, 1
   ori      %r11, %r11, 0x605
   stw      %r11, STASH + 0x160 - STASH_START(%r1)

   # Module flags. Other bits are the same. There's no flag for a system process any more.
   lwz      %r11, 4(%r31)
   rlwinm   %r10, %r11, 31, 31, 31          # 2 (title) to 1
   rlwimi   %r10, %r11, 1, 28, 28           # 4 (DLL) to 8
   rlwimi   %r10, %r11, 31, 29, 29          # 8 (debugger) to 4
   rlwimi   %r10, %r11, 0, 0, 27
   stw      %r10, 4(%r31)

   # 0x40006 is still in the directory by offset here. It's 0x18 bytes, and all that's in the
   # three fields after the title ID on every file checked is zero.
   lwz      %r9, 0x14(%r31)
   mtctr    %r9
   addi     %r8, %r31, 0x18 - 8
   lis      %r4, 4
   ori      %r4, %r4, 6
xex2dFindExecutionId:
   lwzu     %r11, 8(%r8)
   cmplw    cr6, %r11, %r4
   bne      cr6, xex2dFindExecutionIdNext
   lwz      %r11, 4(%r8)
   cmplw    cr6, %r11, %r27                 # where SecurityInfo will end
   blt      cr6, xex25RenameKeys
   addi     %r10, %r11, 0x18
   cmplw    cr6, %r10, %r29
   bgt      cr6, xex25RenameKeys
   andi.    %r10, %r11, 3
   bne      xex25RenameKeys
   add      %r11, %r11, %r31
   lwz      %r10, 8(%r11)
   stw      %r10, 0xC(%r11)
   li       %r10, 0
   stw      %r10, 0x10(%r11)
   stw      %r10, 0x14(%r11)
   b        xex25RenameKeys
xex2dFindExecutionIdNext:
   bdnz     xex2dFindExecutionId
   b        xex25RenameKeys

   # ------------------------------------------------------------------------
   # Xex2dFixImports - rewrites the import descriptor from XEX-'s layout to XEX2's. The
   # conversion computes ImportDigest from the first table afterwards.
   #
   # r26 = import descriptor or zero, r29 = SizeOfHeaders, r28 = SecurityInfo, r31 = headers.
   # Uses r24, r25 and r27, which the conversion has finished with. Everything is checked before
   # anything gets written. If it doesn't fit or doesn't make sense the tables stay how they
   # are, there's no XEX- marker to touch the image, and the HV fails the title on its digest.
   #
   # r24 = tables, r25 = end of the headers, r27 = size of the new name table
   # ------------------------------------------------------------------------
xex2dFixImports:
   cmplwi   cr6, %r26, 0
   beqlr    cr6
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -XEX2D_FRAME(%r1)

   add      %r25, %r31, %r29
   subf     %r11, %r26, %r25
   cmplwi   cr6, %r11, 0xC
   blt      cr6, xex2dImportsBail
   andi.    %r10, %r26, 3
   bne      xex2dImportsBail
   lwz      %r24, 8(%r26)
   addi     %r10, %r24, -1
   cmplwi   cr6, %r10, XEX2D_MAX_TABLES
   bge      cr6, xex2dImportsBail
   lwz      %r9, 4(%r26)
   cmplwi   cr6, %r9, XEX2D_MAX_NAMES
   bgt      cr6, xex2dImportsBail
   andi.    %r10, %r9, 3
   bne      xex2dImportsBail
   addi     %r10, %r9, 0xC
   cmplw    cr6, %r10, %r11
   bgt      cr6, xex2dImportsBail

   # Build the new name table on the stack. Names are null terminated and aligned to 4 bytes.
   # r5 = old name, r6 = end of the old names, r7 = new name, r8 = kind
   addi     %r5, %r26, 0xC
   add      %r6, %r5, %r9
   addi     %r7, %r1, XEX2D_NAMES
   addi     %r8, %r1, XEX2D_KINDS - 4
   mtctr    %r24
xex2dNameLoop:
   cmplw    cr6, %r5, %r6
   bge      cr6, xex2dImportsBail
   lwz      %r11, 0(%r5)
   lis      %r10, 0x7862
   ori      %r10, %r10, 0x6F78              # xbox
   cmplw    cr6, %r11, %r10
   li       %r4, XEX2D_KIND_KERNEL
   beq      cr6, xex2dCopyName
   lis      %r10, 0x6472
   ori      %r10, %r10, 0x6976              # driv
   cmplw    cr6, %r11, %r10
   beq      cr6, xex2dNameDrivers
   lis      %r10, 0x7861
   ori      %r10, %r10, 0x6D2E              # xam.
   cmplw    cr6, %r11, %r10
   li       %r4, XEX2D_KIND_XAM
   beq      cr6, xex2dCopyName
   lis      %r10, 0x786E
   ori      %r10, %r10, 0x6574              # xnet
   cmplw    cr6, %r11, %r10
   beq      cr6, xex2dNameXnet
   lis      %r10, 0x7862
   ori      %r10, %r10, 0x646D              # xbdm
   cmplw    cr6, %r11, %r10
   li       %r4, XEX2D_KIND_XBDM
   beq      cr6, xex2dCopyName
   li       %r4, XEX2D_KIND_OTHER
xex2dCopyName:
   # Words, up to and including the one with the terminator. r3 is scratch.
   lwz      %r11, 0(%r5)
   addi     %r5, %r5, 4
   stw      %r11, 0(%r7)
   addi     %r7, %r7, 4
   li       %r3, 4
xex2dCopyNameByte:
   rlwinm.  %r10, %r11, 8, 24, 31
   beq      xex2dNameDone
   rotlwi   %r11, %r11, 8
   addic.   %r3, %r3, -1
   bne      xex2dCopyNameByte
   cmplw    cr6, %r5, %r6
   blt      cr6, xex2dCopyName
   b        xex2dImportsBail
xex2dNameDrivers:
   li       %r4, XEX2D_KIND_DRIVERS
   lis      %r10, 0x7862
   ori      %r10, %r10, 0x6F78              # xbox
   stw      %r10, 0(%r7)
   lis      %r10, 0x6B72
   ori      %r10, %r10, 0x6E6C              # krnl
   stw      %r10, 4(%r7)
   lis      %r10, 0x2E65
   ori      %r10, %r10, 0x7865              # .exe
   stw      %r10, 8(%r7)
   li       %r10, 0
   stw      %r10, 0xC(%r7)
   addi     %r7, %r7, 0x10
   b        xex2dSkipName
xex2dNameXnet:
   li       %r4, XEX2D_KIND_XNET
   lis      %r10, 0x7861
   ori      %r10, %r10, 0x6D2E              # xam.
   stw      %r10, 0(%r7)
   lis      %r10, 0x7865
   ori      %r10, %r10, 0x7800              # xex
   stw      %r10, 4(%r7)
   addi     %r7, %r7, 8
xex2dSkipName:
   # On to the next old name, without keeping any of this one
   lwz      %r11, 0(%r5)
   addi     %r5, %r5, 4
   li       %r3, 4
xex2dSkipNameByte:
   rlwinm.  %r10, %r11, 8, 24, 31
   beq      xex2dNameDone
   rotlwi   %r11, %r11, 8
   addic.   %r3, %r3, -1
   bne      xex2dSkipNameByte
   cmplw    cr6, %r5, %r6
   blt      cr6, xex2dSkipName
   b        xex2dImportsBail
xex2dNameDone:
   stwu     %r4, 4(%r8)
   bdnz     xex2dNameLoop

   # The names have to take up all of the old name table. They can shrink by 4 at most, because
   # that's what the back to front move below relies on. Real files only ever have one xnet.xex.
   cmplw    cr6, %r5, %r6
   bne      cr6, xex2dImportsBail
   addi     %r27, %r1, XEX2D_NAMES
   subf     %r27, %r27, %r7
   addi     %r11, %r27, 4
   cmplw    cr6, %r11, %r9
   blt      cr6, xex2dImportsBail

   # Check each table, and work out where it's going. r3 = old table, r4 = new table,
   # r5 = old size, r6 = bytes the HV reads, starting from its +4
   addi     %r3, %r26, 0xC
   add      %r4, %r3, %r27
   add      %r3, %r3, %r9
   addi     %r7, %r1, XEX2D_OLD - 4
   addi     %r8, %r1, XEX2D_NEW - 4
   mtctr    %r24
xex2dPlanLoop:
   subf     %r11, %r3, %r25
   cmpwi    cr6, %r11, 0x24
   blt      cr6, xex2dImportsBail
   lwz      %r5, 0(%r3)
   cmplwi   cr6, %r5, 0x24
   blt      cr6, xex2dImportsBail
   cmplw    cr6, %r5, %r11
   bgt      cr6, xex2dImportsBail
   andi.    %r10, %r5, 3
   bne      xex2dImportsBail
   lhz      %r6, 0x22(%r3)
   slwi     %r6, %r6, 2
   addi     %r6, %r6, 0x24
   cmplw    cr6, %r6, %r5
   bgt      cr6, xex2dImportsBail
   lbz      %r10, 0x21(%r3)
   cmplw    cr6, %r10, %r24
   bge      cr6, xex2dImportsBail

   # The same test as the HV's. If it won't fit in what's left of this page, it starts a new one.
   addi     %r11, %r4, 4
   clrlwi   %r11, %r11, 20
   add      %r11, %r11, %r6
   cmplwi   cr6, %r11, 0x1000
   ble      cr6, xex2dPlanFits
   cmplwi   cr6, %r6, 0x1000
   bgt      cr6, xex2dImportsBail
   addi     %r4, %r4, 0xFFF + 4
   clrrwi   %r4, %r4, 12
   addi     %r4, %r4, -4
xex2dPlanFits:
   stwu     %r3, 4(%r7)
   stwu     %r4, 4(%r8)
   add      %r3, %r3, %r5
   add      %r4, %r4, %r5
   addi     %r4, %r4, 4
   bdnz     xex2dPlanLoop

   # r3 = end of the old tables, r4 = end of the new ones, r5 = end of the old descriptor,
   # r6 = how much they grow. The space it needs has to be free at the end of the headers.
   lwz      %r11, 0(%r26)
   add      %r5, %r26, %r11
   cmplw    cr6, %r3, %r5
   bgt      cr6, xex2dImportsBail
   cmplw    cr6, %r5, %r25
   bgt      cr6, xex2dImportsBail
   subf     %r6, %r3, %r4
   subf     %r10, %r6, %r25
   cmplw    cr6, %r10, %r5
   blt      cr6, xex2dImportsBail
   mr       %r8, %r25
xex2dCheckFree:
   cmplw    cr6, %r8, %r10
   ble      cr6, xex2dCheckFreeDone
   lwzu     %r11, -4(%r8)
   cmplwi   cr6, %r11, 0
   beq      cr6, xex2dCheckFree
   b        xex2dImportsBail
xex2dCheckFreeDone:

   # From here on it can't fail. Move whatever comes after the imports, back to front.
   mr       %r8, %r25
xex2dMoveAfter:
   cmplw    cr6, %r10, %r5
   ble      cr6, xex2dMoveAfterDone
   lwzu     %r11, -4(%r10)
   stwu     %r11, -4(%r8)
   b        xex2dMoveAfter
xex2dMoveAfterDone:

   # And point the directory at it
   lwz      %r9, 0x14(%r31)
   mtctr    %r9
   addi     %r8, %r31, 0x18 - 8
   subf     %r7, %r31, %r5
xex2dFixDir:
   lwzu     %r11, 8(%r8)
   clrlwi   %r11, %r11, 24
   cmplwi   cr6, %r11, 1
   ble      cr6, xex2dFixDirNext
   lwz      %r11, 4(%r8)
   cmplw    cr6, %r11, %r7
   blt      cr6, xex2dFixDirNext
   add      %r11, %r11, %r6
   stw      %r11, 4(%r8)
xex2dFixDirNext:
   bdnz     xex2dFixDir

   # The descriptor's new size. r4 is where the next table would start, for the loop below.
   lwz      %r11, 0(%r26)
   add      %r11, %r11, %r6
   stw      %r11, 0(%r26)

   # Back to front, so nothing gets overwritten before it's moved. Only the first table can
   # move down, by 4 at most, and that still leaves its addresses moving up.
   # r3 = table index * 4, r4 = end of this new table, r5 = old table, r6 = new table
   slwi     %r3, %r24, 2
xex2dTableLoop:
   addi     %r3, %r3, -4
   addi     %r11, %r1, XEX2D_OLD
   lwzx     %r5, %r11, %r3
   addi     %r11, %r1, XEX2D_NEW
   lwzx     %r6, %r11, %r3
   lhz      %r7, 0x22(%r5)
   lbz      %r8, 0x21(%r5)

   # Addresses
   slwi     %r9, %r7, 2
   add      %r10, %r5, %r9
   addi     %r10, %r10, 0x24
   add      %r12, %r6, %r9
   addi     %r12, %r12, 0x28
   cmplwi   cr6, %r7, 0
   beq      cr6, xex2dAddressesDone
   mtctr    %r7
xex2dAddressLoop:
   lwzu     %r11, -4(%r10)
   stwu     %r11, -4(%r12)
   bdnz     xex2dAddressLoop
xex2dAddressesDone:

   # Anything between the addresses and the next table is padding
   add      %r12, %r6, %r9
   addi     %r12, %r12, 0x28
   li       %r11, 0
xex2dPadLoop:
   cmplw    cr6, %r12, %r4
   bge      cr6, xex2dPadDone
   stw      %r11, 0(%r12)
   addi     %r12, %r12, 4
   b        xex2dPadLoop
xex2dPadDone:

   # NextImportDigest is zero until the chain's rebuilt
   stw      %r11, 4(%r6)
   stw      %r11, 8(%r6)
   stw      %r11, 0xC(%r6)
   stw      %r11, 0x10(%r6)
   stw      %r11, 0x14(%r6)

   subf     %r10, %r6, %r4
   stw      %r10, 0(%r6)
   sth      %r7, 0x26(%r6)
   sth      %r8, 0x24(%r6)                  # Unused is the top byte, ModuleIndex the bottom one

   # Module number and version, by what the library was
   slwi     %r8, %r8, 2
   addi     %r11, %r1, XEX2D_KINDS
   lwzx     %r8, %r11, %r8
   li       %r11, 0
   cmplwi   cr6, %r8, XEX2D_KIND_XAM
   lis      %r10, KERNEL_MODULE_NUMBER@h
   ori      %r10, %r10, KERNEL_MODULE_NUMBER@l
   blt      cr6, xex2dHaveModule
   cmplwi   cr6, %r8, XEX2D_KIND_XBDM
   lis      %r10, XAM_MODULE_NUMBER@h
   ori      %r10, %r10, XAM_MODULE_NUMBER@l
   blt      cr6, xex2dHaveModule
   lis      %r10, XBDM_MODULE_NUMBER@h
   ori      %r10, %r10, XBDM_MODULE_NUMBER@l
   beq      cr6, xex2dHaveModule
   mr       %r10, %r11
xex2dHaveModule:
   stw      %r10, 0x18(%r6)
   lis      %r10, XEX2D_VERSION@h
   ori      %r10, %r10, XEX2D_VERSION@l
   or       %r10, %r10, %r8
   stw      %r10, 0x1C(%r6)
   stw      %r10, 0x20(%r6)

   mr       %r4, %r6
   cmplwi   cr6, %r3, 0
   bne      cr6, xex2dTableLoop

   # The first table's the one place padding can't go after a table, so it goes on the names.
   # r6 = first table, so r4 - names is how much the name table takes up.
   addi     %r10, %r26, 0xC
   subf     %r11, %r10, %r6
   stw      %r11, 4(%r26)
   addi     %r9, %r1, XEX2D_NAMES - 4
   addi     %r10, %r10, -4
   srwi     %r8, %r11, 2
   mtctr    %r8
   srwi     %r27, %r27, 2
xex2dNamesLoop:
   li       %r11, 0
   cmplwi   cr6, %r27, 0
   beq      cr6, xex2dNamesPad
   lwzu     %r11, 4(%r9)
   addi     %r27, %r27, -1
xex2dNamesPad:
   stwu     %r11, 4(%r10)
   bdnz     xex2dNamesLoop

   lis      %r11, XEX_MAGIC_HI
   ori      %r11, %r11, XEX_MAGIC_XEX2D
   stw      %r11, 0xC(%r28)

   # Each table holds the digest of the next, the same as XEX%
   addi     %r1, %r1, XEX2D_FRAME
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -0x60(%r1)
   b        xex25Chain

xex2dImportsBail:
   addi     %r1, %r1, XEX2D_FRAME
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

   # ------------------------------------------------------------------------
   # Xex2dFixSlots - writes the final 17489 ordinal and the module index to every import
   # slot in the image, so the HV takes them as data imports. Only for a converted XEX-, once,
   # before its first HvxLoadImageData. r3 = loader entry, r4 = headers.
   #
   # r3 = ranges or zero, r4 = module index << 16, r5 = load address, r6 = image size,
   # r7 = table, r8 = tables left, r9 = this address, r12 = stub, r31 = image
   # ------------------------------------------------------------------------
xex2dFixSlots:
   mflr     %r12
   stw      %r12, -8(%r1)
   std      %r29, -0x20(%r1)
   std      %r30, -0x10(%r1)
   std      %r31, -0x18(%r1)
   stwu     %r1, -0x70(%r1)
   lwz      %r31, 0x1C(%r3)
   mr       %r30, %r4
   mr       %r3, %r4
   lis      %r4, 1
   ori      %r4, %r4, 0x3FF
   KMAKEBRANCHL RtlImageXexHeaderField
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dFixSlotsDone
   lwz      %r11, 0x10(%r30)
   lwz      %r5, 0x110(%r11)
   lwz      %r6, 4(%r11)
   lwz      %r8, 8(%r3)
   lwz      %r7, 4(%r3)
   add      %r7, %r7, %r3
   addi     %r7, %r7, 0xC
xex2dSlotTable:
   lhz      %r9, 0x26(%r7)
   cmplwi   cr6, %r9, 0
   beq      cr6, xex2dSlotNextTable
   mtctr    %r9
   lbz      %r4, 0x25(%r7)
   slwi     %r4, %r4, 16
   addi     %r9, %r7, 0x24

   # Which ordinals these are. xbdm's are the same numbers, so it doesn't have a table.
   lbz      %r10, 0x1F(%r7)
   li       %r12, XEX2D_KERNEL_STUB
   cmplwi   cr6, %r10, XEX2D_KIND_XAM
   blt      cr6, xex2dSlotStub
   li       %r12, XEX2D_XAM_STUB
xex2dSlotStub:
   li       %r3, 0
   cmplwi   cr6, %r10, XEX2D_KIND_XBDM
   bge      cr6, xex2dSlotHaveRanges
   bcl      20, 31, xex2dSlotHere
xex2dSlotHere:
   mflr     %r3
   slwi     %r10, %r10, 1
   addi     %r10, %r10, xex2dRangeOffsets - xex2dSlotHere
   lhzx     %r10, %r3, %r10
   add      %r3, %r3, %r10
xex2dSlotHaveRanges:

xex2dSlotLoop:
   # r11 = offset of the slot in the image. A bad one gets left alone, for the HV to reject.
   lwzu     %r11, 4(%r9)
   subf     %r11, %r5, %r11
   cmplw    cr6, %r11, %r6
   bge      cr6, xex2dSlotNext
   andi.    %r10, %r11, 3
   bne      xex2dSlotNext

   # Only a plain ordinal is known to mean anything. Something else might otherwise pass the
   # HV's check with the wrong meaning, so make sure it doesn't.
   lwzx     %r10, %r31, %r11
   srwi.    %r30, %r10, 16
   beq      xex2dSlotOrdinal
   li       %r10, -1
   b        xex2dSlotWrite

xex2dSlotOrdinal:
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dSlotHave
   mr       %r30, %r3
xex2dSlotRange:
   lhz      %r0, 4(%r30)
   cmplwi   cr6, %r0, 0
   beq      cr6, xex2dSlotUseStub
   lhz      %r29, 0(%r30)
   subf     %r29, %r29, %r10
   cmplw    cr6, %r29, %r0
   blt      cr6, xex2dSlotInRange
   addi     %r30, %r30, 6
   b        xex2dSlotRange
xex2dSlotInRange:
   lhz      %r10, 2(%r30)
   add      %r10, %r10, %r29
   b        xex2dSlotHave
xex2dSlotUseStub:
   mr       %r10, %r12
xex2dSlotHave:
   or       %r10, %r10, %r4
xex2dSlotWrite:
   stwx     %r10, %r31, %r11
xex2dSlotNext:
   bdnz     xex2dSlotLoop

xex2dSlotNextTable:
   lwz      %r11, 0(%r7)
   add      %r7, %r7, %r11
   addic.   %r8, %r8, -1
   bne      xex2dSlotTable

xex2dFixSlotsDone:
   addi     %r1, %r1, 0x70
   lwz      %r12, -8(%r1)
   mtlr     %r12
   ld       %r29, -0x20(%r1)
   ld       %r30, -0x10(%r1)
   ld       %r31, -0x18(%r1)
   blr

   # By library kind, from xex2dSlotHere
xex2dRangeOffsets:
   .short   xex2dKernelRanges - xex2dSlotHere
   .short   xex2dDriversRanges - xex2dSlotHere
   .short   xex2dXamRanges - xex2dSlotHere
   .short   xex2dXnetRanges - xex2dSlotHere

   # ------------------------------------------------------------------------
   # VdGetDefaultGammaTable, gone by 1746. Returns 256 words of 10 bits for each channel.
   # ------------------------------------------------------------------------
xex2dGetDefaultGammaTable:
   mflr     %r12
   bcl      20, 31, xex2dGammaHere
xex2dGammaHere:
   mflr     %r3
   mtlr     %r12
   addi     %r3, %r3, xex2dGammaTable - xex2dGammaHere
   blr

   # ------------------------------------------------------------------------
   # VdGetSystemCommandBuffer and VdQuerySystemCommandBuffer for 1640. r3 = the title's struct,
   # which Query allows to be null, r4 = where to put the identifier. See the top of this file.
   # ------------------------------------------------------------------------
xex2dGetSystemCommandBuffer:
   lis      %r12, VdGetSystemCommandBuffer@h
   ori      %r12, %r12, VdGetSystemCommandBuffer@l
   b        xex2dSystemCommandBuffer
xex2dQuerySystemCommandBuffer:
   lis      %r12, VdQuerySystemCommandBuffer@h
   ori      %r12, %r12, VdQuerySystemCommandBuffer@l
xex2dSystemCommandBuffer:
   mflr     %r11
   stw      %r11, -8(%r1)
   std      %r31, -0x10(%r1)
   stwu     %r1, -0x100(%r1)
   mr       %r31, %r3
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dSystemCommandCall
   addi     %r3, %r1, 0x50
xex2dSystemCommandCall:
   mtctr    %r12
   bctrl
   cmplwi   cr6, %r31, 0
   beq      cr6, xex2dSystemCommandDone
   li       %r8, 0
   stw      %r8, 0(%r31)
   addi     %r10, %r1, 0x50 - 4
   mr       %r9, %r31
   li       %r8, 4
   mtctr    %r8
xex2dSystemCommandHead:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex2dSystemCommandHead
   addi     %r10, %r10, 4
   li       %r8, 0x20
   mtctr    %r8
xex2dSystemCommandTail:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex2dSystemCommandTail
xex2dSystemCommandDone:
   addi     %r1, %r1, 0x100
   lwz      %r11, -8(%r1)
   mtlr     %r11
   ld       %r31, -0x10(%r1)
   blr

   # ------------------------------------------------------------------------
   # VdSetSystemCommandBuffer for 1640. r3 = the title's struct.
   # ------------------------------------------------------------------------
xex2dSetSystemCommandBuffer:
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -0x100(%r1)
   mr       %r10, %r3
   addi     %r9, %r1, 0x50 - 4
   li       %r8, 4
   mtctr    %r8
xex2dSetCommandHead:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex2dSetCommandHead
   li       %r8, 0
   stwu     %r8, 4(%r9)
   li       %r8, 0x20
   mtctr    %r8
xex2dSetCommandTail:
   lwzu     %r8, 4(%r10)
   stwu     %r8, 4(%r9)
   bdnz     xex2dSetCommandTail
   addi     %r3, %r1, 0x50
   KMAKEBRANCHL VdSetSystemCommandBuffer
   addi     %r1, %r1, 0x100
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

   # ------------------------------------------------------------------------
   # VdInitializeScalerCommandBuffer for 1640. 8 arguments in registers, then on the stack the
   # second filter's parameters, the buffer and its size. 17489 has the hardware parameters
   # before the buffer, and those are from VdpInternalScalerSetup, which is what 1640's calls.
   # It doesn't touch any registers, and returns zero if the arguments are no good. It needs the
   # ANA lock held, as it asserts otherwise. The real function takes that itself, and the lock
   # isn't recursive, so it has to be released first.
   # ------------------------------------------------------------------------
xex2dInitializeScalerCommandBuffer:
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -XEX2D_SCALER_FRAME(%r1)
   stw      %r3, XEX2D_SCALER_REGS + 0x00(%r1)
   stw      %r4, XEX2D_SCALER_REGS + 0x04(%r1)
   stw      %r5, XEX2D_SCALER_REGS + 0x08(%r1)
   stw      %r6, XEX2D_SCALER_REGS + 0x0C(%r1)
   stw      %r7, XEX2D_SCALER_REGS + 0x10(%r1)
   stw      %r8, XEX2D_SCALER_REGS + 0x14(%r1)
   stw      %r9, XEX2D_SCALER_REGS + 0x18(%r1)
   stw      %r10, XEX2D_SCALER_REGS + 0x1C(%r1)
   KMAKEBRANCHL HalAcquireAnaLock
   bl       xex2dScalerArguments
   KMAKEBRANCHL VdpInternalScalerSetup
   stw      %r3, XEX2D_SCALER_RESULT(%r1)
   KMAKEBRANCHL HalReleaseAnaLock
   lwz      %r3, XEX2D_SCALER_RESULT(%r1)
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dScalerDone
   bl       xex2dScalerArguments
   lwz      %r11, XEX2D_SCALER_FRAME + 0x5C(%r1)
   stw      %r11, 0x64(%r1)
   lwz      %r11, XEX2D_SCALER_FRAME + 0x64(%r1)
   stw      %r11, 0x6C(%r1)
   KMAKEBRANCHL VdInitializeScalerCommandBuffer
xex2dScalerDone:
   addi     %r1, %r1, XEX2D_SCALER_FRAME
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

   # What both functions have the same of: the registers, then the second filter's parameters
   # and the hardware parameters on the stack. They're free to change all of it, so it's redone.
xex2dScalerArguments:
   lwz      %r3, XEX2D_SCALER_REGS + 0x00(%r1)
   lwz      %r4, XEX2D_SCALER_REGS + 0x04(%r1)
   lwz      %r5, XEX2D_SCALER_REGS + 0x08(%r1)
   lwz      %r6, XEX2D_SCALER_REGS + 0x0C(%r1)
   lwz      %r7, XEX2D_SCALER_REGS + 0x10(%r1)
   lwz      %r8, XEX2D_SCALER_REGS + 0x14(%r1)
   lwz      %r9, XEX2D_SCALER_REGS + 0x18(%r1)
   lwz      %r10, XEX2D_SCALER_REGS + 0x1C(%r1)
   lwz      %r11, XEX2D_SCALER_FRAME + 0x54(%r1)
   stw      %r11, 0x54(%r1)
   addi     %r11, %r1, XEX2D_SCALER_HW
   stw      %r11, 0x5C(%r1)
   blr

   # ------------------------------------------------------------------------
   # Xex2dSetTls - what 1640's XexStartExecutable did for TLS. r29 = loader entry, r30 = process.
   # ------------------------------------------------------------------------
xex2dSetTls:
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -0x70(%r1)
   lwz      %r3, 0x1C(%r29)
   li       %r4, 1
   li       %r5, 9                          # IMAGE_DIRECTORY_ENTRY_TLS
   addi     %r6, %r1, 0x50
   KMAKEBRANCHL RtlImageDirectoryEntryToData
   li       %r5, 0
   li       %r6, 0
   li       %r7, 0
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dSetTlsCall
   lwz      %r11, 0x50(%r1)
   cmplwi   cr6, %r11, 0x18
   blt      cr6, xex2dSetTlsCall
   lwz      %r7, 0(%r3)                     # start of raw data
   lwz      %r11, 4(%r3)                    # end of raw data
   subf     %r6, %r7, %r11
   lwz      %r5, 0x10(%r3)                  # size of zero fill
   add      %r5, %r5, %r6
xex2dSetTlsCall:
   mr       %r3, %r30
   li       %r4, 0x40
   KMAKEBRANCHL KeSetTlsConfigurationProcess
   addi     %r1, %r1, 0x70
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

   # ------------------------------------------------------------------------
   # Xex2dStackSize - what 1640's XexStartExecutable did for the stack. r29 = loader entry.
   # Returns SizeOfStackCommit from the PE header in r4, or zero to get the kernel's minimum.
   # ------------------------------------------------------------------------
xex2dStackSize:
   mflr     %r12
   stw      %r12, -8(%r1)
   stwu     %r1, -0x60(%r1)
   lwz      %r3, 0x1C(%r29)
   KMAKEBRANCHL RtlImageNtHeader
   li       %r4, 0
   cmplwi   cr6, %r3, 0
   beq      cr6, xex2dStackSizeDone
   addi     %r11, %r3, 0x64
   lwbrx    %r4, 0, %r11
xex2dStackSizeDone:
   addi     %r1, %r1, 0x60
   lwz      %r12, -8(%r1)
   mtlr     %r12
   blr

.include "xex2d_ordinals_17489.S"

   # c = i * 4 + i / 85, with c << 20 | c << 10 | c
xex2dGammaTable:
   .set     xex2dGammaIndex, 0
   .rept    256
   .long    ((xex2dGammaIndex * 4 + xex2dGammaIndex / 85) << 20) | ((xex2dGammaIndex * 4 + xex2dGammaIndex / 85) << 10) | (xex2dGammaIndex * 4 + xex2dGammaIndex / 85)
   .set     xex2dGammaIndex, xex2dGammaIndex + 1
   .endr
9:

.set Xex2dSetTls,       Xex25Cave + (xex2dSetTls - 0b)
.set Xex2dStackSize,    Xex25Cave + (xex2dStackSize - 0b)
.set Xex2dFixSlots,     Xex25Cave + (xex2dFixSlots - 0b)
.set Xex2dGetDefaultGammaTable, Xex25Cave + (xex2dGetDefaultGammaTable - 0b)
.set Xex2dGetSystemCommandBuffer, Xex25Cave + (xex2dGetSystemCommandBuffer - 0b)
.set Xex2dQuerySystemCommandBuffer, Xex25Cave + (xex2dQuerySystemCommandBuffer - 0b)
.set Xex2dSetSystemCommandBuffer, Xex25Cave + (xex2dSetSystemCommandBuffer - 0b)
.set Xex2dInitializeScalerCommandBuffer, Xex25Cave + (xex2dInitializeScalerCommandBuffer - 0b)
.set Xex25FixHeaders,   Xex25Cave + (xex25FixHeaders - 0b)
.set Xex25FixImports,   Xex25Cave + (xex25FixImports - 0b)
.set Xex25GetDefaultMEInitCommand, Xex25Cave + (xex25GetDefaultMEInitCommand - 0b)
.set Xex25ImageXexHeaderField, Xex25Cave + (xex25ImageXexHeaderField - 0b)
.set Xex25GetSystemCommandBuffer, Xex25Cave + (xex25GetSystemCommandBuffer - 0b)
.set Xex25QuerySystemCommandBuffer, Xex25Cave + (xex25QuerySystemCommandBuffer - 0b)
.set Xex25InitializeEngines, Xex25Cave + (xex25InitializeEngines - 0b)

KMAKEPATCH KernelExports + (XEX25_MEINIT_ORDINAL - 1) * 4
0:
   .long    Xex25GetDefaultMEInitCommand - KernelBase
9:

KMAKEPATCH KernelExports + (XEX25_HEADERFIELD_ORDINAL - 1) * 4
0:
   .long    Xex25ImageXexHeaderField - KernelBase
9:

KMAKEPATCH KernelExports + (XEX25_GETSYSTEMCB_ORDINAL - 1) * 4
0:
   .long    Xex25GetSystemCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX25_QUERYSYSTEMCB_ORDINAL - 1) * 4
0:
   .long    Xex25QuerySystemCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX25_INITENGINES_ORDINAL - 1) * 4
0:
   .long    Xex25InitializeEngines - KernelBase
9:

KMAKEPATCH KernelExports + (XEX2D_SCALER_ORDINAL - 1) * 4
0:
   .long    Xex2dInitializeScalerCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX2D_SETCB_ORDINAL - 1) * 4
0:
   .long    Xex2dSetSystemCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX2D_QUERYCB_ORDINAL - 1) * 4
0:
   .long    Xex2dQuerySystemCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX2D_GETCB_ORDINAL - 1) * 4
0:
   .long    Xex2dGetSystemCommandBuffer - KernelBase
9:

KMAKEPATCH KernelExports + (XEX2D_GAMMA_ORDINAL - 1) * 4
0:
   .long    Xex2dGetDefaultGammaTable - KernelBase
9:

# ============================================================================
# Xex1HeaderFixup
#
# Called from XexpVerifyXexHeaders with r31 = headers. r3-r12 are free here, as
# that function has already saved off its arguments. Has to run the instruction
# it replaced (lwz r11, 0x10(r31)) before returning.
#
# r24 = end of the fixed part of SecurityInfo, r25 = how much it grows,
# r26 = end of the range to move, r27 = new end of SecurityInfo,
# r28 = SecurityInfo, r29 = SizeOfHeaders, r30 = SecurityInfo offset
# ============================================================================
KMAKEPATCH Xex1Cave
0:
xex1HeaderFixup:
   lwz      %r11, 0(%r31)
   lis      %r10, XEX_MAGIC_HI
   ori      %r10, %r10, XEX_MAGIC_XEX1
   cmplw    cr6, %r11, %r10
   beq      cr6, xex1Convert
   addi     %r10, %r10, XEX_MAGIC_XEX25 - XEX_MAGIC_XEX1
   cmplw    cr6, %r11, %r10
   beq      cr6, xex1Convert
   addi     %r10, %r10, XEX_MAGIC_XEX2D - XEX_MAGIC_XEX25
   cmplw    cr6, %r11, %r10
   beq      cr6, xex1Convert

   # Not XEX1, XEX% or XEX-, nothing to do
   lwz      %r11, 0x10(%r31)
   blr

xex1Convert:
   mflr     %r12
   stw      %r12, -8(%r1)
   std      %r24, -0x48(%r1)
   std      %r25, -0x40(%r1)
   std      %r26, -0x38(%r1)
   std      %r27, -0x30(%r1)
   std      %r28, -0x28(%r1)
   std      %r29, -0x20(%r1)
   std      %r30, -0x18(%r1)
   stwu     %r1, -FRAME_SIZE(%r1)

   li       %r24, XEX1_INFO_END
   li       %r25, XEX1_GROWTH
   clrlwi   %r11, %r11, 16
   cmplwi   cr6, %r11, XEX_MAGIC_XEX1
   beq      cr6, xex1HaveFormat
   li       %r24, XEX25_INFO_END
   li       %r25, XEX25_GROWTH
   cmplwi   cr6, %r11, XEX_MAGIC_XEX25
   beq      cr6, xex1HaveFormat
   li       %r24, XEX2D_INFO_END
   li       %r25, XEX2D_GROWTH
xex1HaveFormat:

   # Don't trust anything yet, these headers might not have been verified by
   # anything and SecurityInfo isn't rejected for being odd until later on.
   lwz      %r30, 0x10(%r31)
   lwz      %r29, 8(%r31)
   lis      %r11, 1
   cmplw    cr6, %r29, %r11
   bgt      cr6, xex1Bail
   cmplw    cr6, %r30, %r29
   bge      cr6, xex1Bail

   add      %r28, %r30, %r31
   andi.    %r11, %r28, 3
   bne      xex1Bail

   # HvImageInfo can't cross a page
   clrlwi   %r11, %r28, 20
   cmplwi   cr6, %r11, 0x1000 - 8 - XEX2_INFO_SIZE
   bgt      cr6, xex1Bail

   # Size has to be sane and the bigger SecurityInfo has to fit in the headers
   lwz      %r11, 0(%r28)
   cmplw    cr6, %r11, %r24
   blt      cr6, xex1Bail
   cmplw    cr6, %r11, %r29
   bgt      cr6, xex1Bail
   add      %r27, %r30, %r11
   add      %r27, %r27, %r25
   cmplw    cr6, %r27, %r29
   bgt      cr6, xex1Bail

   # And the directory has to end before SecurityInfo starts
   lwz      %r9, 0x14(%r31)
   addi     %r10, %r9, -1
   cmplwi   cr6, %r10, 0x2000               # more than fits in 64KB, and the shift would overflow
   bge      cr6, xex1Bail
   slwi     %r10, %r9, 3
   addi     %r10, %r10, 0x18
   cmplw    cr6, %r10, %r30
   bgt      cr6, xex1Bail

   # Find the last optional header stored in the headers. Types 0 and 1 are
   # values in the directory, anything else is an offset.
   mtctr    %r9
   addi     %r8, %r31, 0x18 - 8
   li       %r26, 0
xex1FindLast:
   lwzu     %r11, 8(%r8)
   clrlwi   %r11, %r11, 24
   cmplwi   cr6, %r11, 1
   ble      cr6, xex1FindLastNext
   lwz      %r11, 4(%r8)
   cmplw    cr6, %r11, %r29
   bgt      cr6, xex1Bail
   cmplw    cr6, %r11, %r26
   ble      cr6, xex1FindLastNext
   mr       %r26, %r11
xex1FindLastNext:
   bdnz     xex1FindLast

   # Is there a gap in front of it? If not, look at the end of the headers.
   mr       %r3, %r26
   bl       xex1IsRoomAt
   beq      cr6, xex1HaveRoom
   mr       %r26, %r29
   mr       %r3, %r26
   bl       xex1IsRoomAt
   bne      cr6, xex1Bail

xex1HaveRoom:
   # From here on the headers get modified and failing isn't an option.
   # Stash everything that's about to get overwritten.
   addi     %r3, %r28, STASH_START
   addi     %r4, %r1, STASH
   li       %r5, STASH_WORDS
   bl       xex1CopyWords

   # Move page descriptors and optional headers out of the way, back to front
   add      %r8, %r31, %r26
   subf     %r10, %r25, %r8
   add      %r9, %r28, %r24
xex1Move:
   cmplw    cr6, %r10, %r9
   ble      cr6, xex1MoveDone
   lwzu     %r11, -4(%r10)
   stwu     %r11, -4(%r8)
   b        xex1Move
xex1MoveDone:

   # Point the directory at the headers that moved
   lwz      %r9, 0x14(%r31)
   mtctr    %r9
   addi     %r8, %r31, 0x18 - 8
   add      %r7, %r30, %r24
xex1FixDir:
   lwzu     %r11, 8(%r8)
   clrlwi   %r11, %r11, 24
   cmplwi   cr6, %r11, 1
   ble      cr6, xex1FixDirNext
   lwz      %r11, 4(%r8)
   cmplw    cr6, %r11, %r7
   blt      cr6, xex1FixDirNext
   cmplw    cr6, %r11, %r26
   bge      cr6, xex1FixDirNext
   add      %r11, %r11, %r25
   stw      %r11, 4(%r8)
xex1FixDirNext:
   bdnz     xex1FixDir

   cmplwi   cr6, %r25, XEX1_GROWTH
   beq      cr6, xex1HeadersReady
   KMAKEBRANCHL Xex25FixHeaders
xex1HeadersReady:

   # Exports moved from a header to SecurityInfo. Zero if there aren't any. XEX% has no
   # 0x10400 by this point, as that was its stack size.
   mr       %r3, %r31
   lis      %r4, 1
   ori      %r4, %r4, 0x400
   KMAKEBRANCHL RtlImageXexHeaderField
   mr       %r27, %r3

   # r26 = import descriptor, or zero if it doesn't import anything
   mr       %r3, %r31
   lis      %r4, 1
   ori      %r4, %r4, 0x3FF
   KMAKEBRANCHL RtlImageXexHeaderField
   mr       %r26, %r3

   # Write out XEX2 SecurityInfo
   li       %r11, XEX2_INFO_SIZE
   stw      %r11, 0x108(%r28)

   # 1838 doesn't use these flags, the 17489 HV would act on them if they're set:
   # 0x80000000/0x40000000 revocation checks, 0x08000000 online activation,
   # 0x04000000 keyvault privileges, 0x30 datacenter, 0x8 XGD2 media
   lwz      %r11, STASH + 0x158 - STASH_START(%r1)
   lis      %r10, 0xCC00
   ori      %r10, %r10, 0x38
   andc     %r11, %r11, %r10
   stw      %r11, 0x10C(%r28)

   lwz      %r11, STASH + 0x130 - STASH_START(%r1)
   stw      %r11, 0x110(%r28)

   addi     %r3, %r1, STASH + 0x11C - STASH_START
   addi     %r4, %r28, 0x114
   li       %r5, 5
   bl       xex1CopyWords

   addi     %r3, %r1, STASH + 0x144 - STASH_START
   addi     %r4, %r28, 0x140
   li       %r5, 4
   bl       xex1CopyWords

   addi     %r3, %r1, STASH + 0x134 - STASH_START
   addi     %r4, %r28, 0x150
   li       %r5, 4
   bl       xex1CopyWords

   stw      %r27, 0x160(%r28)

   lwz      %r11, STASH + 0x154 - STASH_START(%r1)
   stw      %r11, 0x178(%r28)
   lwz      %r11, STASH + 0x160 - STASH_START(%r1)
   stw      %r11, 0x17C(%r28)
   lwz      %r11, STASH + 0x164 - STASH_START(%r1)
   stw      %r11, 0x180(%r28)

   lwz      %r11, 0(%r28)
   add      %r11, %r11, %r25
   stw      %r11, 0(%r28)

   lis      %r11, XEX_MAGIC_HI
   ori      %r10, %r11, XEX_MAGIC_XEX1
   stw      %r10, 8(%r28)                   # marker for the display and key checks
   ori      %r11, %r11, XEX_MAGIC_XEX2
   stw      %r11, 0(%r31)

   cmplwi   cr6, %r25, XEX1_GROWTH
   beq      cr6, xex1ImportsReady
   KMAKEBRANCHL Xex25FixImports
xex1ImportsReady:

   # ImportTableCount. Without one the HV won't go looking for import tables.
   li       %r11, 0
   cmplwi   cr6, %r26, 0
   beq      cr6, xex1NoImports
   lwz      %r11, 8(%r26)
xex1NoImports:
   stw      %r11, 0x128(%r28)
   cmplwi   cr6, %r11, 0
   beq      cr6, xex1HashHeaders

   # ImportDigest = SHA(first table + 4, 0x24, the import addresses). If the table
   # isn't inside the headers, skip this and the HV fails it on the digest instead.
   add      %r4, %r31, %r29
   addi     %r4, %r4, -0x28
   lwz      %r11, 4(%r26)
   cmplw    cr6, %r11, %r29
   bgt      cr6, xex1HashHeaders
   add      %r11, %r11, %r26
   addi     %r11, %r11, 0xC
   cmplw    cr6, %r11, %r4
   bgt      cr6, xex1HashHeaders
   lhz      %r6, 0x26(%r11)
   slwi     %r6, %r6, 2
   subf     %r4, %r11, %r4
   cmplw    cr6, %r6, %r4
   bgt      cr6, xex1HashHeaders
   addi     %r3, %r11, 4
   li       %r4, 0x24
   addi     %r5, %r11, 0x28
   li       %r7, 0
   li       %r8, 0
   addi     %r9, %r28, 0x12C
   li       %r10, 0x14
   KMAKEBRANCHL XeCryptSha

xex1HashHeaders:
   # HeaderHash = SHA(after HvImageInfo up to SizeOfHeaders, start of headers
   # through SecurityInfo.ImageSize). The kernel checks this right after we return
   # and the HV checks it again for title headers. Needs to be done last.
   addi     %r3, %r28, 8 + XEX2_INFO_SIZE
   add      %r4, %r31, %r29
   subf     %r4, %r3, %r4
   mr       %r5, %r31
   addi     %r6, %r30, 8
   li       %r7, 0
   li       %r8, 0
   addi     %r9, %r28, 0x164
   li       %r10, 0x14
   KMAKEBRANCHL XeCryptSha

   # Way out, finished or not
xex1Bail:
   addi     %r1, %r1, FRAME_SIZE
   lwz      %r12, -8(%r1)
   mtlr     %r12
   ld       %r24, -0x48(%r1)
   ld       %r25, -0x40(%r1)
   ld       %r26, -0x38(%r1)
   ld       %r27, -0x30(%r1)
   ld       %r28, -0x28(%r1)
   ld       %r29, -0x20(%r1)
   ld       %r30, -0x18(%r1)
   lwz      %r11, 0x10(%r31)
   blr

   # ------------------------------------------------------------------------
   # Xex1IsRoomAt - are the r25 bytes before header offset r3 free, and will moving
   # data up to there leave SecurityInfo intact? cr6.eq = yes
   # r27 = where SecurityInfo will end.
   # ------------------------------------------------------------------------
xex1IsRoomAt:
   subf     %r11, %r25, %r3
   cmplw    cr6, %r11, %r27
   bltlr    cr6
   clrlwi   %r11, %r3, 30
   cmplwi   cr6, %r11, 0
   bnelr    cr6
   add      %r10, %r31, %r3
   srwi     %r9, %r25, 2
   mtctr    %r9
xex1IsRoomLoop:
   lwzu     %r11, -4(%r10)
   cmplwi   cr6, %r11, 0
   bnelr    cr6
   bdnz     xex1IsRoomLoop
   blr

   # ------------------------------------------------------------------------
   # Xex1CopyWords - copy r5 words from r3 to r4
   # ------------------------------------------------------------------------
xex1CopyWords:
   mtctr    %r5
xex1CopyLoop:
   lwz      %r11, 0(%r3)
   stw      %r11, 0(%r4)
   addi     %r3, %r3, 4
   addi     %r4, %r4, 4
   bdnz     xex1CopyLoop
   blr

   # ------------------------------------------------------------------------
   # Xex1LoadImageData - replaces the call to HvxLoadImageData in XexpLoadFile.
   # r3 = image, r4-r6 = page descriptor. Makes one HV call for each 64KB of image
   # the descriptor covers, which is only ever one call for an XEX2. Returns the
   # same thing as HvxLoadImageData, zero on failure.
   #
   # Uses what XexpLoadFile keeps in r26 (headers) and r30 (this page descriptor).
   # r24 = image, r25 = r4, r27 = r5, r28 = r6, r29 = pages left,
   # r30 = pages in 64KB, r31 = offset of the next page in the image
   # ------------------------------------------------------------------------
xex1LoadImageData:
   mflr     %r12
   stw      %r12, -8(%r1)
   std      %r24, -0x48(%r1)
   std      %r25, -0x40(%r1)
   std      %r27, -0x38(%r1)
   std      %r28, -0x30(%r1)
   std      %r29, -0x28(%r1)
   std      %r30, -0x20(%r1)
   std      %r31, -0x18(%r1)
   stwu     %r1, -0xA0(%r1)

   mr       %r24, %r3
   mr       %r25, %r4
   mr       %r27, %r5
   mr       %r28, %r6
   srdi     %r29, %r4, 36

   # XEX- import slots get fixed up before any of the image reaches the HV. r25 was the loader
   # entry, and that's where it got saved. The callee only uses volatiles, and r4-r6 are saved.
   lwz      %r11, 0x10(%r26)
   lwz      %r10, 0xC(%r11)
   lis      %r9, XEX_MAGIC_HI
   ori      %r9, %r9, XEX_MAGIC_XEX2D
   cmplw    cr6, %r10, %r9
   bne      cr6, xex1LoadNoSlots
   addi     %r10, %r11, 0x184
   cmplw    cr6, %r10, %r30
   bne      cr6, xex1LoadNoSlots
   lwz      %r3, 0xA0 - 0x40 + 4(%r1)
   mr       %r4, %r26
   KMAKEBRANCHL Xex2dFixSlots
xex1LoadNoSlots:

   # Where this descriptor starts is the sum of the ones before it
   lwz      %r11, 0x10(%r26)
   lwz      %r10, 0x10C(%r11)
   addi     %r9, %r11, 0x184
   li       %r31, 0
xex1LoadSum:
   cmplw    cr6, %r9, %r30
   bge      cr6, xex1LoadSumDone
   lwz      %r8, 0(%r9)
   srwi     %r8, %r8, 4
   add      %r31, %r31, %r8
   addi     %r9, %r9, 0x18
   b        xex1LoadSum
xex1LoadSumDone:

   # 0x10000000 = 4KB pages
   li       %r30, 1
   andis.   %r10, %r10, 0x1000
   beq      xex1LoadNext
   li       %r30, 0x10

xex1LoadNext:
   # r10 = pages up to the next 64KB boundary, or however many are left
   addi     %r10, %r30, -1
   and      %r10, %r31, %r10
   subf     %r10, %r10, %r30
   cmplw    cr6, %r29, %r10
   bge      cr6, xex1LoadHaveCount
   mr       %r10, %r29
xex1LoadHaveCount:
   subf     %r29, %r10, %r29
   add      %r31, %r31, %r10

   # Same descriptor, with only the page count changed
   slwi     %r10, %r10, 4
   rldicl   %r9, %r25, 32, 60
   or       %r10, %r10, %r9
   clrldi   %r4, %r25, 32
   rldimi   %r4, %r10, 32, 0
   mr       %r3, %r24
   mr       %r5, %r27
   mr       %r6, %r28
   KMAKEBRANCHL HvxLoadImageData
   cmplwi   cr6, %r3, 0
   beq      cr6, xex1LoadDone
   cmplwi   cr6, %r29, 0
   bne      cr6, xex1LoadNext

xex1LoadDone:
   addi     %r1, %r1, 0xA0
   lwz      %r12, -8(%r1)
   mtlr     %r12
   ld       %r24, -0x48(%r1)
   ld       %r25, -0x40(%r1)
   ld       %r27, -0x38(%r1)
   ld       %r28, -0x30(%r1)
   ld       %r29, -0x28(%r1)
   ld       %r30, -0x20(%r1)
   ld       %r31, -0x18(%r1)
   blr

   # ------------------------------------------------------------------------
   # Xex1MagicGate - replaces cmplw cr6, r11, r10 on the XEX2 magic.
   # r11 = magic from the file, r10 = XEX2 magic. cr6.eq = magic is acceptable
   # ------------------------------------------------------------------------
xex1MagicGate:
   cmplw    cr6, %r11, %r10
   beqlr    cr6
   addi     %r10, %r10, XEX_MAGIC_XEX1 - XEX_MAGIC_XEX2
   cmplw    cr6, %r11, %r10
   beqlr    cr6
   addi     %r10, %r10, XEX_MAGIC_XEX25 - XEX_MAGIC_XEX1
   cmplw    cr6, %r11, %r10
   beqlr    cr6
   addi     %r10, %r10, XEX_MAGIC_XEX2D - XEX_MAGIC_XEX25
   cmplw    cr6, %r11, %r10
   blr

   # ------------------------------------------------------------------------
   # Xex1DisplayFlagGate - replaces rlwinm. r11, r26, 0, 1, 1 in VdSetDisplayMode.
   # r26 = flags. cr0.eq = flag 0x40000000 isn't set, or the running title has the XEX1 marker.
   # ------------------------------------------------------------------------
xex1DisplayFlagGate:
   rlwinm.  %r11, %r26, 0, 1, 1
   beqlr
   lis      %r11, XexExecutableModuleHandle@ha
   lwz      %r11, XexExecutableModuleHandle@l(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 0x58(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 0x10(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 8(%r11)
   lis      %r10, XEX_MAGIC_HI
   ori      %r10, %r10, XEX_MAGIC_XEX1
   cmplw    %r11, %r10
   blr

   # ------------------------------------------------------------------------
   # Xex1StartTlsGate - replaces beq past the call to KeSetTlsConfigurationProcess, in
   # XexStartExecutable. cr0.eq = there's no 0x20104 header. Only XEX- gets anything else done.
   # ------------------------------------------------------------------------
xex1StartTlsGate:
   bnelr
   mflr     %r11
   addi     %r11, %r11, XEX_START_TLS_SKIP
   mtlr     %r11
   lwz      %r11, 0x10(%r31)
   lwz      %r11, 0xC(%r11)
   lis      %r10, XEX_MAGIC_HI
   ori      %r10, %r10, XEX_MAGIC_XEX2D
   cmplw    cr6, %r11, %r10
   bnelr    cr6
   KMAKEBRANCH Xex2dSetTls

   # ------------------------------------------------------------------------
   # Xex1StartStackGate - replaces mr r4, r3 before KeSetDefaultKernelStackSizeProcess, in
   # XexStartExecutable. r3 = the 0x20200 header, or zero. Only XEX- gets anything else done.
   # ------------------------------------------------------------------------
xex1StartStackGate:
   mr       %r4, %r3
   cmplwi   cr6, %r3, 0
   bnelr    cr6
   lwz      %r11, 0x10(%r31)
   lwz      %r11, 0xC(%r11)
   lis      %r10, XEX_MAGIC_HI
   ori      %r10, %r10, XEX_MAGIC_XEX2D
   cmplw    cr6, %r11, %r10
   bnelr    cr6
   KMAKEBRANCH Xex2dStackSize

   # ------------------------------------------------------------------------
   # Xex1PhysicalGate - replaces mr r25, r5 in MmAllocatePhysicalMemoryEx. r5 = protect flags.
   # While an XEX- is running, its title process gets 64KB pages when it would have got 4KB.
   # See the top of this file. 0x01000000 on its own means no mapping, so that's left alone.
   # Only r9-r11 are free here, the other arguments are still to come.
   # ------------------------------------------------------------------------
xex1PhysicalGate:
   mr       %r25, %r5
   lis      %r11, XexExecutableModuleHandle@ha
   lwz      %r11, XexExecutableModuleHandle@l(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 0x58(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 0x10(%r11)
   cmplwi   cr6, %r11, 0
   beqlr    cr6
   lwz      %r11, 0xC(%r11)
   lis      %r10, XEX_MAGIC_HI
   ori      %r10, %r10, XEX_MAGIC_XEX2D
   cmplw    cr6, %r11, %r10
   bnelr    cr6
   lwz      %r11, 0x100(%r13)
   lbz      %r11, 0x73(%r11)
   cmplwi   cr6, %r11, 2                    # the system process
   beqlr    cr6
   andis.   %r11, %r25, 0xA000              # already 64KB or 16MB
   bnelr
   lis      %r11, 0x100
   cmplw    cr6, %r25, %r11
   beqlr    cr6
   oris     %r25, %r25, 0x2000
   blr
9:

.set Xex1PhysicalGate,  Xex1Cave + (xex1PhysicalGate - 0b)
.set Xex1StartTlsGate,  Xex1Cave + (xex1StartTlsGate - 0b)
.set Xex1StartStackGate, Xex1Cave + (xex1StartStackGate - 0b)
.set Xex1HeaderFixup,   Xex1Cave + (xex1HeaderFixup - 0b)
.set Xex1MagicGate,     Xex1Cave + (xex1MagicGate - 0b)
.set Xex1LoadImageData, Xex1Cave + (xex1LoadImageData - 0b)
.set Xex1DisplayFlagGate, Xex1Cave + (xex1DisplayFlagGate - 0b)

# ============================================================================
# VdSetDisplayMode - don't blank the display for XEX1 titles, see the top of this file
# ============================================================================
KMAKEPATCH VdSetDisplayMode_Flag
0:
   KMAKEBRANCHL Xex1DisplayFlagGate
9:

# ============================================================================
# XexStartExecutable - TLS slots and a stack for XEX-, see the top of this file
# ============================================================================
KMAKEPATCH XexStartExecutable_Tls
0:
   KMAKEBRANCHL Xex1StartTlsGate
9:

KMAKEPATCH XexStartExecutable_Stack
0:
   KMAKEBRANCHL Xex1StartStackGate
9:

# ============================================================================
# MmAllocatePhysicalMemoryEx - no 4KB pages for an XEX-, see the top of this file
# ============================================================================
KMAKEPATCH MmAllocatePhysicalMemoryEx_Protect
0:
   KMAKEBRANCHL Xex1PhysicalGate
9:

# ============================================================================
# XexpLoadFile - split up page descriptors that the HV won't take in one call
# ============================================================================
KMAKEPATCH XexpLoadFile_LoadImageData
0:
   KMAKEBRANCHL Xex1LoadImageData
9:

# ============================================================================
# HvxLoadImageData - ignore the page hash, see the top of this file
# ============================================================================
MAKEPATCH HV_LoadImageData_HashCheck
0:
   nop
9:

# ============================================================================
# HvxResolveImports - send old kernel and xam imports to where those functions are now.
#
# Replaces slwi r11, r11, 2. r11 = index into the export table, r26 = ordinal.
# r9, r10 and r12 are free here, and so are cr7 and ctr. r1 is HvxResolveImports' frame,
# with the import table header at +0x1F0 and the exporter's first ordinal at +0x88. r26
# has to stay as it is, because the thunk's second word gets checked against it after this.
#
# Going by the table's version, anything older than 1838 uses the 1746 ordinals, and 1838
# up to the start of XEX2 uses the 1838 ones. 1838's kernel ordinals didn't need a table.
# ============================================================================
MAKEPATCH Xex1HvCave
0:
xex1RemapOrdinal:
   lwz      %r10, 0x208(%r1)                # import table's version, as build number
   srwi     %r10, %r10, 8
   addis    %r10, %r10, -0x20               # anything but 2.0.x ends up too big to pass
   cmplwi   cr6, %r10, XEX2_FIRST_BUILD
   bge      cr6, xex1RemapDone
   cmplwi   cr7, %r10, XEX1_FIRST_BUILD

   mflr     %r12
   bcl      20, 31, 1f
1:
   mflr     %r9
   mtlr     %r12

   lwz      %r10, 0x204(%r1)                # import table's module number
   lis      %r12, XAM_MODULE_NUMBER@h
   ori      %r12, %r12, XAM_MODULE_NUMBER@l
   cmplw    cr6, %r10, %r12
   beq      cr6, xex1RemapXam
   lis      %r12, KERNEL_MODULE_NUMBER@h
   ori      %r12, %r12, KERNEL_MODULE_NUMBER@l
   cmplw    cr6, %r10, %r12
   bne      cr6, xex1RemapDone
   bge      cr7, xex1RemapDone

   # Anything past the end of 1746's exports isn't a real import, so it gets the stub
   addi     %r10, %r26, -XEX25_KERNEL_FIRST
   cmplwi   cr6, %r10, XEX25_KERNEL_COUNT
   li       %r12, XEX25_KERNEL_STUB
   bge      cr6, xex1RemapKernelStub
   slwi     %r10, %r10, 1
   addi     %r9, %r9, xex25KernelTable - 1b
   lhzx     %r12, %r9, %r10
xex1RemapKernelStub:
   mr       %r10, %r12
   b        xex1RemapHave

xex1RemapXam:
   addi     %r9, %r9, xex1RemapTable - 1b - 4
   li       %r10, (xex1RemapTableEnd - xex1RemapTable) / 4
   bge      cr7, xex1RemapXamScan
   addi     %r9, %r9, xex25XamTable - xex1RemapTable
   li       %r10, (xex25XamTableEnd - xex25XamTable) / 4
xex1RemapXamScan:
   mtctr    %r10
xex1RemapFind:
   lhzu     %r10, 4(%r9)
   cmplw    cr6, %r10, %r26
   beq      cr6, xex1RemapFound
   bdnz     xex1RemapFind
   b        xex1RemapDone

xex1RemapFound:
   lhz      %r10, 2(%r9)
xex1RemapHave:
   lwz      %r9, 0x88(%r1)
   subf     %r11, %r9, %r10

xex1RemapDone:
   slwi     %r11, %r11, 2
   blr

   # 1838 ordinal, 17489 ordinal. See the top of this file for where these came from.
xex1RemapTable:
   .short  257,  258    # NetDll_UpnpActionCreate
   .short  258,  259    # NetDll_UpnpActionGetResults
   .short  259,  260    # NetDll_UpnpEventCreate
   .short  260,  261    # NetDll_UpnpEventGetCurrentState
   .short  261,  262    # NetDll_UpnpEventUnsubscribe
   .short  262,  263    # NetDll_UpnpDoWork
   .short  263,  264    # NetDll_UpnpCloseHandle
   .short  450, 1109    # XamApplySkin (removed)
   .short  452,  485    # XamFormatMessage
   .short  453,  795    # XamBuildResourceLocator
   .short  454,  789    # XamBuildSharedSystemResourceLocator
   .short  455,  745    # XamShowMessageBox
   .short  456, 1109    # XCustomGetBannerImage (removed)
   .short  457, 1109    # XamCustomSetBannerImage (removed)
   .short  458,  472    # XCustomSetAction
   .short  459,  473    # XCustomGetLastActionPress
   .short  460, 1109    # XCustomGetActionSetting (removed)
   .short  461,  475    # XCustomBroadcastActionEvent
   .short  462, 1109    # XamGetBkgndDefault (removed)
   .short  463,  453    # XamGetDefaultSystemImage
   .short  464,  487    # XamFormatTimeString
   .short  466,  488    # XamFormatDateString
   .short  467,  480    # XamDbgPrint
   .short  468,  416    # XamEnableInactivityProcessing
   .short  469,  415    # XamSetInactivityTime
   .short  470,  460    # XamSetDashContext
   .short  471,  461    # XamGetDashContext
   .short  472,  463    # XamGetCurrentTitleId
   .short  473,  454    # XamGetWCNConfigFile
   .short  474,  462    # XamIsCurrentTitleDash
   .short  475,  417    # XamResetInactivity
   .short  476,  547    # XamAreMixedAccountsSignedIn
   .short  477,  797    # XamBuildGamercardResourceLocator
   .short  478,  418    # XamSetInactivityTimeFromConfig
   .short  479,  798    # XamBuildDynamicResourceLocator
   .short  480,  455    # XamSetPowerMode
   .short  482,  456    # XamExecuteChallenge
   .short  483,  746    # XamIsSysUiInvokedByXenonButton
   .short  484,  747    # XamIsSysUiInvokedByTitle
   .short  485,  486    # XamUniSortCmpString
   .short  601,  603    # XamContentDelete
   .short  603,  604    # XamContentCreateEnumerator
   .short  604,  605    # XamContentCreateDeviceEnumerator
   .short  605,  606    # XamContentGetDeviceData
   .short  606,  607    # XamContentGetDeviceName
   .short  607,  608    # XamContentSetThumbnail
   .short  608,  590    # XamCreateEnumeratorHandle
   .short  609,  591    # XamGetPrivateEnumStructureFromHandle
   .short  610,  592    # XamEnumerate
   .short  611,  609    # XamContentGetThumbnail
   .short  612,  610    # XamContentGetCreator
   .short  613,  611    # XamContentLaunchImage
   .short  614,  612    # XamContentGetAttributes
   .short  615,  613    # XamContentGetDeviceState
   .short  616,  614    # XamContentGetLicenseMask
   .short  617,  615    # XamContentFlush
   .short  624,  633    # XamContentAggregateCreateEnumerator
   .short  625,  624    # XamContentDeleteInternal
   .short  626,  625    # XamContentCreateInternal
   .short  627,  634    # XamContentCreateAndMountPackage
   .short  628,  626    # XamContentSetThumbnailInternal
   .short  629,  627    # XamContentLaunchImageInternal
   .short  630,  635    # XamContentOpenPackageFile
   .short  631,  636    # XamContentMountPackage
   .short  632,  628    # XamContentWritePackageHeader
   .short  633,  637    # XamContentFlushPackage
   .short  634,  629    # XamContentDismountAndClosePackage
   .short  635,  638    # XamContentClosePackageFile
   .short  636,  616    # XamContentResolve
   .short  637,  630    # XamContentResolveInternal
   .short  638,  631    # XamContentGetAttributesInternal
   .short  770,  775    # XamUserAddRecentPlayer
   .short  771,  776    # XamUserUpdateRecentPlayer
   .short  772,  777    # XamUserCreatePlayerEnumerator
   .short  773,  778    # XamParseGamerTileKey
xex1RemapTableEnd:

.include "xex25_ordinals_17489.S"
9:

MAKEPATCH HV_ResolveImports_Index
0:
   bla      Xex1HvCave
9:

# ============================================================================
# XexpLoadXexHeaders - accept XEX1 and XEX% magic
# ============================================================================
KMAKEPATCH XexpLoadXexHeaders_Magic
0:
   KMAKEBRANCHL Xex1MagicGate
9:

# ============================================================================
# XexLoadImageHeaders - accept XEX1 and XEX% magic
# ============================================================================
KMAKEPATCH XexLoadImageHeaders_Magic
0:
   KMAKEBRANCHL Xex1MagicGate
9:

# ============================================================================
# XexpVerifyXexHeaders - convert XEX1 and XEX% headers on the way in. All of the paths
# which load headers come through here, so this is the only place that does it.
# ============================================================================
KMAKEPATCH XexpVerifyXexHeaders_Hook
0:
   KMAKEBRANCHL Xex1HeaderFixup
9:

# ============================================================================
# End of XEX1 and XEX% support
# ============================================================================
