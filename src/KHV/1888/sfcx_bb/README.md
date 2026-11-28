# 1888 big block (256/512MB Jasper) flash support

Lets the 1888 kernel read and write the 64MB system area of a big block
Jasper in the stock xeBuild big block layout: file reads, creating and
replacing files (config files, boot animation, ...), mobile files and
XConfig settings. The memory unit area isn't used. Small block consoles are
unaffected: every hook checks a flag that `SfcxInitializeHardware` only sets
on a big block controller.

Status: passes the host simulator tests below; not tested on hardware yet.

## Files

```
sfcx_bb/
  bb.h            engine interface, 1888 device extension offsets
  bb_engine.c     mount, translation, allocator, writers, coalescing, mobile log
  bb_target.c     console glue: flash I/O through SfcxSynchronousFlashPassThrough
  stubs.S         hooks, kernel <-> C thunks, register mode DMA replacement
  link.ld         places the cave at 0x800E1200, retail 1888 addresses
  build.sh        libxenon build, writes ../inc/sfcx_bb_1888_blob.S
  gen_blob.py     blob -> KMAKEPATCH include
  test/           host NAND simulator, model of 1888's FS code, tests
../inc/sfcx_bb_1888.S       hook sites (included from khv_1888.S)
../inc/sfcx_bb_1888_blob.S  generated cave contents (committed)
```

`build.bat` only needs xenon-as/xenon-objcopy because the generated blob is
committed. After changing anything here, rebuild it in WSL:

```
./build.sh                                   # needs /usr/local/xenon/bin (libxenon)
./test/soak.sh <64MB+spare BB image> 600     # host tests, several seeds
```

## Stock big block layout (what xeBuild writes, what 17559 reads)

128KB erase blocks, 2KB pages, 528-byte sectors (512 data + 16 spare),
spare in meta type 2:

| spare byte | meaning |
|---|---|
| 0 | bad block marker (0xFF = good) |
| 1, 2 (low nibble) | LBA: 128KB block number |
| 5, 3, 4, 6 | sequence number, low byte first |
| 7, 8, 9 | data/root: FS geometry; mobile entry: size (7 lo, 8 hi), free 2KB pages left (9) |
| 12 (low 6 bits) | block type |
| 12 (top 2), 13-15 | ECC (same algorithm as small block) |

- FS data region: `count = 4 * spare[8]` blocks from
  `base = 0x1E0 - spare[9] - count` (0x15C and 0x80 on xeBuild images), then
  `spare[9]` (4) config blocks, then the spare area 0x1E0-0x1FF (bad block
  replacements, LBA = the block replaced).
- The FS is the format 1888 already uses on small block: 1024 16KB units,
  root = FAT in even sectors and 32-byte directory entries in odd sectors,
  last 512 bytes = bad block bitmap. FAT units are relative to the data
  region: unit `u` is in block `base + u/8`, slot `u%8`.
- Data blocks: type 0x2A, sequence 0. Root: a type 0x2C slot inside a data
  block, sequence = root version; the newest complete one wins.
- Mobile files (MobileB-J, types 0x31-0x39): one shared block, every
  version on a 2KB page boundary, sharing the block's sequence.

## How 1888 is adapted

1888's directory, FAT and transaction code stays. On big block only the
layer that decides where data lands changes:

| 1888 function | big block behaviour |
|---|---|
| SfcxCreateDeviceObject | device extension 0x68C -> 0x6A0 (flag, engine context) |
| SfcxInitializeHardware | decode controller type; 1024 units; redirect XConfig containers 0/1 |
| SfcxStartFlashPassThrough | DMA requests done as register mode sector I/O (BB DMA counts 2KB pages) |
| SfcxMountVolume | newest complete root and mobile block, bad block remap, free map |
| SfcxTranslateLogicalFlashBlock | unit -> `remap[base + u/8] * 8 + u%8` (all 1888 read paths go through it) |
| SfcxFindAvailableFreeFlashBlock | next slot of the block the transaction is filling; a block is erased (cache range invalidated) when taken, and only if none of its units is in use |
| SfcxEraseLogicalFlashBlock | no-op for the slot just handed out, refused otherwise |
| SfcxWriteFileDataFlashBlock | unit with a type 0x2A spare |
| SfcxWriteRootDirectoryFlashBlock | type 0x2C slot, sequence + 1, FAT without transaction flags |
| SfcxBeginUpdateTransaction | start a fresh block with the old root block's live units, coalesce every block with a hole |
| SfcxEndUpdateTransaction | point open FCBs at units the transaction moved |
| SfcxWriteMobileFile | append to the mobile block, compact when full |
| SfcxVolumeWrite | refused: a raw 16KB write would erase 128KB |

