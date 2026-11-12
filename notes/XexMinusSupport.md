# XEX- Support on the 17489 Devkit Kernel

Notes on loading `XEX-` executables, the format used by build 1640, on top of the [XEX1](Xex1Support.md) and [`XEX%`](XexPercentSupport.md) support. The patch is in `src/KHV/17489_RGLoader/inc/xex1_17489.S`, with the ordinal tables in `xex2d_ordinals_17489.S`, built by the same `xex1` flag.

**`Dolphin.exe` from 1640 runs on hardware,** and looks right, apart from the [HUD](#hud). That run had the ANA lock assertion patched out by hand in WinDbg, so the build with the [real fix](#vdinitializescalercommandbuffer) hasn't been run yet, and no other title has been tried. Everything else was tested by running the real kernel and HV code in the interpreter, on the 36 files in the recovery and all 4 CoD2 executables. See [Testing](#testing) for what that does and doesn't cover, and [Running it](#running-it) for what's next.

idaxex calls this format `XEX2D`, because the magic byte is `0x2D`. Labels in the patch use `xex2d`, the way `xex25` is used for `XEX%`.

## Summary

The headers convert the same way as before. The imports are the new part:

1. **Import tables are 4 bytes shorter per table,** with no `VersionMin`, so every table gets rewritten and the descriptor grows.
2. **Import records are plain import address slots holding only an ordinal.** There are no `01ss oooo` thunks. The HV's data import path already writes what these need, but it rejects them because they have no module index byte.
3. **Titles import libraries that no longer exist.** `drivers.xex` became part of the kernel and `xnet.xex` part of xam, so their tables get pointed there, with their own ordinals.
4. **The module flags mean something else.** A title is `0x2` here and `0x1` everywhere later.
5. **Two kernel functions changed in ways the names don't show.** The [system command buffer](#system-command-buffer) has its first five words in a different order, and [`VdInitializeScalerCommandBuffer`](#vdinitializescalercommandbuffer) has an extra stack argument. A title would crash on either.
6. **TLS slots and the stack size used to come from the PE.** 17489 only looks for headers these files don't have, see [Process start](#process-start).
7. **D3D makes GPU addresses by masking.** That's wrong by `0x1000` for 4KB physical memory on 17489, see [GPU addresses](#gpu-addresses).

The import slots get rewritten in the image from the kernel, just before the first `HvxLoadImageData`, using final 17489 ordinals. That leaves the HV alone for `XEX-`, and the tables go in the kernel, where there's room. See [Resolving imports](#resolving-imports).

The bigger unknown is at runtime. 1640's D3D is older than anything tried so far, and nothing can test that without a console.

## Sources

| Thing | Where | Notes |
| - | - | - |
| Kernel | `symsrv\xboxkrnlwd.exe\42982F17c0000` | PE with its PDB. Loader is in the kernel here, there's no HV involved |
| Display, audio and XMA | `symsrv\drivers.dll\4298350E52000` | The `drivers.xex` exports |
| xam | `symsrv\xamd.dll\42983F49ec000` | |
| xnet | `symsrv\xnetd.dll\4298351D4d000` | Merged into xam later on |
| xbdm | `symsrv\xbdm.dll\42982F7D54000` | |
| Samples | `1640_Xenon_Recovery.iso_ext\N\XDKSAMPLES` | `Dolphin`, `LightShafts`, `SceneViewer`, `AudioConsole`, `UIAuditioning` |
| Format reference | `D:\Documents\GitHub\idaxex\formats` | `xex_structs.hpp` and `xex_optheaders.hpp`, namespace `xex2d` |

`symsrv` is under `1640_Xenon_Recovery_with_Symbols`. It holds up to five builds of each module, from February to May 2005. Only the May 28 one is 1640, which matches Dolphin's timestamp (`42984203`). Don't use the others.

`peaudit.py` reads these exports with no changes. IDA opens the kernel and `drivers.dll` with `idat -A -c -Opdb:off`, with names applied from the PDB's public symbols.

## Format

Checked against all 36 `XEX-` files in the recovery, and against what 1640's `XexpParseXexHeaders` and `XexpLoadFile` read. idaxex's layout is right, apart from what's noted under [idaxex and xex1tool](#idaxex-and-xex1tool).

### SecurityInfo

It's `0x140` bytes, against `0x184` in XEX2, so it grows by `0x44`. Nothing lines up, including `ImageSize`, which every later format has at `+4`.

| Field | `XEX-` | XEX2 | Notes |
| - | - | - | - |
| Size | `+0x000` | `+0x000` | Includes the page descriptors, as in XEX2 |
| Signature | `+0x004` | `+0x008` | All zeroes in all 36. Becomes the marker |
| HeaderHash | `+0x104` | `+0x164` | Recomputed |
| ImageHash | `+0x118` | `+0x114` | All zeroes in all 36 |
| LoadAddress | `+0x12C` | `+0x110` | |
| ImageSize | `+0x130` | `+0x004` | |
| CurrentVersion, LowestAcceptableVersion | `+0x134`, `+0x138` | n/a | All zeroes, dropped |
| PageDescriptorCount | `+0x13C`, 16 bits | `+0x180` | |
| ImageFlags | `+0x13E`, 16 bits | `+0x10C` | Shift left by 16. `0x1000` in all 36, which is 4KB pages |
| Page descriptors | `+0x140` | `+0x184` | |

These don't exist in `XEX-`, so the conversion has to supply them:

| Field | Value | Why |
| - | - | - |
| InfoSize | `0x174` | As XEX1 |
| ImportTableCount, ImportDigest | From the tables | As XEX1 |
| MediaID | Zeroes | As `XEX%` |
| ImageKey | Zeroes | There's no key field, and no file is encrypted |
| ExportTableAddress | 0 for titles | Key `0x10300` on system modules, see [Scope](#scope) |
| GameRegion | `0xFFFFFFFF` | As `XEX%` |
| AllowedMediaTypes | `0x10605` | What the XEX% `Dolphin.exe` has, which runs on hardware |

The header hash is `SHA(SecurityInfo + 0x118 to SizeOfHeaders, start of headers to SecurityInfo + 0x104)`. It checks out on all 36, so it's a usable test that a file is intact. The conversion doesn't need it.

Page descriptors keep the same format and info bits as `XEX%` (`1`, `2` and `3` here). Their digests are all zero in all 36, so nothing in the format proves an image is intact. Dolphin's 11 descriptors cover up to `0x40` pages each, so `Xex1LoadImageData` has to split them, which it already does. The `0x2A578` patch already turns off the hash check.

### Module flags

These are in the file header at `+4`, and idaxex's `xex0::ModuleFlags` has the right names. The 1640 kernel uses bit `0x2` to choose the title process.

| Meaning | `XEX-` | `XEX%` onward |
| - | - | - |
| Title | `0x2` | `0x1` |
| Exports to title | n/a | `0x2` |
| System process | `0x1` | No flag |
| DLL | `0x4` | `0x8` |
| Debugger | `0x8` | `0x4` |

Without this, 17489's `XexpVerifyXexHeaders` (`andi. r10, r11, 9`, compared with 1) doesn't see a title at all. Titles are the only row I've confirmed, by comparing the same sample in `XEX-` (`0x2`) and `XEX%` (`0x1`). The rest are from idaxex's names.

### Optional headers

| Key | Files | What happens |
| - | - | - |
| `0x003FF` data descriptor | 36 | Same format, going by the fields. 10 are raw, including all 5 samples and `xshell`. 26 are compressed, including `dash`, `xbupdate` and `processdump` |
| `0x10001` base, `0x18002` vital stats | 36 | Same key and format |
| `0x10100` entry point | 34 | Same key. `xapi` and `xapid` don't have one |
| `0x102FF` imports | 34 | Rename to `0x103FF`, as `XEX%` |
| `0x201FF` static libraries | 36 | Rename to `0x200FF`, as `XEX%` |
| `0x002FF`, `0x10300`, `0xE10302` | System modules only | Left alone for now |
| `0x40006` execution ID | `xshell`, `dash`, [CoD2](#call-of-duty-2) | Same key and size as XEX2's, with a different layout, so it has to be rewritten in place |

No file has TLS or stack size keys, so the `XEX%` renames for those never come up. `SizeOfHeaders` is `0x1000` in the recovery and `0x2000` in CoD2.

Headers are packed with no gaps, in all 40 files, so the only free space is at the end, and it's blank. That's `0x28C` bytes at the least (`dash.xex`), and `0x518` for a title (`CoD2MP.exe`). Growing SecurityInfo and the import descriptor needs about `0x70` bytes. Imports are the last optional header except where `0x40006` follows them, which is `xshell`, `dash` and all of CoD2, so that moves as well.

The HV won't take an import table that crosses a page, and on `cod2sp_s.exe` the kernel's table would, from about `0xEA0` to `0x10EC`. So a table that won't fit in what's left of a page starts at the next one. The padding goes on the end of the table before it, or on the name table for the first one, and neither is hashed. The kernel walks tables by `TableSize`, and the digest uses `ImportCount`.

### Import tables

The descriptor is the same (`Size`, `NameTableSize`, `ModuleCount`, then names). Each table is `0x24` bytes instead of `0x28`:

| Field | `XEX-` | XEX2 |
| - | - | - |
| TableSize | `+0x00` | `+0x00` |
| NextImportDigest | `+0x04` | `+0x04` |
| ModuleNumber | `+0x18` | `+0x18` |
| Version | `+0x1C` | `+0x1C` |
| VersionMin | n/a | `+0x20` |
| Unused, ModuleIndex | `+0x20`, `+0x21` | `+0x24`, `+0x25` |
| ImportCount | `+0x22` | `+0x26` |
| Import addresses | `+0x24` | `+0x28` |

ModuleNumber, Version and every digest are zero, so the chain is rebuilt the same way as `XEX%`. The HV reads these at fixed offsets, so the tables have to be rewritten, not just patched up.

### Import records

This is the biggest difference from every later format.

Each import address points at a word in a table near the start of the image (`0x92001000` to about `0x92001250` in the samples) that holds only the ordinal, with the rest zero. All 963 records in the 8 raw files with imports look like that. The title reaches them through its own thunks, 84 of them in Dolphin:

```
lis   r11, slot@h
lwz   r11, slot@l(r11)
mtctr r11
bctr
```

So the slot just needs to end up holding the export's address, for functions and variables alike. 1640's `XexpBindImageImports` does exactly that when the word is a plain ordinal. It also has a second form, `0001 oooo` followed by `0002 mmmm`, which it turns into a `lis`/`addi` pair. No raw file uses it, but the 26 compressed ones weren't checked.

### `drivers.xex`

Every sample imports it, and in 1640 it holds the display, audio and XMA code. 110 of its 118 exports are 17489 kernel exports by name, and none are in xam. The ones that aren't:

| Ordinal | Function | Imported by the samples? | What to do |
| - | - | - | - |
| 9 | `VdGetDefaultGammaTable` | Yes | [Put back](#entry-points-that-need-something) |
| 10 | `VdGetDefaultMEInitCommand` | Yes | Existing slot 757 |
| 3 | `VdEdramHeap` | No | Stub. It's a variable, so a stub would be wrong if something does import it |
| 47 to 49 | `XAudio*DolbyDigital*` | No | Stub |
| 59 | `NicReadAlphaNicFactoryAddress` | No | Stub |
| 74 | `XUsbcamGetHWConfig` | No | Stub |

## Ordinals

Compared by name, using the PDBs for 1640 and `tools/xex1_tests/xex25/crackdown/names.json` for 1746 and 17489. As with `XEX%`, only names were compared, not arguments.

| Library | Exports | Same on 17489 | Moved | Gone | Runs if stored as ranges |
| - | - | - | - | - | - |
| Kernel | 417 | 36 | 366 | 15 | 34 |
| `drivers.xex`, to the kernel | 118 | n/a | 110 | 8 | 41 |
| xam | 431 | 85 | 318 | 28 | 57 |
| xnet, to xam | 133 | n/a | 133 | 0 | 8 |

Across the 5 samples that's 97 kernel, 43 drivers, 6 xam and 6 xbdm functions, nearly all of which match by name. These need a decision of their own:

| Library | Ordinal | 1640 function | Goes to | Why |
| - | - | - | - | - |
| Kernel | 329 to 332 | `TlsAlloc` and so on | 338 to 341 | `KeTls*` now |
| Kernel | 287, 288 | `RtlFreeAnsiString`, `RtlFreeUnicodeString` | 295, 296 | They share an address in the PDB |
| Kernel | 3, 67 | Several names each | 2, stub | The same aliases as in `xex25_ordinals.py` |
| Kernel | 39 | `HalRegisterShutdownNotification` | 38 | As `XEX%` |
| Kernel | 1, 98, 161, 349, 401 and `*NonVolatile*`, `*ConfigPartition`, `SfcWriteLogical` | Removed | 666 | Not imported by the samples |
| drivers | 14 | `VdInitializeEngines` | 910 | The existing wrapper, see below |
| drivers | 10 | `VdGetDefaultMEInitCommand` | 757 | The existing function |
| drivers | 9 | `VdGetDefaultGammaTable` | 915 | Put back, see below |
| drivers | 12, 19, 24 | `VdGetSystemCommandBuffer`, `VdQuerySystemCommandBuffer`, `VdSetSystemCommandBuffer` | 914, 913, 912 | New wrappers, **not** the `XEX%` ones, see below |
| drivers | 17 | `VdInitializeScalerCommandBuffer` | 911 | A new wrapper, see below |
| xam | 20 to 25 | `XLaunchNewImage` to `XamTerminateTitle` | 420 to 425 | Renamed, as in the `XEX%` table |
| xam | 85, 89 | `XamUserGetMembershipTier*` | 535, 539 | Renamed, as in the `XEX%` table |
| xam | 2, 4, 5, 40, 45, 46, 49, 51, 103, 144, 172, 704, 901, and `PIX*` | Removed, or debug names | 1109 | Not imported by the samples. Only xam 25 of these rows is |

xbdm's 6 imports (1, 9, 28, 30, 36, 72) have the same names in idaxex's tables for later builds, and those tables agree with each other. xbdm needs no remap, but this should be rechecked with the 17489 PDB, as that build isn't on disk.

`xex1tool -i` prints later names for `XEX-` ordinals, and they're wrong. It calls xam 705 `XamShowKeyboardUI`, and the PDB says `XGetVideoFlags`. It calls kernel 41 `HalSendSMCMessage`, and the PDB says `HalReturnToFirmware`. Use the 1640 PDBs.

## Resolving imports

The HV code that matters is at `0x2AD14` to `0x2AEF0`. For a record, it:

1. Checks the address is aligned and inside the image.
2. At `0x2AD88`, reads the second byte of the word, and fails with `C000007B` unless it equals the table's ModuleIndex.
3. Takes the ordinal from the low 16 bits, and runs the remap at `0x2ADC4` if there is one.
4. At `0x2AE38`, if the top byte is 0, writes the export's address to the slot and moves on.

So step 4 is already what `XEX-` needs. Only step 2 is in the way, as an ordinal-only word has a 0 there.

### Options

| | A: rewrite slots in the kernel | B: patch the HV |
| - | - | - |
| Change | Before the first `HvxLoadImageData`, write `00ss oooo` to every slot, with the final 17489 ordinal | Hook `0x2AD88` to skip the check, and add tables to `Xex1HvCave` |
| Ordinal tables | In the kernel, with room up to `0x801D0030` | In the HV, with `0x344` bytes left, shared with everything else |
| Effect on other formats | None | Another branch in code every title runs |
| Works with an encrypted image | No, but there's no such thing in this format | Yes |
| Compressed images | Yes, it's already decompressed by then | Yes |

**This went with A.** Slots aren't covered by the digests, and the image hash check is already off, so nothing notices the change. Their words are already what the HV expects for a data import once the byte is right.

The kernel writes the image itself, at `LDR entry + 0x1C` plus the offset (`XexpLoadRawImage`, called from `0x800A3654`), so it should still be writable at that point. That's from reading the code, and it's the first thing to confirm on hardware.

`0x800A3764` is already hooked by `Xex1LoadImageData`, `r30` is the descriptor being loaded, and `r25` is the loader entry. The rewrite only happens for the first descriptor of a file with the second marker, `XEX-` at `Signature + 4`, which the conversion only writes once the tables have converted. So if they couldn't be, the image is left alone and the HV fails the title on its digest.

A word with anything in its high half gets replaced with `0xFFFFFFFF`, which the HV always rejects. Leaving it isn't enough, because `0001 oooo` passes the HV's check on a table with a module index of 1, and would resolve to the wrong thing. All 963 records in the raw files are plain ordinals, so this has never come up.

### Telling the tables apart

The conversion writes `2.0.1861.k` as both versions, with `k` in the bottom byte saying which library it was:

- The HV's remap skips anything at 1861 or above, so `XEX-` won't go through it at all. The `XEX%` tables aren't involved, which matters because of the [system command buffer](#system-command-buffer).
- 1861 is also the kernel's minimum, so the kernel's version check would pass even if RGLoader hadn't patched it.
- RGLoader's stub at `0xB208` only applies to function thunks, and these are data imports.

The old notes assumed the "below 1838" gate would have to split up for `XEX-`. With this it doesn't.

### Renaming libraries

The kernel loads whatever's in the name table (`XexpResolveImageImports`), so `drivers.xex` has to go. It becomes `xboxkrnl.exe`, which is 4 bytes longer once aligned, so the name table grows along with the tables. `xnet.xex` becomes `xam.xex`, which is 4 bytes shorter. That leaves two names for an exporter. The walker handles that, one entry per name, and `XexpCompleteImageLoad` finds the exporter from ModuleIndex and walks tables by size. `XexpUnloadModules` dereferences each entry once and the walker references each once, so quitting should balance out.

## Entry points that need something

### System command buffer

This is different to `XEX%`, and it's why `XEX-` can't share its wrappers. The plan for this assumed 1640 and 17489 matched, going by the size and where width and height are. They don't. From `D3DDevice_SetSystemCommandBuffer` in the 1640 xam, and `D3DCommandBuffer_Queue` in 17489's:

| Offset | 1640 | 1838 and 17489 |
| - | - | - |
| `+0x00` | Flag | Address |
| `+0x04` | Address | Size |
| `+0x08` | Size | Front buffer |
| `+0x0C` | Front buffer | Format |
| `+0x10` | Format | New word |
| `+0x14` onward | Width, height and the scaler parameters | Same |

Straight through to 445, D3D would have run a size as if it were an address. So all three functions have wrappers at empty slots, which move the words round through a private struct. The wrappers don't share anything with the `XEX%` ones.

The flag is `+0x4AB8` of the device, which is the alpha kit path. `D3DDevice_Swap` only takes a buffer whose flag matches, so with the Xenos path, Get and Query always give it 0. Set drops it, and passes 0 for the new word. I don't know what that word does, but it's dropped in the other direction on `XEX%` as well.

### VdInitializeScalerCommandBuffer

The stack arguments moved, which a check of registers doesn't show. Both functions take 8 in registers.

| Stack | 1640 | 17489 |
| - | - | - |
| `+0x54` | Second filter's parameters | Same |
| `+0x5C` | Buffer | `_HARDWARE_SCALER_PARAMETERS`, `0x580` bytes |
| `+0x64` | Buffer size | Buffer |
| `+0x6C` | n/a | Buffer size |

17489 copies `0x580` bytes from what a 1640 title passes as its buffer, and then writes to an address that's really a size of `0xC8`. 1640 used to work those parameters out itself, with `VdpInternalScalerSetup`, and that's still there in 17489 with the same arguments. So a wrapper calls it into a private buffer, and calls the real function with the stack arguments one slot up. It doesn't touch any registers, unlike the exported `VdInitializeScaler`, which also programs the hardware.

It needs the ANA lock. The first version of the wrapper didn't take it, and `Dolphin.exe` stopped on an assertion at `800E9910`, in `ASSERT_VALID_VIDEO_MODE`. The lock isn't recursive, and the real function takes it too, so the wrapper holds it only around the setup.

I didn't check whether `XEX%` titles have the same problem. It's at ordinal 453 directly in that table, and the XEX% `Dolphin.exe` gets past it, so its D3D has probably already got the new argument.

### Process start

This was the first thing to go wrong on hardware. `Dolphin.exe` loaded, its imports resolved and its code ran, then it stopped on `Assertion failure - code c0000420` at `8009CC90`, which is in `KeTlsSetValue`. The check there is the same on both kernels: that the index is below the process's slot count.

`XEX-` files have no TLS or stack size headers, and they didn't need any, because 1640's `XexStartExecutable` got both from somewhere else:

| | 1640 | 17489, with no headers |
| - | - | - |
| TLS slots | 64, always | 0 |
| TLS data | The PE's TLS directory. None of the samples or CoD2 have one | None |
| Default stack | `SizeOfStackCommit` in the PE header, `0x10000` in all of them | `0x4000`, the minimum |

So `TlsAlloc` returned -1 and the title passed that to `TlsSetValue`. The stack would have been the next problem. `XEX%` isn't affected, as it has headers for both, which get renamed.

`Xex1StartTlsGate` and `Xex1StartStackGate` hook `XexStartExecutable` where it finds no header. Only a file with the `XEX-` marker gets anything different, and it goes through `Xex2dSetTls` and `Xex2dStackSize`, which read the same PE fields 1640's did. The headers can't get new keys instead, because the image isn't in memory yet when they're converted, and they're hashed by the time it is.

The plan missed this because it compared what's in the file and what the imports do, and this is in neither. It's worth expecting more like it: other things `XexStartExecutable` and the loader used to read from the PE. The earlier tests also stopped short of process start, which `xex2d_hv_test.py` now covers.

### GPU addresses

With process start fixed, `Dolphin.exe` stopped on `The GPU appears to be hung!` at `9206F87C`, in `D3D::DeadlockDetector::Check`, with status `0x40110`. That fires when the fence the GPU writes to memory doesn't move for 2 seconds. It took three register dumps to find, all at that break.

| Evidence | Value | Meaning |
| - | - | - |
| Ring base, `7FC80700` | `1FC51000` | From `MmGetPhysicalAddress`, for a ring at `FFC50000` |
| Addresses in the ring's packets | `1FA60060`, `1FA50000`, `1FA4F002` | From clearing the top 3 bits of `FFA6xxxx` and so on |
| Registers 4 and 7, `7FC80010` and `1C` | Not `00FEEFEE` and `F00DF00D` | The second indirect buffer never ran |
| Flush registers, `7FC828BC` | `01B70000` base | Not anything the title's first buffer asked for, so that didn't run either |

The ring base and the packets disagree by `0x1000`. On 1640, `MmGetPhysicalAddress` for the 4KB physical region at `0xE0000000` just clears the top 3 bits. On 17489 it adds 1 to the page number. So 1640's D3D, which clears the bits itself in many places, sends the GPU `0x1000` short of every 4KB allocation. It ran the fence page as commands, and went idle. 1746's D3D has a helper that handles this, so `XEX%` isn't affected.

Those address calculations are compiled all through the title, including anything in its own libraries, so they can't be fixed one at a time. `Xex1PhysicalGate` hooks `MmAllocatePhysicalMemoryEx` instead. While an `XEX-` is running, anything in the title process that would have got 4KB pages gets 64KB ones, from `0xA0000000`, where clearing the bits does give the right address going by the code. The allocator already rounds size and alignment. xam's and the kernel's allocations in the system process are left alone.

This costs memory, as every small allocation now takes at least 64KB. `SetRingBufferParameters` alone makes two of 0x34 and 0x20 bytes. That shouldn't matter on the samples, but it's something to watch on [CoD2](#call-of-duty-2). This worked, as `Dolphin.exe` now draws correctly. What wasn't checked is anything that masks an address in the image, which is mapped differently and would have been wrong on 1640 too.

Ruled out along the way: D3D's own HSIO calibration, as the flag at `801E6FD0` is already 1, the fence packet, which `SetFence` in 17489's D3D builds identically, and the coherency and setup packets, which match 1746's by opcode and register. `7FC80738` holding `01BC3980` is left over from before the title.

### HUD

Opening the HUD in `Dolphin.exe` corrupts the graphics, and they go back to normal when it closes. Not looked at yet. The obvious place to start is the [system command buffer](#system-command-buffer), since that's how xam's HUD reaches the title, and those wrappers have only run against stand-ins until now. Set passes 0 for the word whose purpose isn't known, and 1640's D3D is drawing a buffer built by 17489's xam, either of which could do this.

### VdInitializeEngines

1640's `drivers.dll` reads no arguments. Dolphin's D3D calls it with `li r3, 0x668` and nothing else, so r4 to r7 are whatever's left over, the same bug as [1746](XexPercentSupport.md#vdinitializeengines). `xex25InitializeEngines` handles this as it is, since `0x668` is below `0x10000`.

### VdGetDefaultMEInitCommand

The same 19 words as 1746's, going by the code and its table (`0`, `0x80` up to `0x380`). The existing function at slot 757 can be used. Dolphin calls it with `(buffer, 0xA0)`, the same as 1746.

### VdGetDefaultGammaTable

It's gone by 1746. It returns a pointer to 256 words, which D3D copies into its device (`92069E3C`), so a stub returning 0 would fault. It's at slot 915, with the table as `0x400` bytes of data, since the function has to return a pointer. The table has `c = i * 4 + i / 85` and each word being `c << 20 | c << 10 | c`, and the test compares it with `drivers.dll`'s.

With that and the wrappers, 911 to 915 are all used, and **there are no more empty slots in the export table.** `VdSetSystemCommandBuffer` for `XEX%` was going to need one, see [`XexPercentSupport.md`](XexPercentSupport.md#system-command-buffer). It could share a slot by telling formats apart from the marker, or the table could be extended.

### Not needed

- **`RtlImageXexHeaderField`:** neither the samples nor CoD2 import it or `XexExecutableModuleHandle`, so the [loader entry](XexPercentSupport.md#loader-entry) wrapper isn't used for these. A title that does import it would need sending through slot 898, which the table doesn't do yet.
- **`VdGetCurrentDisplayInformation`:** `0x58` bytes on both, and the two fields D3D reads, at `+0x48` and `+0x4A`, are written the same way in both.
- **`VdSetDisplayMode`:** flag `0x40000000` writes `0x100` to `0x7FC8602C` on 1640, the same as 1838. The conversion keeps the `XEX1` marker, so `Xex1DisplayFlagGate` covers it.
- **Zero key fix at `0x29C20`:** the marker takes care of this too, and these images aren't encrypted.

## Scope

**Titles first.** The goal is the 5 samples and [Call of Duty 2](#call-of-duty-2): raw images importing the kernel, xam, xbdm, `drivers` and `xnet`. `xnet.xex` is in scope because CoD2 needs it. It gets renamed to `xam.xex`, with its own table, and all 133 exports are on 17489's xam by name. Later on, if wanted:

| Thing | What it would take |
| - | - |
| `xshell.xex` | 3 imports from `XAPI.XEX`, which doesn't exist on 17489 |
| Compressed images | Same format on the surface, as `XEX%`, but never run by real code. No sample needs it, but `dash.xex` does |
| System modules | Exports at `0x10300`, `GamerCard.xex`, bound paths and compression. Not a goal, as with `XEX%` |
| Other builds | Ordinals can't be told apart, as tables have no versions. Only the `0x201FF` library list says what a file was built with. The stale `xshell.xex` on the 1746 recovery is 1640 too. I didn't open the 1538 recovery, which is still in its zip, so whether it's `XEX-` isn't known |

**Don't run** `xbupdate.xex`, `mfgbootlauncher.xex` or `processdump.xex`, as they're manufacturing, update and dump tools, and I haven't looked at what they do. See [Don't run these](Xex1Support.md#dont-run-these).

## Call of Duty 2

`D:\Downloads\Cod2 704` is a real game on this format, and it's built on 1640. It's a much better test than the samples, and it changed parts of this plan. Nothing here has been run.

| File | Target in the map | Built | Libraries | Imports |
| - | - | - | - | - |
| `cod2sp_s.exe` | `cod2sp_xenon_rs` | Jul 5, 2005 | `D3D9LTCG`, `XAUD` | 324 |
| `cod2sp.exe` | `cod2sp_xenon_r` | Jul 5, 2005 | `D3D9I`, `XAUDI`, call cap | 328 |
| `cod2mp_s.exe` | `cod2mp_xenon_rs` | Jul 3, 2005 | Not listed | 332 |
| `CoD2MP.exe` | `cod2mp_xenon_r` | Jul 5, 2005 | Not listed | 336 |

The two SP files' library lists both say 2.0.1640 (`XBOXKRNL`, `XAPILIB` and others), so the claim holds up. The folder is 4.9GB, with data in `zone`, `main` and `video`. `assert.log` is dated 2003 and only shows a config running, so it's nothing to go on.

### What it confirms

- **The ordinal mapping, independently.** Each file comes with its linker map, which names every import slot. Reading the ordinal from each slot and looking it up in the 1640 PDBs gives the same name for every slot in both SP builds (321 of 324, and 325 of 328). The remaining 3 are aliases: `RtlSprintf`, `RtlVsnprintf` and `RtlVsprintf`, which the PDB calls `sprintf`, `vsnprintf` and `vsprintf`.
- **Import records.** All are ordinal-only slots with a zero high half, at `0x82000380` onward in all four.
- **Format.** Header hash is correct on all four. Signature, image hash and page digests are all zero, and the module flag is `0x2`.

It doesn't look damaged like the [Crackdown prototype](XexPercentSupport.md#crackdown-prototype). Function addresses from the maps all land on non-zero words (one exception) and about 55% to 70% start with `mflr r12` on the two builds checked. `cod2sp_s.exe` has no cluster starting with `0xFF` padding. With no image hash that's only a good sign, not proof, and the data files haven't been looked at.

### What it adds

| Difference | Samples | CoD2 | What it means |
| - | - | - | - |
| Load address and pages | `0x92000000`, 4KB | `0x82000000`, 64KB (ImageFlags 0) | The same as `PDZ_toplay.exe`, and `Xex1LoadImageData` handles either |
| Image size | About `0x240000` | `0x1EC0000` to `0x3020000` | 125 to 194 descriptors, of up to 4 pages each |
| `SizeOfHeaders` | `0x1000` | `0x2000` | Page descriptors now cross the `0x1000` boundary |
| `xnet.xex` | Not imported | 87 functions, `NetDll_*` | Needed from the start. Same names on 17489's xam, but check the arguments |
| `0x40006` | No | Yes, after the imports | Rewritten and moved, see below |
| `0x18102` call cap | No | `_r` builds only | The same as [`XEX%`](XexPercentSupport.md#open-problems), so don't start the profiler. It's another reason to try `_s` first |
| `VdQuerySystemCommandBuffer`, `VdSetSystemCommandBuffer` | Not imported | Imported | Both directions of the [system command buffer](#system-command-buffer) matter, and both have wrappers |
| xam | 6 functions | 57, including `XamContent*`, `XamShow*`, `XamUser*`, `XNotify*`, `XMsg*` | Much more API surface. All match by name, or are the renames in the table |
| Kernel | 97 across all samples | 136 to 141 | All on 17489 by name, apart from `Tls*`, which are in the table |

**Execution ID.** It's `00000000 00000000 41560385 0000 0000 00000000 00000000`, so the title ID is at `+8`, where XEX2 expects a base version, with the title ID at `+C`. Both are `0x18` bytes, so it's rewritten in place. Left as it is, the kernel would see a title ID of 0.

`XamGetExecutionId` (xam 900) hands back that same struct. The only caller in `cod2sp.exe` is `XVerifySameFamily`, in the title's own library, which reads the publisher with `lhz 8(r11)`. So the title ID is copied to `+C` rather than moved, which leaves it where both of them look. The only thing in the kernel that touches `+8` is `XexpDeltaDecompressHeaders`, which writes a base version when applying a patch, and patches won't apply to these. No wrapper needed. Everything after the title ID is zero in every file that has one, so those fields are left as zeroes.

**Short files.** All four files end before the data descriptor says they should, by `0x2E00` (or `0x2DF0` on `CoD2MP.exe`), in the last block. The samples aren't like this. On 17489 the read goes through `XexpReadLocalFile` to `NtReadFile`, and `XexpLoadRawImage` only checks the status, not how much was read. It asks for a whole block at once when loading the whole image, so the read starts before the end of the file, and should return what's there with a success status. The rest stays zero. That's from reading as far as `NtReadFile` and from how reads normally behave, and I didn't read the file system underneath. If it's wrong, the load stops with `C0000011`.

**Saves and sign-in.** `XamContentCreate` and friends are imported, and the [`XCONTENT_DATA` problem](XContentData.md) applies. So don't expect saves to work right away.

### What the maps are good for

Having symbols for the title itself makes debugging a lot easier. Use `cod2sp.map`, since its `D3D9I` library isn't link-time optimised, so functions like `D3DDevice_Swap` (`0x7CB368` in the map, `0x823CB368` when loaded) survive with their names. Add `0x81C00000` to a map address to get the loaded address.

### First run

`cod2sp.exe` stops on `Assertion failure` at `8175CE50` in xam, which is `XamLoaderSetLaunchData`. The game passes a size of `0x808`, from `main`, `Com_CheckStartupMessage` and others. 1640's `XSetLaunchData` clamped anything over `0x3FC` without saying so, and 17489's does the same but asserts first. So it's harmless, and that assertion is patched out in `rglXam.S`, which leaves the clamp. That means anything the game keeps past `0x3FC` of its launch data is lost across a launch, the same as it was on 1640.

Expect more of these, as 17489's xam has plenty of assertions that 1640's didn't. They're worth reading one at a time, since some will be real.

### Saves

Signing in to `cod2sp.exe` stops on this, from `OpenContextFile` calling `XContentCreate`:

```
***RIP: (pcd->szFileName[0] != NULL) Empty string specified for XCONTENT_DATA szFileName.
```

`XCONTENT_DATA` is `0x108` bytes on 1640 and `0x134` on 17489, so 17489 reads a file name from off the end of the struct. Skipping the break doesn't fix anything. Create's arguments differ on 1640 as well. [`XContentData.md`](XContentData.md) has the details and what a fix needs.

### Which one to run

`cod2sp_s.exe` first. It has no call cap, the fewest imports and the smallest image, and SP is less likely to depend on networking. `cod2sp.exe` is the one to switch to if something needs debugging, because of its symbols. Leave MP until SP works.

## How it fits together

| Part | Where | What it does |
| - | - | - |
| Magic | `xex1MagicGate`, `xex1HeaderFixup` | A third compare |
| Sizes | `xex1Convert` | `XEX2D_INFO_END` of `0x140` and `XEX2D_GROWTH` of `0x44`. The move, directory fix and hash are shared |
| Headers | `xex2dFixHeaders` | Puts fields into the stash where XEX1 has them. Image size, module flags, execution ID, then the `XEX%` key renames and sort |
| Tables | `xex2dFixImports` | Checks everything first, then rewrites the names and tables, moves what's after them, and shares `XEX%`'s digest chain |
| Slots | `xex2dFixSlots`, from `Xex1LoadImageData` | See [Resolving imports](#resolving-imports) |
| Entry points | `xex2d*`, at slots 911 to 915 | See [Entry points](#entry-points-that-need-something) |
| Process start | `xex1Start*Gate`, `xex2dSetTls`, `xex2dStackSize` | See [Process start](#process-start) |
| Physical memory | `xex1PhysicalGate` | See [GPU addresses](#gpu-addresses) |
| Ordinals | `inc/xex2d_ordinals_17489.S` | 144 ranges, 888 bytes. Anything not in a range goes to the stub |

Everything except the dispatch and the gates is in `Xex25Cave`, which still has `0xCC18` bytes free. `Xex1Cave` has `0x160` left.

## What the checks found

These were the checks that could have changed the design, before any of it was written. Two of them did.

| Check | Result |
| - | - |
| Patch slot size limit | The 4BL reads the size from `+0x70` of the flash header, and doesn't check the patch against it. It's `0x10000` on all 5 xeBuild images I looked at, and one has `0x4992` bytes in use, so about 11KB is fine. **JTAG doesn't use slots** and loads from a fixed address in RAM, and I didn't find its limit |
| System command buffer | **Different.** It needs wrappers, [see above](#system-command-buffer) |
| Arguments of imported functions | **One real problem,** and it wasn't in the registers. `pgv3.py`'s check flagged 20 functions. Of the 4 I read, 3 are false alarms from instructions it doesn't know. The rest are data exports and functions that start with a branch, which I went by the pattern on, not by reading each one. Comparing stack arguments found [the scaler](#vdinitializescalercommandbuffer). This only covers the kernel and `drivers`, so xam and xnet are compared by name alone. It also says nothing about behaviour: `XMASetOutputBufferReadOffset` takes the same arguments, but only writes to the context on 1640, and does more than that on 17489 |
| `VdGetCurrentDisplayInformation` | The same, [see above](#not-needed) |
| `0x7FC80F00` | **Not reached.** It's in `sub_92069D58`, the alpha kit path, and `sub_9206D310` only calls that if `VdGetGraphicsAsicID` has its top bit set. 17489 returns `0x11`. It's only compared against `0x4A48` to `0x4A4F` anyway. No debugger session needed |
| Read callback on short files | [Should be fine](#what-it-adds), not proven |
| `XamGetExecutionId` | No wrapper, [see above](#what-it-adds) |
| 1640 XDK | Skipped. The PDBs and CoD2's maps were enough |

`VdIsHSIOTrainingSucceeded` came up along the way. D3D prints an error and skips its ME init if that returns 0. On 17489 it returns a variable that the kernel sets during startup. I'd expect it to be set, but it's something to look at if D3D reports `HSIO training has failed`.

## Testing

In `tools/xex1_tests`, see the README there. All of these run real kernel and HV code in the interpreter.

| Test | Covers | Result |
| - | - | - |
| `xex2d_test.py` | The real `XexpVerifyXexHeaders` on all 40 unique files. Every field, the directory, names, module numbers, the digest chain, the HV's page rule, a second pass | 40 of 40 |
| The same, fuzzing | Bad headers mustn't fault or write past the end | 4,000 runs, no faults. This found two bugs in the first version, now fixed |
| `xex2d_hv_test.py` | The real hook on each image, then the real HV loop from `0x2ACF8`, including the remap, for all 5 samples and all 4 CoD2 files | 1,867 slots, all resolving to the expected export, none to a stub |
| The same, against the maps | Each CoD2 slot's name in its linker map against the function it ended up with. The maps have nothing to do with the PDBs the tables came from | 1,300 slots, all agree |
| The same, process start | The real `XexStartExecutable`, `KeTlsAlloc` and `KeTlsSetValue`. Without the marker this faults at `8009CC90`, the same as the console did. Real XEX2s match plain RGLoader | All pass |
| The same, the rest | The real name walker. Refused slots and bad addresses. The gamma table and ME init against `drivers.dll`'s own. Every wrapper | All pass |
| All the existing tests | XEX2 identical to plain RGLoader, and every XEX1 and `XEX%` test | All pass |

It also found that `xex1Convert` didn't catch a directory count large enough to overflow its size check. That applied to XEX1 and `XEX%` as well, and it's fixed for all of them.

What this doesn't cover is anything that only a console can show: whether the image really is writable at the hook, what the HV does outside the import loop, how the file system handles a short read, and whether any of the 1640 code then behaves on 17489's kernel. `HvxLoadImageData` is stood in for, and kernel functions behind the wrappers are too. Export tables for xam and xbdm aren't in the kernel image, so those only prove the right ordinal arrives.

## Running it

With the usual [setup](Xex1Support.md#setting-up-a-run), and logging on from the start. `build.bat` deletes all of `output`, which has `17489_RGLoader_xex1_xex25.zip` in it, so copy that somewhere first if it's still wanted. Order:

| # | Title | Why |
| - | - | - |
| 1 | `Dolphin.exe` | Same demo as the XEX1 and `XEX%` builds, and the fewest imports |
| 2 | `LightShafts.exe` | One more kernel import, and more D3D |
| 3 | `SceneViewer.xex` | Files, xbdm |
| 4 | `AudioConsole.xex` | The first to use `XAudio*` and `XMA*`, through `drivers` |
| 5 | `UIAuditioning.xex` | The widest use among the samples |
| 6 | `cod2sp_s.exe` | The first real game, see [Which one to run](#which-one-to-run). Copy the whole folder |
| 7 | `cod2sp.exe` | If it needs symbols |
| 8 | `cod2mp_s.exe`, `CoD2MP.exe` | Once SP works |

First, confirm a normal XEX2 and the XEX% `Dolphin.exe` still run, because they have the most to lose. Expect the first failures here:

| Symptom | Most likely |
| - | - |
| `C000007B`, nothing else printed | Magic or flags |
| `C000007B`, `failed to complete load` | A slot's module byte, meaning the rewrite didn't take or was too late |
| `C0000221` | Import digest |
| `C0000225` | A library name that didn't get a module number |
| Fault at the rewrite | The image wasn't writable at that point, which would make [option B](#options) the fallback |
| Crash at a nonsense address soon after start | A bad ordinal or a missing wrapper. Check the slot's value |
| Hang or black screen in D3D | [Runtime differences](#risks) |

## Risks

**D3D is older than anything tried so far.** It's the most likely thing to need real debugging.

- Dolphin has 15 `lis rN, 0x7FC8` against 9 in the XEX% build, so it touches GPU registers directly more often. The one that looked worst, a check for alpha kits, [isn't reached](#what-the-checks-found).
- `drivers.dll` and D3D both split on `VdGetGraphicsAsicID` being at or above `0x80000000` (`r300_*`). 17489 always returns `0x11`, so that takes the Xenos path, as 1640's D3D would expect on a real Xenos.
- It's also possible that 1640 expected an earlier Xenos revision, in ways only a run will show. Its shaders are also compiled for 1640's microcode, in `Media\Shaders`.

**Names aren't behaviour.** This was the source of most of the problems on XEX1 and `XEX%`. The display functions have moved to a different module entirely, so expect at least one more struct or flag like the ones already found. Audio is the least tested, since `XAudio*` and `XMA*` moved too.

**Patch size.** `patches_*.bin` for RGLoader goes from about 7.7KB to about 12.3KB. That's well under the 64KB slot on an RGH image, but [JTAG's limit isn't confirmed](#what-the-checks-found), and a console that stops booting would point there first.

**The slot rewrite assumes a raw or decompressed image, in plain text, at that point.** That's true of everything in this format so far.

**A big step between titles.** After the samples, the only real game is [CoD2](#call-of-duty-2), which uses far more of the API. If it stops working, there's nothing in between to narrow it down with.

## idaxex and xex1tool

Worth knowing when reading its output for this format, and worth fixing there if it matters. None of this affects the plan.

- Prints `Title Exports` for flag `0x2`, using the XEX2 meaning. These are plain titles.
- Prints later names for ordinals, as above.
- Reads the `0x24` byte tables and ordinals correctly, but treats every record as a variable, because the top byte is 0. Functions and variables can't be told apart from the record.
- `xex1tool` can't open a path with a comma, which includes this SDK's folder. Copy files out first.

## Open questions

1. **Is titles only the right scope to start?** `xshell.xex` is the obvious next thing, but it brings in `XAPI.XEX`.
2. **Are there other `XEX-` files worth testing with?** [CoD2](#call-of-duty-2) is raw, so compression still doesn't matter for anything known. A compressed game would change that.
