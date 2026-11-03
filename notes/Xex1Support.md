# XEX1 Support on the 17489 Devkit Kernel

Notes from getting XEX1 executables (devkit build 1838) running on the 17489 kernel. The patch itself is in `src/KHV/17489_RGLoader/inc/xex1_17489.S`, and the comments at the top of that file cover how it works.

## Status

`Dolphin.exe` (an 1838 XDK sample) loads and runs at full speed with a picture, on RGLoader 17489, on a Falcon over VGA, after a clean reboot.

To build it, add `.set xex1, 1` to a `khv_vfuses_*.S` file in `17489_RGLoader`. It's off by default.

| Thing | State |
| - | - |
| Dolphin, RGLoader `khv_vfuses_sb.S` with `xex1` set, Falcon | Works on hardware |
| Quitting back to xshell | Clean, seen on hardware |
| The other XEX1 samples (62 unique header sets) | Headers and page descriptors pass in emulation. Only the ones under [Tested titles](#tested-titles) have run on hardware |
| RGLoader `flash` and `jtag` with `xex1` set | Assemble, not tested |
| Perfect Dark Zero prototype, `PDZ_toplay.exe`, RGLoader with `xex1` set | Works on hardware, played with no problems seen, and audio seemed fine, see [below](#perfect-dark-zero-prototype) |
| Perfect Dark Zero prototype, `PDZ_totest.exe` | Not tried on hardware |
| Project Gotham Racing 3, `Gotham3_R.exe`, RGLoader with `xex1` set | Works on hardware, with or without a debugger, see [below](#project-gotham-racing-3-beta) |

Setting `xex1` changes behaviour for XEX2 too:

- `HvxLoadImageData` no longer checks image hashes, for anything.

RGLoader already skips the old import check, and patches out the kernel's signature and header hash checks (`0xA0994` and `0xA09F0`), with or without `xex1`.

## Tested titles

XEX1 titles run on hardware, on RGLoader 17489 with `xex1` set, on a Falcon. "Works" means the title seemed to work fine when played, so it isn't a full test of each one.

| Title | File | Result | Build tested on |
| - | - | - | - |
| Project Gotham Racing 3 beta | `Gotham3_R.exe` | Works, apart from the [showroom crash](#project-gotham-racing-3-beta), which is a bug in the beta's own files | Ordinal remap. The full race and no-debugger run were on the 1838-only gate, and it reached the start screen on the wider gate |
| Marble Blast Ultra beta | `XenonTSE.exe` | Works | Ordinal remap, wider gate |
| Dolphin (XDK sample) | `Dolphin.exe` | Works | Ordinal remap, wider gate |
| LightShafts (XDK sample) | `LightShafts.exe` | Works | Ordinal remap, wider gate |
| Perfect Dark Zero prototype | `PDZ_toplay.exe` | [Works](#perfect-dark-zero-prototype) | Before the ordinal remap, not retested. It imports ordinal 457 and the moved content calls, so it now behaves differently |

All four titles on the wider gate were run with WinDbg attached, and the log shows no assertions or access violations from them, other than the PGR3 showroom crash.

## What it took

Each of these is a separate problem. Fixing one only uncovered the next, so a title that gets further than before isn't necessarily close to working.

| # | Symptom | Cause | Fix |
| - | - | - | - |
| 1 | Load rejected | Kernel only accepts the `XEX2` magic, and SecurityInfo has a different layout | `Xex1MagicGate` and `Xex1HeaderFixup` |
| 2 | `C0000221` | XEX1 page descriptors are bigger than the HV allows | `Xex1LoadImageData` splits them, NOP at `0x2A578` |
| 3 | Crash at `00000000` | RGLoader stubs every old function import with `li r3, 0` | `b 0x8` at `0xB224` |
| 4 | Black screen, title running fine | `VdSetDisplayMode` flag `0x40000000` means something else on 17489 | `Xex1DisplayFlagGate` |
| 5 | `C000007B` from `HvxResolveImports`, encrypted titles only | The HV decrypts the image key with the retail key, so the image is garbage | Marker check at `0x29C20` |
| 6 | Assertion `c0000420` in xam, then a lock-up | xam ordinals moved after 1838, so imports resolve to the wrong function | `xex1RemapOrdinal` at `0x2ADC4` |

## Format differences

| Field | XEX1 (1838) | XEX2 (17489) | Notes |
| - | - | - | - |
| Size | `+0x000` | `+0x000` | Grows by `0x1C` |
| ImageSize | `+0x004` | `+0x004` | |
| Signature | `+0x008` | `+0x008` | First word becomes the `XEX1` marker |
| InfoSize | n/a | `+0x108` | Always `0x174` |
| ImageFlags | `+0x158` | `+0x10C` | Masked with `~0xCC000038` |
| LoadAddress | `+0x130` | `+0x110` | |
| ImageHash | `+0x11C` | `+0x114` | |
| ImportTableCount | HVI in the image | `+0x128` | From the `0x103FF` header |
| ImportDigest | HVI in the image | `+0x12C` | Computed from the first table |
| MediaID | `+0x144` | `+0x140` | |
| ImageKey | `+0x134` | `+0x150` | |
| ExportTableAddress | `0x10400` header | `+0x160` | |
| HeaderHash | `+0x108` | `+0x164` | Recomputed |
| GameRegion | `+0x154` | `+0x178` | |
| AllowedMediaTypes | `+0x160` | `+0x17C` | |
| PageDescriptorCount | `+0x164` | `+0x180` | |
| Page descriptors | `+0x168` | `+0x184` | |

Other things worth knowing about the format:

- **Encryption:** all 7 encrypted XEX1 samples, and PDZ, use the zero devkit key. On 17489 the HV uses that key when its first signature check passes (`0x29C84`), but a converted XEX1 can fail that check, as `0x206DC` only covers a malformed public key. RGLoader's retail decryption patches then pick the retail key at `0xF0`, which is what the marker check at `0x29C20` avoids.
- **Region:** titles have `0xFFFFFFFF`. System modules have 0 with the region free flag (`0x20000000`). Both pass.
- **Import tables:** the chain is `SHA(table + 4, 0x24 + 4 * ImportCount)`, with each table holding the digest of the next. 11 of the 54 samples with imports have padding after the imports that isn't hashed, so `TableSize` can't be used to hash them.
- **Import thunks:** four words, `01ss oooo`, `02ss oooo`, `mtctr r11`, `bctr`. The HV overwrites the first two with `lis r11` and `addi r11, r11`.
- **Page size:** bit `0x10000000` of ImageFlags has to match bit `0x10000000` of the load address, or `XexpLoadFile` rejects it. All the samples are consistent.
- **Making room:** SizeOfHeaders can't change, because it's also the file offset of the image. The extra `0x1C` bytes come from the alignment gap before the last optional header, or the slack at the end of the headers.

## Page descriptors

The format is the same as XEX2, but the size isn't.

- XEX2 has one descriptor per 64KB at most, never crossing a 64KB boundary. `HvxLoadImageData` fails anything else (more than `0x10000` bytes, or crossing a boundary) and the kernel reports that as `C0000221`.
- XEX1 has one descriptor per section. Dolphin has 9 descriptors for `0x1E9000` bytes, and the largest are `0x40` 4KB pages. 43 of the 62 unique samples break the rule.

The headers have no room for more descriptors, so the kernel hook makes one HV call per 64KB instead (Dolphin's 9 become 39). XEX2 descriptors already fit, so they reach the HV as one call with the same arguments as before.

The HV hashes each call against a chain, and that hash covers the whole descriptor, so a piece of one can't match. That's why the hash check has to be off. The hashes in the XEX1 files are correct, it's only the split that breaks them.

## RGLoader's import stub

RGLoader hooks `HvxResolveImports` at `0x2AE7C`, the instruction that writes a thunk's first word, and branches to `0xB208`. If the import's version is older than the exporter's minimum, it writes `lis r11, 0x3860` to the thunk, which is `li r3, 0` as an instruction. The comment there says it fills unresolved ordinals, but the only condition that triggers it is the version check. Newer imports skip it, because the `blt` at `0xB214` jumps past the `lis`.

XEX2 imports are never below the minimum, so this never fires for them. For XEX1 it hits every function thunk. Data imports go down a different path, so they were fine, which made this confusing to read:

```
921d09ec  38600000  li    r3, 0                  <- should be lis r11, 0x800B
921d09f0  396b3530  addi  r11, r11, 0x3530       <- correct
921d09f4  7d6903a6  mtctr r11
921d09f8  4e800420  bctr
```

`r11` still held the module handle from the code before the call, so the jump went to `0x30000EC8 + 0x3530 = 0x300043F8`, which is `looP` fill in pool memory. The crash at `00000000` that showed up in the debugger was a second fault. The first one was handled, and while running the exception handler, execution ended up in the middle of `__restgprlr`, which loaded `LR` as 0 and returned to it. `.cxr` on the context record from the stack (`7001eb00`) is what showed the real fault.

## xam ordinals

xam's exports were reshuffled after 1838, and nothing fails at load because the moved ordinals still exist. `Gotham3_R.exe` stopped here:

```
Assertion failure - code c0000420 (first chance)
8178e6d8 0fe00019 twi 31,r0,25
```

Ordinal 457 was `XamCustomSetBannerImage` on 1838. On 17489 it's `XamGetDefaultImage`, which traps when its first argument is 3 or more, and the game passes a texture pointer. Entering `gh` got past it, and the game carried on to the start screen. Without a debugger the console locked up, and with the remap it no longer does. The same import with a null texture calls it with `r3=0, r4=0`, which would write through a null pointer instead.

Comparing 1838's `xamd` exports, named with its PDB, against 17489's found 71 moved ordinals, and functions that are gone. Six of the moved ones are PGR3 imports: `XamContentDelete`, `XamContentCreateEnumerator`, `XamCreateEnumeratorHandle`, `XamGetPrivateEnumStructureFromHandle`, `XamEnumerate` and `XamContentGetDeviceState`.

`xex1RemapOrdinal` in `xex1_17489.S` fixes the index into the export table in `HvxResolveImports`. It leaves `r26` alone, because the thunk's second word gets checked against it afterwards. It only acts on xam tables with a 2.0 version older than 1861, which is where XEX2 starts, so it doesn't affect XEX2 and doesn't need the marker. The table is from 1838. 1839's xam has the same exports at the same ordinals going by the code (658 of 662 functions start the same, and the other 4 aren't moved anywhere). Every XEX1 surveyed imports xam at 1838 or 1839. The code and table are at `0xB500` in the HV.

| 1838 ordinals | What happens to them |
| - | - |
| 70 moved | Sent to the new ordinal, from the table |
| 450, 456, 457, 460, 462 | Removed, and the ordinal is now something unrelated. Sent to 1109, which is `li r3, 0; blr` |
| 427 | Left alone. Several functions share its address in the 1838 PDB, so the name is ambiguous |
| 420-426, 428, 535, 539, 974 | Left alone. Same ordinal under a new name, going by the names only |
| 672, 675-677 | Left alone. These have no 17489 export. Only `updater.xex` imports any of them |
| 1105-1107 | Left alone. No surveyed XEX1 imports them |

Things to keep in mind:

- **Only names were compared.** A function with the same name could still have different arguments.
- **`xex1tool -i` shows 1838 names for these ordinals.** They all matched the PDB for PGR3's imports, so a modern table is what's misleading here. For 17489, use `symsrv_17489\xamd.dll\55EFF5E6850200`, which has the trap at the same address as the running xam.
- **`XexGetProcedureAddress` isn't covered,** only imports.
- **`xex1tool` can't open a path with a comma in it.** It prints `Error opening XEX file`. Copy the file somewhere else first.

An audit of all 35 unique XEX1s found at 1838 (the recovery's `N` folder, the earlier scan, PGR3 and both PDZ builds), covering 459 xam, 426 kernel and 37 xbdm ordinals, by name after the remap:

- **xam:** every import reaches the 1838 function by name, except the removed functions sent to the stub, renames at the same ordinal, and `updater.xex`'s three missing ordinals. Both PDZ builds import 457 and the content calls too, so they get the remap as well.
- **Kernel:** only ordinals 38 (`HalRegisterShutdownNotification`, now `HalRegisterPowerDownNotification`, imported by xam and xbdm only) and 479 (`VdVerifyMEInitCommand`, a known stub) differ among what's imported. In the full export table, 66, 413, 586 and 592 also differ, but nothing surveyed imports them. 592 (`XeKeysHmacMd5UsingKey`) is now `XeKeysSaveBootLoaderEx`, so a title that did import it would be calling something dangerous.
- **xbdm:** every import has the same name. The 17489 side used `xbdm.dll` `52292916c4000` from the SDK, as the build in `symsrv_17489` (`55EFF880c4000`) isn't on disk.

`remap_test.py` runs the real hook. [Project Gotham Racing 3](#project-gotham-racing-3-beta) has the result on hardware.

## The black screen

Dolphin's 1838 D3D passes `0x40000000` to `VdSetDisplayMode`. The two kernels do different things with it:

| Kernel | Effect of flag `0x40000000` |
| - | - |
| 1838 | Writes `0x100` to `0x7FC8602C` |
| 17489 | Sets bit 0 of `0x7FC87938` |

The title was fine. `VdSwap` was being called every frame, and the front buffer held `80400000` (`0x00004080` byte-swapped, a dark blue). The display registers were scanning that buffer at 1280x720. Comparing 384 display registers against xshell left `0x7938` as the one that stood out (`701` vs `700`), and writing `700` to it live brought the picture back at full speed.

I don't know what that bit actually does, only that clearing it fixes the picture on VGA. Other video outputs haven't been tried. `0x6024` also differed (`1c889e4b` vs 0) and didn't need changing.

The gate only ignores the flag when the running title's SecurityInfo has the `XEX1` marker. It walks `XexExecutableModuleHandle` -> `+0x58` -> `+0x10` -> `+8`.

## Kernel structures that didn't change

These were all checked, and were ruled out as causes:

- Kernel export module number `0x45DC17E0` is the same in 1838, 1888 and 17489.
- xam's `0xFCA15C76` is the same in 6717, 12611 and the XEX1 imports. 17489's own xam wasn't checked for this. PGR3's xam imports do resolve on it.
- Kernel export minimum version is 1861 on both 1888 and 17489. 1838's is 1800.
- Dolphin's 92 kernel imports resolve to the expected 17489 functions. `VdVerifyMEInitCommand` is a stub on 17489, which Dolphin doesn't seem to mind.
- `KeDebugMonitorData+0x18`, thread ID at `KTHREAD+0x14C`, and `__C_specific_handler` (same instructions in both, apart from call targets).
- `VdInitializeEngines` and `VdSwap` take compatible arguments. `VdSwap` writes different packets internally (`0x4800` vs `0x485A`), but that didn't stop the picture.

## 17489 addresses

All of these are in one block at the top of `xex1_17489.S`, apart from the RGLoader one.

| Name | Address | Original instruction |
| - | - | - |
| `XexpVerifyXexHeaders_Hook` | `0x800A08E0` | `lwz r11, 0x10(r31)` |
| `XexpLoadXexHeaders_Magic` | `0x800A2DE4` | `cmplw cr6, r11, r10` |
| `XexLoadImageHeaders_Magic` | `0x800A0B94` | `cmplw cr6, r11, r10` |
| `XexpLoadFile_LoadImageData` | `0x800A3764` | `bl HvxLoadImageData` |
| `VdSetDisplayMode_Flag` | `0x800F77C4` | `rlwinm. r11, r26, 0, 1, 1` |
| `HV_LoadImageData_HashCheck` | `0x0002A578` | `bne cr6` |
| `HV_ResolveImports_Index` | `0x0002ADC4` | `slwi r11, r11, 2` |
| `Xex1HvCave` | `0x0000B500` | Empty, free until `0xC000` |
| `Xex1Cave` | `0x801C1900` | Empty, `0x26C` bytes free |
| RGLoader `0xB224` | `0x0000B224` | `bge cr6, 0x8` (RGLoader's own code) |
| `RtlImageXexHeaderField` | `0x800B3530` | |
| `XeCryptSha` | `0x801556D8` | |
| `HvxLoadImageData` | `0x8009F8F0` | |
| `XexExecutableModuleHandle` | `0x802080D4` | |

The cave is past RGLoader's code at `0x801C1774` and the strings in `sysroot_hdd.S` at `0x801C1850`, and in the same 4KB page, so it's known to be executable. `.text` ends at `0x801C1770`.

A retarget also needs to get the zero key selected for XEX1s, see the encryption note under [Format differences](#format-differences).

## Finding things in the HV

The 17489 HV has no useful labels, so to get from a kernel `Hvx*` stub to its handler:

1. Read the syscall number out of the stub (`li r0, N`).
2. Look it up in the syscall table at `0x15EC0`.
3. Most entries are `li r11, N; b jt1_jumper` stubs, which go through the table at `0xAAE0` (pointer at `0x80`).

The ones that came up here are `HvxCreateImageMapping` at `0x2C520`, `HvxLoadImageData` at `0x2A388`, `HvxFinishImageDataLoad` at `0x2A678`, `HvxStartResolveImports` at `0x2A7C8`, `HvxResolveImports` at `0x2AA38` and `HvxImageXexHeader` at `0x2BC38`.

Kernel exports can be resolved from the table at `0x8008002C`: ordinal 1 is the first entry, and values are relative to `0x80040000`.

## Debugging

The scripts behind these notes are in `tools/xex1_tests`, and its README covers the setup.

- **Headless IDA works** with `idat.exe -A -S<script>`. Work on copies of the databases, because it writes to them. `-b` only applies when loading a new file.
- **WinDbg logging:** `-logo <file>` logs everything, and `-c "$$<script"` runs a script at the first break. `sxd -c2 "..." av` runs commands on a second chance access violation.
- **`u @lr-20` fails when `LR` is 0**, and takes the rest of the command line with it, so put it last.
- **Don't put breakpoints on anything called per frame.** A `VdSwap` breakpoint locked up the WinDbg UI. Breakpoints in busy functions can also stop with `Break instruction exception` one instruction past where they were set. `g` gets past it.
- **Filtering on `LR` in `0x92000000-0x921E9000` doesn't isolate Dolphin**, because xshell loads at the same base.
- **Reading a real XEX image:** `xex1tool -b` dumps aren't byte-identical to the loaded image, as it rewrites import thunks. Only images with no imports hash correctly from a dump, so 6 samples could be checked that way. Dolphin isn't compressed or encrypted, so its image can be read straight from the file at `SizeOfHeaders`, and its hash chain checks out that way.
- **Compare against something that works.** Diffing registers against xshell found the display problem right away, after reading kernel code hadn't.
- **`copy /b` doesn't fail on a missing input.** It joins the files it can find and carries on, and `build.bat`'s failure check only covers the assembler. A patch file with no KHV section builds fine, and doesn't boot. A good `patches_*.bin` has three sections, and a 16MB 17489 RGLoader file should be well over 1,268 bytes.

## Limitations

- Only devkit signed XEX1 is covered. There are no retail XEX1 samples to test against.
- Patch files (`.xexp`) won't apply. XEX1 uses header `0x405` and XEX2 uses `0x5FF`.
- Bound paths are still enforced, so XEX1 system modules only load from their own path.
- `XexTitleHash*` traps on import tables with padding (xshell, AudioConsole, xbdm and others). It isn't part of loading, but something calling it would crash.
- If `XexExecutableModuleHandle` still points at a freed module while a title exits, and something calls `VdSetDisplayMode` with the flag at that moment, the gate could read freed memory. I haven't checked whether that can happen. Quitting Dolphin has been clean so far.
- Passing all this only gets a title to load and start. Anything that relies on a kernel or xam API changing behaviour after 1838 can still break. Dolphin is only one title, and it doesn't use much.

## Earlier formats

There are 39 loose `XEX-` files, all from early dumps.

- **`XEX%`:** the next candidate. It needs a kernel ordinal remap, so it's more work than XEX1 was. See [XexPercentSupport.md](XexPercentSupport.md).
- **`XEX-`:** not small. SecurityInfo and import tables are laid out quite differently, and ImageHash is all zeroes (checked on one `xshell.xex`).
- **`XEX?` and `XEX0`:** no SecurityInfo at all.

## Debugging more complex XEX1 titles

Dolphin is one of the simplest titles there is. [Tested titles](#tested-titles) lists the ones that have been run so far. This is how I'd take on the others. The test order and imports come from `tools/xex1_tests/triage.py`. Apart from `LightShafts`, none of the titles in the list have been run yet, so what each will need is only a guess.

### Don't run these

Some XEX1 files aren't test titles, and some of them could do lasting damage to the console:

- `1838.1_Xenon_Recovery_With_Symbols\default.xex` is the recovery app. It imports `KeBlowFuses`, along with `IoDismountVolumeByName` and `ExSetXConfigSetting`.
- `mfgbootlauncher.xex` and `xbupdate.xex` are manufacturing and update tools, and I haven't looked at what they do.

Check the imports of anything unfamiliar first (`xex1tool -i`).

### Test order

Ordered by how much they use beyond Dolphin, so that each one adds a small number of new things to go wrong. All the samples are in `N\XDKSAMPLES` in the 1838 recovery, and the XDK tools are under `XDKSetupXenon1838.1.exe_ext\common\XDK\bin`.

| # | Title | Kernel imports beyond Dolphin | What it tests |
| - | - | - | - |
| 1 | `finished.xex` | None | One new xam ordinal (714) |
| 2 | `LightShafts` | `MmQueryAddressProtect` | More D3D, a heavier render path |
| 3 | `SceneViewer` | 5, including `RtlCaptureContext`, `NtCreateEvent` and `NtOpenFile` | File and event use, xbdm imports (30, 36) |
| 4 | `effecteditclient.xex` | 5, similar to SceneViewer | Same, plus talking to a PC tool, so it may be harder to judge |
| 5 | `pixie.xex` | `NtCreateEvent`, `NtSetEvent` | xbdm imports (28, 30, 36), also PC tool dependent |
| 6 | `AudioConsole` | 32, mostly `XAudio*` and `XMA*` | Audio. Has an import table with padding |
| 7 | `UIAuditioning` | 56, audio plus threads, symbolic links and `XeCrypt*` | The widest API use. Has a padded table, and new xam ordinal 408 |
| 8 | `xshell.xex` (1838) | Not surveyed, it's encrypted | Whether the old launcher works at all. Has a padded table |

Copy each sample's `Media` folder with it. A missing file could look like a patch problem.

### Perfect Dark Zero prototype

The Aug 25, 2005 build, which has `PDZ_toplay.exe` and `PDZ_totest.exe`. It isn't one of the samples, and it's a much bigger step than the next title in the list, since it's the first real game tried. `PDZ_toplay.exe` works on RGLoader, once the failure below was fixed.

`PDZ_toplay.exe` fails with `LDRX: failed to complete load of module PDZ_toplay.exe (C000007B)` on RGLoader with `xex1` set, on the same console and flash where Dolphin runs. The first `HvxResolveImports` call fails, on the kernel table at `0x1320`, and the HV's exit at `0x2AF2C` is the only one that fits.

The import records in memory were random data. 16 sampled words matched the file decrypted with the retail XEX2 key as the master key, and none matched the zero key, the stored key used as is, or the retail XEX1 key. So the image was decrypted with the wrong key, and the hash check being off meant nothing noticed until imports. Dolphin isn't encrypted, so it never hit this. It's also likely to affect the other encrypted XEX1s.

The fix is at `0x29C20` in RGLoader's `khv_17489.S`, and `key_test.py` covers it against the real HV code with the signature checks stubbed. With it on the console, the game loads with all three import libraries, including xbdm, and it was played with no problems seen. Audio seemed to work fine. No crash or loader error was logged during that session. It's only been played for one session, so parts of the game may still have problems.

Differences from Dolphin:

| | `PDZ_toplay.exe` | `PDZ_totest.exe` | Dolphin |
| - | - | - | - |
| Load address and pages | `0x82000000`, 64KB | `0x82000000`, 64KB | `0x92000000`, 4KB |
| Image size | `0x1360000` | `0x1610000` | `0x1E9000` |
| Image data | Encrypted, raw with gaps | Encrypted, raw with gaps | Neither |
| Descriptors, and HV calls after splitting | 79, 310 | 90, 353 | 9, 39 |
| Kernel, xam, xbdm imports | 397, 320, 6 | 415, 326, 38 | Kernel and xam only |

`PDZ_totest.exe` also has `0x18102` and `0x18200` headers (callcap and fastcap, going by the XEX2 key names), a padded xam import table, and far more xbdm imports. Try `PDZ_toplay.exe` first.

Checked without a console, with `xex1` set:

- **Headers:** convert and pass, with every optional header intact. The HV's own header checks in `HvxImageXexHeader` (`0x2BA48`) were read rather than run.
- **Key:** both images decrypt to `MZ` with the zero key, and not with the retail keys, so that's the key the HV has to use.
- **Image load:** every descriptor passes the model of the HV's rules, and the whole image is covered. The hash check being off means a bad load wouldn't show up until later.
- **Import records:** every one in the decrypted image passes the checks at `0x2AD88` to `0x2AEE0`. No address appears twice, and each table stays within one page.
- **Kernel ordinals:** all of them have a 17489 export. That doesn't mean each function still behaves the same.

`windbg/kd_7b.txt` logs which kernel exit returns `C000007B`, `kd_resolve.txt` logs each `HvxResolveImports` call, and `kd_records.txt` dumps the failing table's records as they are in memory. Titles use the call at `800a1344`, not the one at `800a1378`.

The checks above read the file with the right key, so they couldn't catch this. Comparing against what's in memory is what found it.

Not checked, and could still matter for `PDZ_totest.exe`:

- **xbdm:** `PDZ_toplay.exe` loading shows its module number matches on 17489. `PDZ_totest.exe` has more xbdm imports, with ordinals up to 89.
- **xam:** ordinals go up to 985. [xam ordinals](#xam-ordinals) covers the ones that moved, but this title's imports haven't been compared by name. A missing one gives a jump to nowhere, as RGLoader NOPs that check, so it wouldn't show until it's called.
- **Runtime:** this is an August 2005 game, so it's going to use a lot more than Dolphin does. See [Likely trouble spots](#likely-trouble-spots). `vince.ini` has it logging and uploading to a Microsoft server, which might matter if it blocks waiting on the network.

### Project Gotham Racing 3 beta

`Gotham3_R.exe`, a beta build that imports xam, xbdm and the kernel at 2.0.1838. It's the second real game tried, and it works on RGLoader with `xex1` set. It's glitchy in general, which is expected for a beta and hasn't been looked into.

It loaded with the existing patch, then locked up during startup. One fix was needed, and it applies to every 1838 XEX1 rather than just this game:

| | |
| - | - |
| Symptom | Console locks up after `UIFrontendRouteMap::Init`. With WinDbg attached, it stops on assertion `c0000420` at `xam+0x19E6D8` (`8178e6d8`) |
| Cause | xam ordinals moved after 1838. The game's banner call, ordinal 457, lands in `XamGetDefaultImage`, which traps on the texture pointer it's given |
| Other imports affected | Six more of its imports went to the wrong function, all content or enumeration calls |
| Fix | `xex1RemapOrdinal` at `0x2ADC4` in `HvxResolveImports`, with a table of 75 ordinals at `0xB500`. See [xam ordinals](#xam-ordinals) |
| Scope | Only xam import tables older than 2.0.1861, so not XEX2 |
| Test | `remap_test.py` |

Result on hardware, with WinDbg attached and the fix flashed (at that point the gate was 1838 only. It's since been widened to anything older than 1861, and that build also reaches the start screen with no assertion):

- The assertion is gone, and the log has no assertions, access violations or break instructions after the initial connection.
- It went through profile selection, the menus and a full race to the results screen, then back to the frontend, and quit cleanly.
- It wrote a replay to `SAVE:\Replays` during that session. Nothing was confirmed about loading it back.

It also runs fine with no debugger attached, where it used to lock up.

Not checked:

- **Other saves and content calls,** past what that one session used.

One crash seen after the start screen, on the build with the wider gate, when choosing the showroom from the menu (`Showroom\1000.lua`). This is a mismatch in the beta's own files, not something the patch caused:

1. The script fails with ``attempt to call field `SetTeamColour' (a nil value)`` at line 417. The showroom scripts in `cache\Resource\UI\Scripts\Screens\Showroom` call that function, and the string doesn't appear anywhere in the decrypted `Gotham3_R.exe`, so the scripts expect something this exe doesn't have. The game's assert fires in `luaD_throw`.
2. `CarModelDX9::CreateRendererStrip` logs errors as cars load, then `Attempting to Close XHV engine.` is logged, then the assert `m_list.Size() == N`, in `Ut::StaticPool<class GVRace,200>::~StaticPool`. Going by the order of events, the Lua assert seems to start the shutdown, but that part wasn't traced.
3. Second chance access violation at `821e8430`, reading `0x70050000`, just past the top of the stack. That loop scans a text string for a closing `~`, with no check for the end of the string. The buffer at `r30` holds ` GVRace,200>::~StaticPool`, so the game is drawing the assert's own text, and takes the `~` for a formatting tag. This hides the assert, it isn't the cause.

`.restart /f` doesn't get past this, it just reports the same fault again. It needs a reboot.

Log messages seen in that session which didn't stop the game:

- `Garage_01.vs2` and `TestTrack_frontend_maps.dat` can't be opened, and `Race.dat` can't either. `Garage_01.vs2` isn't in this copy of the game.
- `xstudio.xex` fails with `C0000102` at boot, and `Xam.Community.xex`, `Xam.DataCenterAgent.xex` and `cert.xex` fail to load. These happen before the title starts.

Debugging notes from this one:

- `gh` gets past the assertion, if you need to look at what comes after it.
- `sxe -c "..." asrt` dumps state on assertions, which `sxd -c2 ... av` doesn't catch.
- WinDbg started with `-b` stopped the console booting twice, with the log ending at `Connected to target 169.254.x.x ... on local IP 0.0.0.0`. The same flags worked on other boots, so the cause isn't certain, but `-b` makes the kernel wait for the debugger and the console's early link-local address may not be able to answer. Starting without `-b`, then `Ctrl+Break` and a script that runs `.logopen`, worked.
- WinDbg reports the kernel as `17559` because RGLoader spoofs the reported version so that newer games run. The kernel is actually the 17489 devkit kernel.

### Setting up a run

1. Add `.set xex1, 1` to the patch set, run `build.bat`, and flash it. A build without it fails every XEX1 with `C000007B`.
2. Start WinDbg **before** booting the console, with logging on and only `sxd -c2` set up (see `tools/xex1_tests/windbg/kd_cmds.txt`). Only one debugger can listen on the port.
3. Boot, confirm xshell looks normal, then launch the title.
4. Change one thing at a time, and write down what each title did in the [Status](#status) table.

Don't set breakpoints on anything called per frame. Use `Ctrl+Break` and dump state instead.

### Going by the symptom

| Symptom | Likely area | What to look at first |
| - | - | - |
| `LDRX: failed to load module` | The loader | The status code, below |
| Crash at an odd address, or `00000000` | Probably not the first fault | [Finding the first fault](#finding-the-first-fault) |
| Crash inside kernel or xam code | An argument or structure mismatch | The function in both kernels, using `kb` to see the caller |
| Black screen, title alive | Display | Front buffer contents, then diff registers against xshell |
| Corrupt or partial picture | Render path | D3D's `Vd*` calls, and the GPU command processor registers |
| Hang, with the guide still working | Title waiting on something | `!process -1 7` for what each thread is waiting on |
| Hang, with nothing responding | Kernel or GPU stuck | `Ctrl+Break`, `kb`, then the HV |
| No sound, title fine | `XAudio*` or `XMA*` | Compare with 1838, see [Likely trouble spots](#likely-trouble-spots) |
| `Break instruction` one instruction past a breakpoint | My breakpoints | `g` |

Status codes seen so far, or read from the code:

| Status | Where | Meaning |
| - | - | - |
| `C000007B` | `XexpLoadXexHeaders` | Magic isn't accepted. This is what every XEX1 gets on a build without `xex1` set, and it prints nothing. Check this first |
| `C000007B` | `XexpVerifyXexHeaders`, `XexpLoadFile` | Bad headers. Conversion may have bailed out and left them unconverted |
| `C000007B` | `XexpCompleteImageLoad` | `HvxStartResolveImports` failed. Prints `LDRX: failed to complete load of module` |
| `C000007B` | `HvxResolveImports` (`0x2AF28`) | Exporter's table has the wrong magic, or an import record doesn't match its table. Prints the same `LDRX` line. Random data in the records means the wrong image key, as on PDZ |
| `C0000221` | `XexpVerifyXexHeaders`, `XexpLoadFile`, `HvxResolveImports` | Signature, header hash, page data, or import digest. Which one depends on where |
| `C0000059` | `HvxResolveImports` | Import version. Should be patched out |
| `C0000225` | `HvxResolveImports`, `HvxCreateImageMapping` | Module number mismatch, or a missing `0x4004` header |
| `C0000138` | `HvxResolveImports` | Ordinal has no export. Note that RGLoader NOPs this check at `0x2AE18`, so there it's a jump to nowhere instead |
| `C0050001` | `HvxCreateImageMapping` | Game region |
| `C0050002` | `XexpLoadXexHeaders`, `HvxCreateImageMapping` | Media type, or XGD2 media ID |
| `C00000CC` | `XexpLoadFile` | Bound path. Expect this on system modules |
| `C000008B` | `XexpLoadFile` | No bound path where one is required |

### Finding the first fault

The crash the debugger stops at may not be the first one, like it wasn't with Dolphin. The title's exception handlers run first, and they can do further damage along the way.

1. **Catch it earlier.** `sxe av` stops on the first chance, before any handlers run. It may also stop on faults that the title expects and handles, so `g` past those.
2. **If it's already at the second chance,** look through the stack for a dispatcher context: `ControlPc`, `FunctionEntry`, `EstablisherFrame`, `ContextRecord`. `.cxr <ContextRecord>` shows the original registers. `kb` then shows the real stack.
3. **Check for a bad thunk.** `u <call target> L4` on the import should show `lis r11` and `addi r11`. Anything else means imports aren't resolved. On RGLoader, `li r3, 0` means the stub at `0xB208` fired.
4. **Work out what's at the address.** `lm` for the module. If the value looks like data, check it against the registers, since it may just be arithmetic on a leftover value. `0x30000EC8 + 0x3530` is what gave that away on Dolphin.
5. **Map it to code.** Use `Dolphin+0x3C6C4`-style offsets with the disassembly and the sample's source.

### Comparing kernels

Nearly all of these bugs came from something that looks the same but isn't, so comparing is the most useful method:

- **Same function in both kernels:** the export table is at `0x8006002C` in `SE_1838_decomp.bin` and `0x8008002C` in 17489. Ordinal 1 is the first entry, and values are relative to `0x80040000`. `SE_1838_decomp.bin.i64` won't decompile these, so read the disassembly.
- **Watch for flags and struct sizes, not just arguments.** The display flag had compatible arguments and a different meaning. `VdSwap` also writes different packets in each kernel.
- **Compare states.** Run something that works and something that doesn't, dump the same things under both, and diff them (`regdiff.py`). This found the display problem where reading code hadn't.
- **Don't trust names.** Names on 17489 only say what's there now. `VdVerifyMEInitCommand` is a do-nothing stub, and `VdGetGraphicsAsicID` always returns `0x11`, whatever the hardware is.

### Reference material

- **Sample source:** `XDKSetupXenon1838.1.exe_ext\dev\XDK\Source\Samples`, including `Graphics\Dolphin\Dolphin.cpp` and `Common\AtgApp.cpp`.
- **1838 libraries:** `dev\XDK\lib\xbox`, with `d3d9.lib`, the debug `d3d9d.lib`, and `xapilib*.lib`. Their object names and symbols can identify functions in a title, since they're linked in statically.
- **1838 symbols:** the kernel and system module PDBs are in `symsrv_1838`, and `xboxkrnlsd.exe` is there too. My quick attempt at reading kernel names straight out of the PDB failed. Loading it in IDA is the way to go.

### Likely trouble spots

Guesses from the imports, not findings:

- **Audio:** `XAudio*` and `XMA*` are new to the test list, and they're tied closely to hardware. `XMACreateContext` and friends are worth comparing first, and audio failing may not stop the title. Audio seemed fine in `PDZ_toplay.exe`, which links `XAUDLTCG.LIB`, so this may be less of a risk than it looked.
- **Anything using `Vd*` differently:** every title links its own 1838 D3D, so a D3D feature Dolphin doesn't use could hit a kernel mismatch like the display flag did.
- **Exception handling:** `RtlCaptureContext`, and anything relying on unwinding. `CONTEXT` may have changed size between kernels. Worth checking in `RtlDispatchException`, which copies `0xA40` bytes on 17489.
- **Memory:** `MmQueryAddressProtect`, and 1838 code that assumes its old memory layout or how much memory a title gets.
- **xam and xbdm:** their ordinals work on Dolphin, but only those few have been tried, and only on xam. xbdm's XEX1 tables have version 0, and its 17489 module number still needs confirming.
- **Padded import tables:** these load, but `XexTitleHash*` traps on them. AudioConsole, UIAuditioning and xshell have them.

### When something needs fixing

- **Keep it away from XEX2.** Gate it on the `XEX1` marker, as `Xex1DisplayFlagGate` does, unless it can't affect anything else.
- **Prove it live before patching, if possible.** `ed` on a register or memory, then watching the screen, took seconds and settled the display bug. It's much cheaper than a flash.
- **Add a test.** Each fix so far has one in `tools/xex1_tests`, covering XEX2 as well. Modelling the rules a fix depends on is what would have caught the earlier bugs.
- **Mind the space.** `Xex1Cave` has `0x26C` bytes left, and anything that doesn't fit needs another confirmed-executable location.
- **Stop if it isn't the patch's job.** Some titles might need so many fixes that it stops being a loader patch. It's fine to record that here and move on to the next title.
