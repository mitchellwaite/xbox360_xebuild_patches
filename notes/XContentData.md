# XCONTENT_DATA Across SDK Versions

Titles built before 1838 pass a smaller `XCONTENT_DATA` than 17489's xam expects, so saves and other content calls don't work for `XEX-` and `XEX%` titles. None of this is implemented. This is what's known, for when it gets picked up.

Everything here is from reading each build's xam. Nothing below has been tried on a console, apart from the two breaks under [What it looks like](#what-it-looks-like).

## Summary

| SDK | Format | Size | `szFileName` | `XamContentCreate` args | State on 17489 |
| - | - | - | - | - | - |
| 1640 | `XEX-` | `0x108` | no | 6 | Broken |
| 1746 | `XEX%` | `0x108` | no | 7 | Broken |
| 1838 | XEX1 | `0x134` | yes | Not read | Works as far as tested |
| 2099 | XEX2 | `0x134` | yes | 7 | No conversion needed |
| 17489 | XEX2 | `0x134` | yes | 7 | Native |

The size comes from the `li` in each xam's `XamContentDelete`, and 1640, 1746, 1838 and 2099 have PDBs to confirm it's that function. 

So the change is somewhere after 1746. 1838 needs nothing: PGR3's XEX1 build wrote a replay to `SAVE:\Replays` on hardware, though loading it back wasn't confirmed. Its export ordinals are a separate problem, which [`xex1RemapOrdinal`](Xex1Support.md#xam-ordinals) already handles.

## The two layouts

| Offset | 1640 and 1746 | 1838 onward |
| - | - | - |
| `+0x000` | Device ID | Device ID |
| `+0x004` | Content type | Content type |
| `+0x008` | Display name, `0x100` bytes | Display name, `0x100` bytes |
| `+0x108` | End of struct | `szFileName`, up to 42 chars |
| `+0x134` | | End of struct |

The first three fields are the same, so converting is a copy plus a file name.

- **1640:** read from xam's `XContent::EnumerateWorker`, and matches how CoD2 fills in the struct.
- **1746:** the same function has the same shape, with a `0x108` size check next to the type at `+0x4C` and the name at `+0x50` of the request, which is `+0x48` plus the struct offsets. That's a pattern match, not a full read.
- **1838 onward:** the `+0x108` file name is read directly in `XamContentCreate`. The `0x134` end is from the size passed.

## What goes wrong

### File names

17489's `XamContentCreateEx` (`817BFD98`) reads `szFileName` at `+0x108`, off the end of the title's struct and into whatever follows it, usually the title's stack. A first byte of 0 returns `ERROR_INVALID_PARAMETER`. Anything else gets checked as a file name, and would be used as one if it passes.

`IsValidContentFileName` (`817BFB70`) only wants ASCII within 42 characters, so garbage can pass.

`XamContentDelete` (`817C01C8`) passes a size of `0x134` to `XampContentDelete`, which also reads past the end.

### Create's arguments on 1640

This one is only on `XEX-`. It's separate from the struct, and fixing the struct alone won't be enough.

| Build | r3 | r4 | r5 | r6 | r7 | r8 | r9 |
| - | - | - | - | - | - | - | - |
| 1640 | User | Root name | Data | Flags | Disposition | Overlapped | |
| 1746, 17489 | User | Root name | Data | Flags | Disposition | License mask | Overlapped |

CoD2's call at `8238BAA8` sets `r8` to its overlapped and leaves `r9` as whatever it was. On 17489 that overlapped gets used as a license mask pointer, and the leftover `r9` as the overlapped. A wrapper has to move `r8` to `r9` and clear `r8`.

`xex2d_args.py` doesn't cover this function, so the argument audit in [`XexMinusSupport.md`](XexMinusSupport.md) didn't catch it.

### Enumeration

`XamContentCreateEnumeratorInternal` (`817C0738`) reports `0x134` per item as the buffer size, and `CContentEnumerator::_Enumerate` (`81739160`) copies out records `0x134` apart. That's wrong for an old title in two ways:

- **A title that trusts the reported size** gets a big enough buffer, but steps through it `0x108` at a time and reads records as garbage.
- **A title with its own size** can overrun its buffer by `0x2C` per item. PGR3 asserts that a 25 item buffer is exactly `0x19C8` bytes, so it's in this group, and the overrun would be `0x44C` bytes.

`_Enumerate` is limited by item count, not `cbBuffer`. `XamEnumerate` (`817C2D98`) passes `cbBuffer` along, but nothing read so far checks it for content enumeration. That part hasn't been followed to the end, so it's worth confirming with a test.

This is a possible lead on [PGR3's heap corruption](XexPercentSupport.md#pgr3-where-this-stands), but only that. The bytes found in that heap block don't look like content records.

## What it looks like

CoD2 at 1640, on signing in, from `OpenContextFile` calling `XContentCreate`:

```
***RIP: (pcd->szFileName[0] != NULL) Empty string specified for XCONTENT_DATA szFileName.
```

PGR3 at 1746, which looks like its scan for downloadable content (`82188670`):

```
***RIP: (IsValidContentFileName(pcd->szFileName)) Invalid filename specified for XCONTENT_DATA szFileName.
```

Both are on a debug xam, and `g` or `gh` gets past them, but that doesn't fix anything. The call still goes on to fail or use a bad name.

## Where the file name comes from

Old titles never supply one, as xam made it from the display name. 1640's `XContent::BuildStorageOrg` (`1001A100`) builds this path:

```
Content\<XUID>\<title ID>\<content type>\<MD5 of display name>\
```

The last part is `XeCryptMd5` over the display name's UTF-16 bytes with no terminator, formatted with `%.16I64X%.16I64X`, which is 32 hex characters. It only does this for names of 1 to 127 characters.

The same format string is in 1746's xam. It's also in 1838's, but that hasn't been read, and may be used for something else.

The same scheme fits `szFileName` well:

- 32 ASCII characters pass `IsValidContentFileName`.
- The same display name always gives the same file name, so create, reopen and delete all land on the same content.
- `XeCryptMd5` is still exported, at ordinal 391 on 17489.

Enumeration gives a title the display name back from the content's metadata, as 1640 did, so a title reopening what it enumerated should get the same hash. That relies on 17489 storing the name unchanged, which hasn't been checked.

Content on disk won't carry over from a real 1640 or 1746 console. 1640's are folders, with a `.xeus` file alongside, and 17489 mounts packages. For this it doesn't matter, as these titles would just make new ones through 17489's code.

## What a fix needs

| Function | 17489 ordinal | 1640 | 1746 | Change |
| - | - | - | - | - |
| `XamContentCreate` | 600 | 130 | 600 | Convert the struct, and shift args on 1640 |
| `XamContentDelete` | 603 | 131 | 601 | Convert the struct |
| `XamContentCreateEnumerator` | 604 | 133 | 603 | Report `0x108` per item |
| `XamEnumerate` | 592 | 166 | 610 | `0x108` records, content enumerators only |

The 1746 ordinals are from the PDB. `XamContentClose` doesn't take the struct. 1746 also exports `XamContentSetThumbnail`, `XamContentGetThumbnail` and `XamContentGetCreator`. They probably take it too, but they haven't been read.

These are all xam's exports, so wrappers can't go in the kernel's export table, and that table has no empty slots left anyway. That rules out what `XexPercentSupport.md` first suggested. The approach that looks right:

1. **Hook in `rglXam.S`.** Patch each function's entry to branch to code in `Xex25Cave`, which still has room. It's too far for a relative branch from xam, so it needs `lis`, `ori`, `mtctr`, `bctr`, and the overwritten instructions have to be replayed.
2. **Gate each hook on the title.** xam calls these itself with real `0x134` structs, such as `CXStorageDownloadToDirectory` and `CXamContentAdapter`, so check the process type the way `xex1PhysicalGate` does, then the executable's format.
3. **Convert on the stack.** Build a `0x134` struct in the wrapper's frame and pass that. This is safe with an overlapped, as `XampContentCreate` (`817BFC00`) copies the data into its own request before starting the I/O.
4. **Write enumeration records inside the worker.** The change belongs at the `XMemCpy` and `+= 0x134` in `_Enumerate`. Converting after `XamEnumerate` returns wouldn't work for overlapped calls, or stop an overrun. `CContentEnumerator::Enumerate` also has a loop stepping `0x134` over records, which needs a look. The enumerator should record that its owner is old when it's created, as the worker may not run on the title's thread.

### Telling the builds apart

This needs solving first, because the gate decides everything else:

- **`XEX-`** has its marker at `SecurityInfo+0xC`, but it's only written if imports converted.
- **`XEX%`** keeps the `XEX1` marker on purpose, so it looks the same as 1838 at runtime. Applying this to 1838 would break titles that work now. The likely answer is a `XEX%` marker in the same `+0xC` word, written in `Xex25FixHeaders`, but check that nothing reads that word as part of the signature first.

## Who needs it

| Title | SDK | Uses | Notes |
| - | - | - | - |
| CoD2 `cod2sp.exe` | 1640 | `XContentCreate`, `XContentClose` | Only direct calls found are in `OpenContextFile` and `CloseContextFile`. Delete and the enumerator are imported with no direct callers |
| PGR3 July build | 1746 | Create, enumeration | `ReadSaveGame`, `WriteSaveGame` and the content scan |
| Crackdown prototype | 1746 | Not checked | |
| 1640 samples | | Not surveyed | Scan imports before picking test cases |

CoD2 is the simplest first target, as it only needs create on the title's side, so the file name and argument fixes can be proven without touching enumeration. PGR3 is the one that tests enumeration.

## Testing

The XEX- tests under `tools/xex1_tests` already run real kernel code in the interpreter, and the same approach should work here against 17489's xam:

- Convert a `0x108` struct and compare the result, with names of 1, 127 and 128 characters.
- Check `r8` and `r9` after the 1640 wrapper.
- Check each gate with a system caller, an XEX2 title, an XEX1 title and the old formats.
- For enumeration, fill a buffer sized at `0x108` per item with a guard after it.

On a console: create a save in CoD2, reboot, load it back, and delete it. Then run an XEX2 title and a 1838 title that saves, to check they haven't changed.
