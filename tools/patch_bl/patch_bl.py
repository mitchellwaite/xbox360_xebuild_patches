#!/usr/bin/env python3

# Code borrowed from
# - https://github.com/GoobyCorp/Xbox-360-Crypto/blob/master/build_lib.py
# - https://github.com/GoobyCorp/Xbox-360-Crypto/blob/master/se_patcher.py

import argparse

from pathlib import Path
from StreamIO import *
from typing import Union, TypeVar, BinaryIO

def apply_patches(bl_data: Union[bytes, bytearray], patch_data: Union[str, bytes, bytearray]) -> bytearray:
	with StreamIO(bl_data, Endian.BIG) as blsio, StreamIO(patch_data, Endian.BIG) as psio:
		while True:
			addr = psio.read_uint32()
			if addr == 0xFFFFFFFF:
				break
			size = psio.read_uint32()
			patch = psio.read_ubytes(size * 4)
			blsio.write_ubytes_at(addr, patch)
		bl_data = blsio.getvalue()
	return bytearray(bl_data)


parser = argparse.ArgumentParser("patch_bl",description='A python script that can be used to manually patch Xbox 360 bootloaders with a given xeBuild patch file, i.e. the 4BL/CD/SD, HV, or Kernel')
parser.add_argument("input",help="The input bootloader to patch")
parser.add_argument("patch",help="The xeBuild patch file to patch the bootloader with")
parser.add_argument("output",help="Where to write the patched bootloader")
parser.add_argument("--noheaderupdate",action='store_true', help="Don't update anything in the BL header")
parser.add_argument("--verbose",action='store_true')
parser.add_argument("--extend", help="Extend the bootloader by adding free space")
args = parser.parse_args()


sd_data = Path(args.input).read_bytes()
sd_patch_data = Path(args.patch).read_bytes()

print("Length of unpatched BL: " + hex(len(sd_data)))

sd_data = apply_patches(sd_data, sd_patch_data)

print("Length of patched BL: " + hex(len(sd_data)))

if args.extend is not None:
   sizeToExtend = int(args.extend, 16)
   print("Extending BL to size " + hex(sizeToExtend))
   sd_data.extend(b'\x00' * (sizeToExtend - len(sd_data)))

if(False == args.noheaderupdate):
   print("Patching length into BL at offset 0xC")
   # Get a 32-bit int in a byte array representing the size of the BL,
   # overwrite the integer in the BL at 0xC
   sd_data_len = len(sd_data).to_bytes(4,byteorder='big',signed='false')
   sd_data[12:16] = sd_data_len

Path(args.output).write_bytes(sd_data)

# Done!
print("Done!")