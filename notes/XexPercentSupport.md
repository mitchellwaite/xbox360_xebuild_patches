# XEX% Support on the 17489 Devkit Kernel

Notes on loading `XEX%` executables, the format used by build 1746 and later until an unknown point before 1838, on top of the XEX1 support in [Xex1Support.md](Xex1Support.md). The patch is in `src/KHV/17489_RGLoader/inc/xex1_17489.S`, with the ordinal tables in `xex25_ordinals_17489.S`. It's built by the same `xex1` flag.

## Status

**`Dolphin.exe` runs on hardware, and the HUD opens and works,** with the [loader entry](#loader-entry) and [system command buffer](#system-command-buffer) fixes. It's the only `XEX%` tested on hardware so far that runs. Everything below passes in emulation, against the real kernel and HV code where that's possible and a model of the HV's rules where it isn't. Getting a title to load won't mean it works, see [Open problems](#open-problems).

| Thing | State |
| - | - |
| Headers: the 21 modules in the 1746 flash image, the 5 samples in `xexpercent_samples` and `PDZNR.exe` | Convert and pass the real `XexpVerifyXexHeaders` |
| Headers: the 53 `XEX%` system modules and samples in the recovery | Convert and pass the real `XexpVerifyXexHeaders` |
| Import digests, module numbers and page rules | Pass, checked on the converted headers |
| Image load, on the 5 samples and `PDZNR.exe` | Pass against the model of the HV's rules. `Dolphin.exe` makes 60 HV calls for its 14 descriptors |
| Import records in the image, on the same 6 | All pass the rules at `0x2AD88` to `0x2AEE0` |
| Ordinal remap | The real code at `0x2ADC4`, for every 1746 export, and every import of the titles above |
| `VdGetDefaultMEInitCommand` | Same result as 1746's own function, run side by side |
| XEX1 and XEX2 | All the existing tests still pass, and XEX2 results match plain RGLoader |
| `0x801C2000` being executable | Works on hardware: `Dolphin.exe` gets past the wrapper there at startup |

Try `XDKSAMPLES\Dolphin\Dolphin.exe` first, with the logged WinDbg setup in [Setting up a run](Xex1Support.md#setting-up-a-run). It isn't encrypted or compressed, and there's an XEX1 build of the same demo to compare it with.

## Samples

| Sample | Where | Built against | Image |
| - | - | - | - |
| `Dolphin.exe`, `LightShafts.exe`, `SceneViewer.exe`, `AudioConsole.exe`, `UIAuditioning.xex` | `Y:\Xbox 360\SDK\xexpercent_samples\XDKSAMPLES` | debug libraries | Raw, not encrypted |
| `PDZNR.exe`, Perfect Dark Zero, 22 July 2005 | `D:\Downloads\idaxex+xex1tool-0.44_ida93sp2` | 1746 | Raw, encrypted with the zero key |
| 21 modules in the 1746 flash image | `retail_1746_1_64MB.bin`. Drop `0x10` bytes after every `0x200` | 1746 | Mostly compressed |

There are four titles in the flash image, and the one at `0x26F000` is flagged as a manufacturing support tool. Don't run that one, see [Don't run these](Xex1Support.md#dont-run-these).

## How it works

The conversion is the same as XEX1's, using the layout below. Fields go into the stash where the XEX1 ones would be, so most of the code doesn't care about the format. It keeps the `XEX1` marker in Signature, so the zero key fix at `0x29C20` and `Xex1DisplayFlagGate` apply as they are.

| Field | XEX% | XEX2 |
| - | - | - |
| Signature | `+0x008` | `+0x008` |
| HeaderHash | `+0x108` | `+0x164` |
| ImportDigest | HVI in the image | `+0x12C` |
| ImageHash | `+0x11C` | `+0x114` |
| LoadAddress | `+0x130` | `+0x110` |
| ImageKey | `+0x134` | `+0x150` |
| ImageFlags | `+0x144` | `+0x10C` |
| HVI address | `+0x148` | n/a |
| AllowedMediaTypes | `+0x14C` | `+0x17C` |
| PageDescriptorCount | `+0x150` | `+0x180` |
| Page descriptors | `+0x154` | `+0x184` |

SecurityInfo grows by `0x30`. MediaID becomes zeroes, and GameRegion becomes `0xFFFFFFFF`. The header hash on a `XEX%` file is `SHA(SecurityInfo + 0x148 to SizeOfHeaders, start of headers to SecurityInfo + 8)`, which the conversion doesn't need, since RGLoader skips that check and it gets recomputed anyway. idaxex calls `+0x108` ImportDigest and `+0x148` ExportTableAddress, and both are wrong.

Things only `XEX%` needs:

- **Directory keys:** imports `0x102FF` to `0x103FF`, build versions `0x201FF` to `0x200FF`, TLS `0x10504` to `0x20104`, and stack size `0x10400` to `0x20200`. The directory is sorted again afterwards, because `RtlImageXexHeaderField` binary searches it. XEX1 uses `0x10400` for exports, so renaming it first is also what makes `XEX%` come out with no exports.
- **Import tables:** ModuleNumber, Version and VersionMin are all 0. They're filled in by library name, and the digest chain is rebuilt back to front. All 27 links in the 1746 flash image's chains were correct before conversion, so it's the same hash as XEX1. The HV checks stay on. A library other than xam, xboxkrnl or xbdm keeps a module number of 0 and fails with `C0000225`. `GamerCard.xex` is the only one seen, on system modules.
- **Compression:** the first block's hash matches with the zero key on the compressed titles checked, using the same format as XEX2. No compressed `XEX%` has been loaded by the real code, though, since nothing here emulates decompression.

## Ordinals

The HV picks a table by the import table's version. The conversion always writes 2.0.1746.0.

| Build in the table | Kernel | xam |
| - | - | - |
| Below 1838 | `xex25KernelTable`, every ordinal up to 606 | `xex25XamTable`, 72 rows |
| 1838 to 1860 | Unchanged | `xex1RemapTable`, as before |
| 1861 and up, or not a 2.0 version | Unchanged | Unchanged |

So everything below 1838 is treated the same for now, whatever it was really built against. That includes XEX1s with an older version, though none have been seen. `XEX-` has its own ordinals, but doesn't go through this. xbdm has no table: every import of the titles above has a 17489 export, with the same name on 1746 where they were compared.

The tables are generated by `tools/xex1_tests/xex25/xex25_ordinals.py`, from the 1746 kernel and xam with their PDBs, against 17489's names. Only names were compared, not arguments, so a function can still have changed what it does.

Ordinals past the end of 1746's exports exist on later versions of dashboards that support XEX%, and all the samples use them:

| Ordinal | Function | How it's known | Goes to |
| - | - | - | - |
| 604 | `XeCryptRotSumSha` | `UIAuditioning.xex` calls it with `(data, size, 0, 0, out, 0x14)`, and its 1838 build imports that | 398 |
| 605 | `KeLockL2` | D3D calls it with `(0, 0x7F100000, 0x20000, 1, 1)` and then `dcbz`s that range. The 1838 build's D3D has the same code, at ordinal 107 | 107 |
| 606 | `KeUnlockL2` | Called with 0 where the 1838 build calls ordinal 108 | 108 |

Without these, 605 and 606 are `XeKeysSaveSystemUpdate` and `XeKeysLockSystemUpdate` on 17489, so these are important to get right. Anything past 606 goes to the stub.

Functions with a decision of their own:

| Ordinal | 1746 function | What happens |
| - | - | - |
| Kernel 442 | `VdGetDefaultMEInitCommand` | [Put back](#me-init) at slot 757 |
| Kernel 298 | `RtlImageXexHeaderField` | Through a [wrapper](#loader-entry) at slot 898 |
| Kernel 445, 454 | `VdGetSystemCommandBuffer`, `VdQuerySystemCommandBuffer` | Through [wrappers](#system-command-buffer) at slots 903 and 908 |
| Kernel 448 | `VdInitializeEngines` | Through a [wrapper](#vdinitializeengines) at slot 910 |
| Kernel 539 | No name in the PDB | `XMAReleaseContext`, going by its neighbours and the same gap on 1838 |
| Kernel 338 to 341 | `TlsAlloc` and so on | Same ordinal, now `KeTlsAlloc` and so on |
| Kernel 39 | `HalRegisterShutdownNotification` | 38, now `HalRegisterPowerDownNotification` |
| Kernel 29 to 32, 67, 78, 337, 412, 570, 576, 584, 587, 594, 595, 597, and ordinals with no export | `ExQueryNonVolatileSetting`, `KeAccessFuses`, `SfcWriteLogical`, `Fdfx*` and others | `XeKeysReserved666`, ordinal 666, which is `li r3, 0; blr` |
| xam 420 to 428, 535, 539 | `XLaunchNewImage` and so on | Same ordinal under a new name |
| xam 978 | `XGetLocale` | 1193, `XamGetLocale`. 978 is now `XamGetLanguage` |
| xam 124, 450, 456, 457, 460, 462, 641, 672, 974, 1105 to 1108, 1111 | Removed | 1109, which is `li r3, 0; blr` |

None of the surveyed titles import a stubbed function, other than `NetDll_XnpUpdateInAddrServiceId` (xam 124) in `PDZNR.exe`. Returning 0 is success for a function that returns a status, and whatever it should have written doesn't get written, so a title that uses one might not cope.

## ME init

1746's D3D calls `VdGetDefaultMEInitCommand(buffer, 0xA0)` and submits however many words come back. It's gone on 17489, and D3D from 1838 onwards builds the packet itself. A stub returning 0 would submit nothing, leaving the GPU's micro engine without its init packet, so a stub isn't an option.

`xex25GetDefaultMEInitCommand` writes the same 19 words as 1746's. It's added to the kernel's export table at ordinal 757, which is empty on 17489 (`0x80080BFC`). 1838's D3D builds the same 19 words itself (`Dolphin.exe` at `9205eff4`), and that build runs on 17489, so the packet should be fine. The rest of how 1746's D3D starts up the GPU hasn't been compared, so if D3D hangs early on, start there.

## Loader entry

`Dolphin.exe`'s first run on hardware stopped with a second chance access violation at `800B3530`, which is the start of `RtlImageXexHeaderField`, reading through a bad `r3`. XAPI's startup code does this, in all five samples:

```
lwz   r11, XexExecutableModuleHandle
lwz   r3, 0x50(r11)
lis   r4, 1
ori   r4, r4, 0x801
bl    RtlImageXexHeaderField
```

The 1838 build has the same code with `0x58`, so the headers pointer moved in `LDR_DATA_TABLE_ENTRY` between 1746 and 1838. The 1838 build also asks for `0x20401` where this has `0x10801`, so that's another key that was renamed. It's the default heap size. No sample has it, so the call returns 0 and XAPI uses its default, but a title that has one would lose it, and the conversion should rename it when one turns up.

`xex25ImageXexHeaderField` is at slot 898, also empty on 17489, and only reached by imports older than 1838. If `r3` is the value at `+0x50` of the running title's entry, it swaps in `+0x58` and carries on. Other arguments pass straight through. This is the only read of `XexExecutableModuleHandle` in each sample. It doesn't help a title getting another module's headers the same way, which none of the samples do.

## System command buffer

Opening the HUD in `Dolphin.exe` stopped on this, from the debug D3D linked into the title:

```
ERR[D3D]: Assertion failure: system.ScalerLock
```

`system` is the struct `D3DDevice_Swap` gets from `VdGetSystemCommandBuffer`. xam fills it in through `VdSetSystemCommandBuffer` when it queues something for the title to draw, which is why nothing went wrong until the HUD opened. It grew between 1746 and 1838:

| Field | 1746 | 1838 and 17489 |
| - | - | - |
| Address, size, front buffer, format | `+0x00` to `+0x0C` | Same |
| New word | n/a | `+0x10` |
| Width and height | `+0x10`, `+0x14` | `+0x14`, `+0x18` |
| Scaler parameters present | `+0x18` | `+0x1C` |
| Scaler parameters, `0x38` bytes | `+0x1C` | `+0x20` |
| Second parameters, `0x38` bytes | `+0x54` | `+0x58` |
| Second parameters present (`ScalerLock`) | `+0x8C` | `+0x90` |
| Size, as copied by the kernel | `0x90` | `0x94` |

The left column is from `D3DCommandBuffer_Queue`'s equivalent in the 1746 `xam.xex` (around `8197a5b4`), and the right from 17489's, which has symbols. 1746's D3D took the height for the flag, saw shifted parameters as changed, and read the wrong word for `ScalerLock`. Without an assertion, as on `PDZNR.exe`'s release libraries, it would just have misread them. The kernel's extra 4 bytes also landed past the end of the title's stack buffer.

Both functions now go through a wrapper at an empty export slot, which calls the real one with a private `0x94` byte struct and copies it back without the new word. `VdSetSystemCommandBuffer` (kernel 467) isn't wrapped yet. The 5 samples don't import it, but `PDZNR.exe` does. If that build calls it, 17489 will read a `0x94` byte struct out of its `0x90` byte one, with the fields after `+0x0C` in the wrong place. It needs the same treatment in the other direction before that title's HUD or system UI can be expected to work.

I don't know what the new word at `+0x10` does. It's dropped, and it's whatever `D3DCommandBuffer_Queue` was passed as its fourth argument. 1746's D3D then draws 17489 xam's buffer as if it were its own, so a wrong looking or missing HUD would be the next thing to look at. `VdGetCurrentDisplayInformation` copies `0x58` bytes on both, so it isn't affected.

## VdInitializeEngines

An earlier PGR3 beta (`Gotham3_R.exe`, July 21, 2005, 1746 libraries) stopped with a second chance access violation at `800EE8D0`, in `VdpLoadMicrocode`, reading through its second pointer. It's a 1746 title, so this is the first difference between those two that's come up:

| Build | Call |
| - | - |
| 1746 | `VdInitializeEngines(0x6D2)`. r4 to r7 are whatever's left in them, and 1746's kernel doesn't read them |
| 17489 reads | r4 is a callback, called once later on if it isn't null. r5 is its argument. r6 and r7 are the microcode, with zero meaning its own |

`xex25InitializeEngines` is at slot 910. It clears r4 to r7 if r3 is below `0x10000`, and otherwise passes everything through.

Other kernel functions imported by this title were compared by the argument registers they read on 1746 and 17489 (`pgv3.py`). That only follows the straight line path, so it's a quick check and not proof. Nothing else stood out. `VdInitializeScalerCommandBuffer` reads `r5` and stack arguments on 17489 that 1746 doesn't, but this title sets them all.

## PGR3 beta data

With the [`VdInitializeEngines`](#vdinitializeengines) fix, the July 21 `Gotham3_R.exe` gets as far as reading its data, then stops with:

```
Missing NULL.tga from the texture bank
assert: groups == GVRace::CarGroups && "Cargroups not equal" - file(.\src\game\GameLogic\GameVars.cpp) line(1095) func(GVRace::Read)
Missing NULL.tga from the texture bank
Access violation - code c0000005 (!!! second chance !!!)
824877e4 817e023c lwz r11,23Ch(r30)
```

Only the assert is a real problem. The access violation comes from the game's assert handler, which draws its message on screen before the UI and shaders are set up. D3D then commits state with no vertex shader, as `+0x315C` of the device is the vertex shader and `+0x3158` the pixel shader. `kb` can't walk this stack. Following the back chain from `dds @r1` by hand gives `82487e04`, `82473f68`, `821033a4`, `821db7c8`, `82177c9c`, and that last frame holds the assert's text.

The assert is bad data in `cache\GameData\Races.ipx`, which is damaged the same way as [Crackdown](#crackdown-prototype), so this folder went through the same kind of recovery. It has three foreign clusters at `0x3C000` to `0x48000`, mostly zeroes, with no directory entries in them, and the file ends in the middle of a string. Its section size still matches the file length, because the right number of bytes were read from the wrong places.

`pgr3_races_fix.py` takes out those clusters. There are no hashes to prove it, but the file's own sizes do at every level: 20 championships and all 81 of their events fit exactly, and all have `groups` of 5. The last three championships are lost, starting with Nurburgring Super Series, as they fell off the end. The repaired file says 20 championships, not 23. Anything that refers to the lost ones by ID hasn't been checked.

Scanning this folder for FATX directory clusters finds nothing, but that scan wouldn't have caught this damage either. Other files could have the same problem, and most of them have no structure to check them with. `Missing NULL.tga` appears because the UI's texture list isn't loaded yet. `NULL.tga` is listed in `commonUI_resource.dat`.

### PGR3: where this stands

Last tested with `Races.ipx` repaired, and `Debug.dat` and `Race.dat` renamed so they don't load. The July 21 build loads, plays the city fly-through and the countdown, then faults as the screen changes to `Ingame\HUD.lua`:

```
Access violation - code c0000005 (!!! second chance !!!)
82469da4 a14b0000 lhz r10,0(r11)
```

This is heap corruption, and the fault is only where it got found. `82469DA4` is XAPI's heap code committing more memory for a `0x800` byte allocation, probably Lua, walking the block headers of the heap at `0x01780000` from the start. The block at `0x01E92210` holds `A8832E38 29CB2E3D 3BF4A988...` instead of a header, which reads as a size of `0xA8830` and lands past the committed end at `0x01F16000`. Those bytes aren't in any file in the game's folder in either byte order, so they're compressed on disk or generated at runtime. What wrote them isn't known.

**Next steps, in order:**

1. **Catch the overwrite.** While the game is loading, break in and run `windbg/kd_heapwatch.txt`, which logs each write to `0x01E92210`. The last `HEAPWATCH` line before the crash should name the writer, most likely with a `value` of `A8832E38`. If `r8` at the crash isn't `01E92210`, the layout moved, so change the address in the script and try again. That would also point to timing or uninitialised memory.
2. **Fix `XCONTENT_DATA`.** See below. It's needed for saves either way, but nothing shows it caused this crash.
3. **Check the `Debug.dat` link if it matters.** See below.

**`XCONTENT_DATA` isn't fixed.** It's `0x108` bytes on 1746, as `XamContentCreate` copies that much, and the game asserts that a 25 item enumeration buffer is exactly `0x19C8` bytes. 17489 has `szFileName` at `+0x108`, so it reads past the end of the title's struct. That gives this break on a debug xam, which can be skipped with `g`:

```
***RIP: (IsValidContentFileName(pcd->szFileName)) Invalid filename specified for XCONTENT_DATA szFileName.
```

It looks like the scan for downloadable content that triggers it (`82188670`). `ReadSaveGame` and `WriteSaveGame` use the same call. Enumeration could also write bigger records than the title's buffers expect, so check that against this corruption. See [`XContentData.md`](XContentData.md) for the layouts and what a fix needs.

**What each earlier symptom turned out to be**, in the order they came up:

| Symptom | Cause | State |
| - | - | - |
| Fault at `824877E4` | The assert handler drawing with no vertex shader, after `Cargroups not equal`. Device `+0x315C` is the vertex shader, `+0x3158` the pixel shader | Fixed by repairing `Races.ipx` |
| `[XNET:1] Warning: accept failed: 10022` in a loop | A socket that isn't listening. `UIDebug` on port 27015, a debug TCP/IP channel and `CXBSocket::Accept` all poll `accept`. It stopped by itself, and which one it was wasn't found | Not seen since |
| Black screen, HUD audio only | The main thread sits in the assert handler at `82177D24`, polling for bit `0x1000`, probably A, on a screen that can't show the message. The ring buffer doesn't move, so `Swap` doesn't run, and the guide is drawn through `Swap` | Went away with `Debug.dat` removed |
| `AxisNo==0 \|\| AxisNo==1` at `controller.h` line 534 | `AxisNo` was `0x272AB92B`. Those bytes are at `+0x11` of `Debug.dat`, and the game's defaults write a 32 bit 0 to that offset of the settings block at `0x82CFB278`. The code carrying it to the assert wasn't traced | Same |

`Debug.dat` doesn't look like settings, as the defaults are nearly all 0s and 1s, so its contents were probably replaced in the recovery. The game can write that file back from its own settings, so a new one should be fine. `ControllerConfig` in `PGR3.ipx` has 0 entries, against 4 in the August build, but the file's sizes all agree, so that's how this build is. `kb` can't walk title frames: use `dds @r1`, and follow the back chain, with the return address at 8 bytes below each frame's top.

To set this up again, copy `tools/output/pgr3/cache/GameData/Races.ipx` over the one in `DEVKIT\pgr_xex25\cache\GameData` on the console, and leave out `Debug.dat` and `Race.dat`. The analysis scripts are in `tools/xex1_tests/xex25/pgr3`.

## Code space

| Place | Used up to | Limit | Holds |
| - | - | - | - |
| `Xex1Cave` | `0x801C1DF0` | `0x801C2000` | Conversion, as before |
| `Xex25Cave` | `0x801C23B0` | Data at `0x801D0030` | What only `XEX%` uses |
| `Xex1HvCave` | `0xBCBC` | `0xC000` | Remap code and tables |

`Xex25Cave` is past the 4KB page that's known to run. It's in the same 64KB page, and RGLoader's patches at `0x10E0` also make image memory executable, so it should be fine, but that hasn't been tested. Only a `XEX%` can reach that code, so if it's wrong XEX1 and XEX2 aren't affected. An instruction storage exception at `801C2xxx` while loading a title means this is the problem.

Patch files are bigger now: `patches_*.bin` for RGLoader with `xex1` set is about 7.5KB, a little more than the largest in `output` before this (7,048 bytes). I haven't confirmed the actual limit on a patch slot's size. Check this first if a console stops booting.

## Tests

In `tools/xex1_tests`, see its README. `xex25_test.py`, `xex25_hv_test.py` and `xex25_load_test.py` are the new ones, and the conversion is fuzzed for both `XEX%` and XEX1. Writing the first of these caught `GamerCard.xex` being given xam's module number.

## Crackdown prototype

`CW_RW4_Release.exe` (Sep 1, 2005, 1746 libraries) fails with `LDRX: failed to complete load of module` and `C000007B`. The patch isn't at fault: the file was damaged when it was recovered, and the HV is right to reject it. `xex25_rebuild.py` repairs nearly all of it. The rebuilt file passes every check here, but **hasn't been run on a console**.

**The cause.** The file was recovered from a devkit's FATX drive by reading clusters in a straight line, and it wasn't contiguous on the disk. `0x4000` is a FATX cluster, and the extra clusters start on a cluster boundary of the file. Some are directory clusters, with entries like `0x0C 0x00 "Arial_16.tga"` followed by `0xFF` padding, and the names (`UIAuditioning.xex`, `SceneViewer.xex`, `default.xprp`) belong to other files on that drive. The rest are parts of other files. Because the recovery kept the file's length, the same amount fell off the end. `x_Crash_CW.exe` in the same folder has 3 such clusters, and `PDZNR.exe` has none.

That explains all of the symptoms, as everything after the first foreign cluster sits later than the headers say:

| Thing | Where the headers say | Where it was in the file |
| - | - | - |
| Import thunks | `0x822F64B0` | `0x1C000` later. The header's address held part of a jump table |
| Entry point | `0x82CAD848` | `0x344000` later |
| Import variable slots | `0x841F06B8` | Gone, see below |

Deleting the clusters from the decrypted data doesn't work, which held this up for a while. The image is AES-CBC, so the block after each cluster decrypts wrongly until they're removed from the ciphertext.

**The repair.** The signed hash chain decides what stays, so none of it is a guess. Each descriptor that hashes in one piece anywhere in the stream is an anchor, and the clusters between two anchors are tried until the descriptors in between hash correctly. Of the 156 descriptors:

| Result | Descriptors | Notes |
| - | - | - |
| Hash correct | 155 | Includes the 62 that are signed as all zero |
| Not proven | 1 | Number 136, image `0x21C0000` to `0x2200000` |

209 clusters came out, `0x344000` bytes, which is exactly the final offset. Descriptors 2-3 have 6 foreign clusters, 11 and 20 have 1 each, and 45 has an unbroken run of 201.

The output is unencrypted, with the original block table. It's also the same size as the original, as the end of the stream is zeroes either way.

**What's lost.** Descriptor 136 fell off the end of the file, and nothing from it is anywhere else in the stream. It holds three things:

| Section | Image | What happens to it |
| - | - | - |
| End of `.data` | `0x21C0000` to `0x21E725C` | Zeroes, which isn't proven right. See below |
| `BINKDATA` | `0x21E7280`, `0x4A3C` bytes | Zeroes, which is wrong if it has any initial values. Only code in the `BINK` section uses it (31 references), and `.text` calls into `BINK` from 35 places |
| `.idata` | `0x21F0000`, `0xE43` bytes | The import slots are regenerated, and the rest stays zero as nothing uses it at runtime |

For `.data`, code refers to 910 addresses in that range. 482 of those can be mapped to `PDZNR.exe`, through code that matches exactly, as it's on the same libraries. For 404 of them it's zero in that title's intact image. Most of the other 78 are a run of objects `0x114` bytes apart, that also match more than one place in `PDZNR.exe`, which has a vtable pointer there. Each has one store in Crackdown's code, so they're probably written at startup, but I didn't confirm it. 80 addresses are read, never directly written, and can't be mapped, so they're the most likely problem. Within four levels of calls from the entry point there are 17 references to this range, and 9 of them are reads, so if it fails early, look at those first.

Import slots are `00ss oooo`, the same as the thunk after them, so 302 of the 313 just copy their thunk's ordinal. The other 11 are data imports with no thunk, and had to be worked out:

| Slot | Import | Evidence |
| - | - | - |
| `841F09B0` | `VdHSIOCalibrationLock` (447) | Critical section around `VdReadWriteHSIOCalibrationFlag`, the same as `PDZNR.exe` and the samples |
| `841F0A54` | `VdGlobalDevice` (446) | Code matches `PDZNR.exe` |
| `841F0A58` | `VdGlobalXamDevice` (591) | Code matches `PDZNR.exe` |
| `841F0A70` | `ExLoadedCommandLine` (429) | `lwz r3, slot; blr`, in `PDZNR.exe` and all the samples |
| `841F0AD8` | `KeDebugMonitorData` (90) | Code matches `PDZNR.exe` |
| `841F0AF0` | `ExThreadObjectType` (27) | 8 exact matches in `PDZNR.exe` |
| `841F0B1C` | `ExTimerObjectType` (28) | Same neighbouring functions as `PDZNR.exe` |
| `841F0B2C` | `ExSemaphoreObjectType` (23) | Exact match in `PDZNR.exe` |
| `841F0B38` | `ExEventObjectType` (14) | Exact match in `PDZNR.exe` |
| `841F0B64` | `KeTimeStampBundle` (172) | `lwz r3, 0x10(slot); blr`, in `PDZNR.exe` and all the samples |
| `841F0C18` | `XboxHardwareInfo` (342) | **Inferred.** Tests the low bits of the first word, next to the XMA format check. No other title has this code to compare with, but it's the last common data import left and the samples read it the same way |

**Results on the rebuilt file:**

- `xex25_test.py`: converts and passes the real `XexpVerifyXexHeaders`.
- `xex25_load_test.py`: all 156 descriptors load in 620 HV calls, and there are no bad import records (489 before).
- `xex25_hv_test.py`: all imports remap, by name. `NetDll_XnpUpdateInAddrServiceId` goes to a stub, as on `PDZNR.exe`.
- The entry point is `mflr r12`.
- `xex1tool -l` still says `Invalid image hash!`, because of descriptor 136. That's expected. `xex1` builds of the patch don't check image hashes, so it doesn't stop it loading.

To reproduce it:

```
python xex25_rebuild.py <CW_RW4_Release.exe> <out.exe> --data 841F09B0=447,841F0A54=446,841F0A58=591,841F0A70=429,841F0AD8=90,841F0AF0=27,841F0B1C=28,841F0B2C=23,841F0B38=14,841F0B64=172,841F0C18=342
```

It should work on other files recovered the same way. `xex25_load_test.py` showing bad records and `xex1tool` showing an invalid hash is how to recognise one. Check what's at the end of the image first. On `x_Crash_CW.exe` the three clusters come out and 10 of 11 descriptors are proven, but its last one has real data in the part that's lost.

**On hardware.** The rebuilt executable loads and starts. It then stops with a second chance access violation at `82F492FC`, `lwz r10, 0xC(r10)`, in the code that walks a RenderWare arena's dictionary after loading it:

```
r10 = types[entry.typeIndex]     entries are 0x14 bytes, the index is at +0x10
call r10->[0xC]
```

Which file it was reading hasn't been confirmed, but the game's data came from the same recovery, so the most likely cause is a damaged arena rather than the executable.

**The data files.** 18 of the 1,312 files in the folder have FATX directory clusters in them, which only counts the kind that can be recognised. There are no signed hashes for these. `.dff` files are RenderWare chunk streams though (id, size, version), so the sizes form a chain, and a spliced cluster breaks it:

| File | Chain | Notes |
| - | - | - |
| `gfxtest.dff` | Reaches the exact end | No arena problems. An intact chain doesn't prove the contents, but it's a good sign |
| `billlevel.dff` | Reaches the exact end | 3 of 56 arena magics have odd tables, which might be false matches |
| `GameplayStreaming.dff`, `devfrontend.dff` | Reach the exact end | |
| `fullcity.dff` | Broken at `0x46268` | The level `UserStartup.ini` selects. The next good header is 439 clusters on, about 7MB of a 15MB file, and the real data is lost off the end |
| `global.dff` | Stops at `0xF2A4` | 69 directory clusters. It uses a table of names and hasn't been worked out. See below |
| `gangwar.dff` | Broken at `0x3C4E9B0` | Lost the end of the file |
| `gameplaytest.dff` | Broken at 0 | Doesn't start with a chunk |

Also damaged: `Audio\Music.xwb` (84 directory clusters), `AI\game.kbf` (2), `Streaming\AI_mission_pj.pdl.resblock` (4), 8 `Phy_*.resblock` files, and one `.bik`.

The executable loads `global.dff` through `StartUp::LoadGameDatabaseFile(RWS_GLOBAL_FILE)`, so it may be needed for every level. There's a `globallevel` console command, described as "changes global file", and `GlobalsInDesign` ("loads Global files in design builds or not"), neither of which have been tried.

Removing the directory clusters from a data file is easy, but it can't bring back what fell off the end, and without hashes the result can only be checked for structure. `fullcity.dff` can't be fully recovered from this copy.

**Where this stands, as of November 3, 2026.**

- Rebuilt executable: `tools/output/crackdown/CW_RW4_Release_patch.exe`. That folder is ignored by git, but `xex25_rebuild.py` makes it again with the command above. Copy it over the one in `DEVKIT\CW_RW4`.
- It faults at `82F492FC`, and I haven't confirmed which file it was reading.

Next, in this order:

1. In `UserStartup.ini` on the console, change the level to `xuifrontend_level "gfxtest"` and launch it.
2. If it faults in the same place, also add `globallevel "gfxtest"`. How that command gets used is a guess.
3. If `gfxtest` gets further, try `billlevel`.
4. Each time, keep the newest `Spew_*.txt` from `DEVKIT\CW_RW4\LogFiles` on the console, plus `r` and `kb` from WinDbg. The `Spew_0001.txt` in the download is from the original devkit. `r10` at the fault, and the last asset in the log, should say which file is to blame.
5. If `global.dff` is required and can't be avoided, repair it: remove its 69 directory clusters, then use its name table to check the structure. Only structure can be checked, and what fell off the end stays lost.

Another copy of the prototype would be better than any of this, as `fullcity.dff` can't be recovered from this one. The scripts from this investigation are in `tools/xex1_tests/xex25/crackdown`, see the README there.

## Open problems

In the order I'd expect to hit them:

1. **Execution ID.** `XEX%` has no `0x40006`. Some have `0x40008` instead, which isn't the same layout: `PDZNR.exe` has its title ID in the third word and `0x40006` has it in the fourth. The samples have neither. The kernel and HV seem to handle it being missing, so it shouldn't stop a load, but the title ID will be 0, which may matter for content and saves. Converting it would be a small job.
2. **Library and API behaviour.** 1746's D3D and XAPI are older than 1838's, and only names were compared. The samples don't import `VdSwap`, `VdGpuClockInMHz` or `VdVerifyMEInitCommand`, which their 1838 builds do, so D3D's route through the kernel is different to what's been tested on XEX1. Expect problems like the [black screen](Xex1Support.md#the-black-screen). Whether these titles use the display flag the same way hasn't been checked.
3. **`XexGetProcedureAddress` isn't covered,** only imports, same as XEX1. It also has no idea about the slot at 757 being special, though nothing should ask for that.
4. **Call cap.** The samples have `0x18102` and two thunks for it that aren't in any import table, so they never get resolved. Nothing in `Dolphin.exe` calls them. The kernel only reads that key in `ExpEnableDisableCallAttributedProfiler`, so starting the profiler on one of these would be a bad idea.
5. **Low image flags.** `HvxCreateImageMapping` acts on bits `0x6` at `0x2C844`, and they're kept as they are. None of the samples or `PDZNR.exe` set them, but some flash modules do. Those may fail to load, which is fine for the manufacturing tool.
6. **Patch files and system modules.** As for XEX1, see [Limitations](Xex1Support.md#limitations). Bound paths still apply to system modules, and none of them have been a goal here.

## Going further back

`XEX-` now has its own notes, in [XexMinusSupport.md](XexMinusSupport.md). The "below 1838" gate didn't need to split, because its tables are written with a version the HV's remap skips, and its ordinals get handled in the kernel. It used up the last empty export slots, which matters for the `VdSetSystemCommandBuffer` wrapper this format still needs.
