# ============================================================================
# XEX1 loader support for the 17489 devkit kernel
#
# Lets the kernel load XEX1 executables (the format used by devkit build 1838)
# alongside XEX2. Include this from khv_17489.S, before the patch list
# terminator, by defining xex1:
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
# XEX% is the next candidate, but it isn't a small change. Its kernel ordinals are
# different, so it needs a table to remap them, and its import tables have no module
# numbers or versions. That won't fit in Xex1Cave along with the conversion. None of
# it has been started, see notes/XexPercentSupport.md.
# XEX- isn't a small change. Its SecurityInfo and import tables are laid out quite
# differently, and ImageHash is all zeroes (checked on one xshell.xex), so it
# would also need the HvxLoadImageData hash check patched out at 0x2A578.
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

# Kernel functions
.set RtlImageXexHeaderField,    0x800B3530
.set XeCryptSha,                0x801556D8
.set HvxLoadImageData,          0x8009F8F0

# Kernel variables
.set XexExecutableModuleHandle, 0x802080D4

# HV, in HvxLoadImageData: bne cr6 on the page hash not matching
.set HV_LoadImageData_HashCheck, 0x0002A578

# HV, in HvxResolveImports: slwi r11, r11, 2 on the index into the export table
.set HV_ResolveImports_Index,   0x0002ADC4

# Empty space in the last page of .text, which ends at 0x801C1770. This is past the
# strings in sysroot_hdd.S at 0x801C1850 and RGLoader's patch at 0x801C1774, and is
# in the same 4KB page, so it's known to be mapped executable. Has until 0x801C2000.
.set Xex1Cave, 0x801C1900

# Empty HV space, past RGLoader's FixFuses at 0xB400. Has until 0xC000.
.set Xex1HvCave, 0xB500

# ----------------------------------------------------------------------------
# Format constants, these should not need to change between kernels
# ----------------------------------------------------------------------------
.set XEX_MAGIC_HI,    0x5845
.set XEX_MAGIC_XEX1,  0x5831
.set XEX_MAGIC_XEX2,  0x5832

.set XAM_MODULE_NUMBER, 0xFCA15C76
.set XEX2_FIRST_BUILD,  1861

.set XEX1_INFO_END,   0x168                 # end of the fixed part of XEX1 SecurityInfo
.set XEX1_GROWTH,     0x1C                  # sizeof(xex2::SecurityInfo) - sizeof(xex1::SecurityInfo)
.set XEX2_INFO_SIZE,  0x174                 # sizeof(xex2::HvImageInfo)

# Copy of XEX1 SecurityInfo +0x108..+0x168, on the stack during the conversion
.set STASH,           0x50
.set STASH_START,     0x108
.set STASH_WORDS,     (XEX1_INFO_END - STASH_START) / 4
.set FRAME_SIZE,      0xF0

# ============================================================================
# Xex1HeaderFixup
#
# Called from XexpVerifyXexHeaders with r31 = headers. r3-r12 are free here, as
# that function has already saved off its arguments. Has to run the instruction
# it replaced (lwz r11, 0x10(r31)) before returning.
#
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

   # Not XEX1, nothing to do
   lwz      %r11, 0x10(%r31)
   blr

xex1Convert:
   mflr     %r12
   stw      %r12, -8(%r1)
   std      %r26, -0x38(%r1)
   std      %r27, -0x30(%r1)
   std      %r28, -0x28(%r1)
   std      %r29, -0x20(%r1)
   std      %r30, -0x18(%r1)
   stwu     %r1, -FRAME_SIZE(%r1)

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
   cmplwi   cr6, %r11, XEX1_INFO_END
   blt      cr6, xex1Bail
   cmplw    cr6, %r11, %r29
   bgt      cr6, xex1Bail
   add      %r27, %r30, %r11
   addi     %r27, %r27, XEX1_GROWTH
   cmplw    cr6, %r27, %r29
   bgt      cr6, xex1Bail

   # And the directory has to end before SecurityInfo starts
   lwz      %r9, 0x14(%r31)
   cmplwi   cr6, %r9, 0
   beq      cr6, xex1Bail
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
   addi     %r10, %r8, -XEX1_GROWTH
   addi     %r9, %r28, XEX1_INFO_END
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
   addi     %r7, %r30, XEX1_INFO_END
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
   addi     %r11, %r11, XEX1_GROWTH
   stw      %r11, 4(%r8)
