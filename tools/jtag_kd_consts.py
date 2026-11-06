#!/usr/bin/env python3
"""
jtag_kd_consts.py

Works out the constants for src/KHV/17489_RGLoader/inc/kdnetJTAG_17489.S
from a JTAG NAND image built by xeBuild.

The patch recognises the JTAG payload page (flash page 1) by the ECC word the
kernel computes for it when it rewrites that page with 00 00 in spare bytes
0xA-0xB. That word depends on the payload bytes and the rest of the page's
spare area, so a different payload, core size or NAND layout changes COMP.
ECC_FIX depends only on JTAG_SC, not on the payload.

Works on Windows with a standard python3 interpreter -- no third-party
dependencies required.

USAGE:
    python jtag_kd_consts.py <raw nand image with spare> [page]

EXAMPLES:
    # Small-block image (Xenon, Zephyr, Falcon, 16MB Jasper): JTAG_COMP_SB
    python jtag_kd_consts.py updflash.bin

    # Big-block image (256/512MB Jasper): JTAG_COMP_BB
    python jtag_kd_consts.py updflash_bb.bin
"""

import struct
import sys

PAGE = 0x200
RAW_PAGE = 0x210


def calc_ecc(raw: bytes) -> int:
    """26-bit ECC over 512 data bytes + spare 0x0-0xB + 6 bits of 0xC,
    same as SfcxEncodeECC."""
    val = 0
    v = 0
    for i in range(0x1066):
        if not i & 31:
            v = ~struct.unpack("<L", raw[i // 8:i // 8 + 4])[0]
        val ^= v & 1
        v >>= 1
        if val & 1:
            val ^= 0x6954559
        val >>= 1
    return ~val & 0x3FFFFFF


def ecc_word(raw: bytes) -> int:
    """The value SfcxEncodeECC has in r9 before stwbrx: ECC << 6 | block type."""
    return ((calc_ecc(raw) << 6) | (raw[0x20C] & 0x3F)) & 0xFFFFFFFF


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    page = int(sys.argv[2], 0) if len(sys.argv) > 2 else 1
    with open(sys.argv[1], "rb") as f:
        f.seek(0, 2)
        if f.tell() % RAW_PAGE:
            sys.exit("image has no spare data (size is not a multiple of 0x210)")
        f.seek(page * RAW_PAGE)
        raw = bytearray(f.read(RAW_PAGE))

    spare = raw[PAGE:]
    stored = struct.unpack("<L", spare[0xC:0x10])[0]
    print(f"page {page} spare        {spare.hex()}")
    print(f"stored ECC valid      {calc_ecc(raw) == stored >> 6}")

    jtag_sc = struct.unpack(">H", spare[0xA:0xC])[0]
    if jtag_sc == 0:
        print("spare 0xA-0xB is 00 00: not a JTAG payload page, nothing to restore")
        return

    # What the kernel builds when it rewrites the page: 00 00 in 0xA-0xB.
    kernel = bytearray(raw)
    kernel[0x20A:0x20C] = b"\0\0"
    comp = ecc_word(kernel)
    fix = comp ^ ecc_word(raw)

    # Big block has the bad-block marker at spare byte 0, small block at 5
    layout = "BB" if spare[0] == 0xFF else "SB"

    print(f".set JTAG_SC, 0x{jtag_sc:X}")
    print(f".set JTAG_COMP_{layout}, 0x{comp:08X}")
    print(f".set JTAG_ECC_FIX, 0x{fix:08X}")
    print(f"(stored ECC bytes 0xC-0xF: {spare[0xC:0x10].hex(' ').upper()})")


if __name__ == "__main__":
    main()