Raw pass-through IOCTLs from outside the driver (NAND tools) keep physical
addresses and raw spare bytes, like on 17559.

### How space is managed (the same way as 17559)

Checked against 17559's SfcxBeginUpdateTransaction, RestartUpdateTransaction,
FlushUpdateFlashBlockBuffer, CoalesceDataBlocks and WriteMobileFile /
CompactLargeMobileBlock / InspectLargeMobileBlock.

- Every transaction writes into freshly erased blocks. It starts by copying
  the live units of the block holding the current root into a fresh block
  (17559 reads that block into its 128KB update buffer and rewrites it on
  commit). The old root block is then all dead and is freed by the commit,
  so a commit never costs a free block overall, and at least one free block
  is left at rest without any reserve arithmetic. A write that runs out of
  blocks fails and its transaction rolls back, as on 17559.
- Pages of a block are only programmed in ascending order after an erase,
  and a block is never appended to by a later transaction.
- Nothing the committed root references is erased. Units are written first,
  the root last; a power cut leaves the previous root and everything it
  references.
- At the start of every transaction, every block with a hole (1 to 7 live
  units), emptiest first, has its units moved into the transaction's
  blocks, as long as they fit with room left for the root. The emptied
  blocks are freed by the commit. `sysupdate.xexp?` is never moved
  (bootloaders read it by position).
- Mobile files: an entry claims (spare byte 9) how many pages are left after
  it. A full block is compacted into a fresh one with the next sequence: the
  latest version of every existing file, then the new entry, all claiming the
  fill level of the finished block. An interrupted compaction never reaches
  its claim, so mount (the newest block that parses as complete, like
  17559) keeps using the old block, which is released only once the new
  one is done.
- A program or erase failure retires the whole 128KB block (kept in the
  root's bad block bitmap).

What differs from 17559 is only what 1888's interface forces: 1888 writes
each 16KB unit as soon as it has it, so units go straight to their block
instead of through a 128KB RAM buffer, and a mobile entry never crosses a
16KB unit (1888 reads a mobile file from one unit), with "deleted" entries
of a file that doesn't exist as padding.
- `sysupdate.xexp?` is never moved (17559 does the same; bootloaders read it
  by position).

### XConfig settings

1888 keeps STATIC/SECURED and STATISTIC settings in two raw 16KB blocks at
the end of the flash volume. On big block those become `MobileF.dat` and
`MobileG.dat` (17559 uses regular files, but 1888 doesn't allow read+write
opens of regular flash files). USER/CONSOLE/network/media center settings
stay in MobileB/C/D.dat. Settings read from a stock image are 17559's;
1888 zero-fills categories whose version doesn't match.

## Tests

`test/` builds the engine natively against a NAND simulator that fails on
any program of a non-erased sector, out of order page program or more than
4 partial programs per page, computes/checks ECC, and can inject erase and
program failures and power cuts. `fs1888.c` is a transcription of the 1888
code that calls the engine (update transactions, the unit writer and its
retry loop, file writes, chain freeing, read paths), so the engine is tested
under the same contract the kernel gives it.

The suite: mount a stock xeBuild BB image and compare every file with an
independent decode of the raw image; random file replace/create/delete and
mobile writes with frequent remounts; an open FCB that must follow coalescing;
power cuts at random points (the remount must show the old or new state and
nothing else); fill to disk full, free half, refill; a packed volume with
deletes, small writes, remounts and settings writes cut by power failures
(every compaction is cut at least once), which must always keep a free
block; failing blocks.

## Not covered / to check on hardware

- Only the hooks' logic is tested off-console; the asm hooks were checked by
  disassembly. The register mode sector I/O assumes the controller accepts
  512-byte sub-page reads/writes on big block (libxenon relies on this).
- 1888 can't replace a file without free space for the new copy (same as on
  small block); xeBuild BB images have about 2.4MB free.
- Like 17559, each transaction rewrites up to 112KB of the previous root
  block, so a small file write costs more NAND programs than on small block.
- `SfcxQueryFileAllocationList` returns FS unit numbers, not flash offsets;
  only a tool that turns those into raw flash addresses would care.