xex1FixDirNext:
   bdnz     xex1FixDir

   # Exports moved from a header to SecurityInfo. Zero if there aren't any.
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
   addi     %r11, %r11, XEX1_GROWTH
   stw      %r11, 0(%r28)

   lis      %r11, XEX_MAGIC_HI
   ori      %r10, %r11, XEX_MAGIC_XEX1
   stw      %r10, 8(%r28)                   # marker for the display and key checks
   ori      %r11, %r11, XEX_MAGIC_XEX2
   stw      %r11, 0(%r31)

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
   ld       %r26, -0x38(%r1)
   ld       %r27, -0x30(%r1)
   ld       %r28, -0x28(%r1)
   ld       %r29, -0x20(%r1)
   ld       %r30, -0x18(%r1)
   lwz      %r11, 0x10(%r31)
   blr

   # ------------------------------------------------------------------------
   # Xex1IsRoomAt - are the XEX1_GROWTH bytes before header offset r3 free, and
   # will moving data up to there leave SecurityInfo intact? cr6.eq = yes
   # r27 = where SecurityInfo will end.
   # ------------------------------------------------------------------------
xex1IsRoomAt:
   addi     %r11, %r3, -XEX1_GROWTH
   cmplw    cr6, %r11, %r27
   bltlr    cr6
   clrlwi   %r11, %r3, 30
   cmplwi   cr6, %r11, 0
   bnelr    cr6
   add      %r10, %r31, %r3
   li       %r9, XEX1_GROWTH / 4
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
   blr

   # ------------------------------------------------------------------------
   # Xex1DisplayFlagGate - replaces rlwinm. r11, r26, 0, 1, 1 in VdSetDisplayMode.
   # r26 = flags. cr0.eq = flag 0x40000000 isn't set, or the running title is XEX1.
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
9:

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
# HvxResolveImports - send 1838 xam imports to where those functions are now.
#
# Replaces slwi r11, r11, 2. r11 = index into the export table, r26 = ordinal.
# r9, r10 and r12 are free here. r1 is HvxResolveImports' frame, with the import
# table header at +0x1F0 and the exporter's first ordinal at +0x88. r26 has to stay
# as it is, because the thunk's second word gets checked against it after this.
# ============================================================================
MAKEPATCH Xex1HvCave
0:
xex1RemapOrdinal:
   lwz      %r10, 0x204(%r1)                # import table's module number
   lis      %r9, XAM_MODULE_NUMBER@h
   ori      %r9, %r9, XAM_MODULE_NUMBER@l
   cmplw    cr6, %r10, %r9
   bne      cr6, xex1RemapDone
   lwz      %r10, 0x208(%r1)                # import table's version, as build number
   srwi     %r10, %r10, 8
   addis    %r10, %r10, -0x20               # anything but 2.0.x ends up too big to pass
   cmplwi   cr6, %r10, XEX2_FIRST_BUILD
   bge      cr6, xex1RemapDone

   mflr     %r12
   bcl      20, 31, 1f
1:
   mflr     %r9
   mtlr     %r12
   addi     %r9, %r9, xex1RemapTable - 1b - 4
   li       %r10, (xex1RemapTableEnd - xex1RemapTable) / 4
   mtctr    %r10
xex1RemapFind:
   lhzu     %r10, 4(%r9)
   cmplw    cr6, %r10, %r26
   beq      cr6, xex1RemapFound
   bdnz     xex1RemapFind
   b        xex1RemapDone

xex1RemapFound:
   lhz      %r10, 2(%r9)
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
9:

MAKEPATCH HV_ResolveImports_Index
0:
   bla      Xex1HvCave
9:

# ============================================================================
# XexpLoadXexHeaders - accept XEX1 magic
# ============================================================================
KMAKEPATCH XexpLoadXexHeaders_Magic
0:
   KMAKEBRANCHL Xex1MagicGate
9:

# ============================================================================
# XexLoadImageHeaders - accept XEX1 magic
# ============================================================================
KMAKEPATCH XexLoadImageHeaders_Magic
0:
   KMAKEBRANCHL Xex1MagicGate
9:

# ============================================================================
# XexpVerifyXexHeaders - convert XEX1 headers on the way in. All of the paths
# which load headers come through here, so this is the only place that does it.
# ============================================================================
KMAKEPATCH XexpVerifyXexHeaders_Hook
0:
   KMAKEBRANCHL Xex1HeaderFixup
9:

# ============================================================================
# End of XEX1 support
# ============================================================================
