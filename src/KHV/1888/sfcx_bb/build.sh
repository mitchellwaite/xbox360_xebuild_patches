#!/bin/bash
# Build the 1888 big block code cave with the libxenon toolchain and write
# ../inc/sfcx_bb_1888_blob.S (committed, so build.bat only needs xenon-as).
set -e
cd "$(dirname "$0")"
X=${XENON:-/usr/local/xenon}/bin
CFLAGS="-m32 -O2 -mcpu=powerpc -msoft-float -mno-altivec -mno-vsx -mno-multiple -mno-string
        -fno-pic -fno-PIE -msdata=none -G0 -ffreestanding -fno-builtin
        -fno-tree-loop-distribute-patterns -fno-stack-protector -fno-asynchronous-unwind-tables
        -fno-common -Wall -Wextra -Wno-unused-parameter -Werror"
mkdir -p out
$X/xenon-gcc $CFLAGS -c bb_engine.c -o out/bb_engine.o
$X/xenon-gcc $CFLAGS -c bb_target.c -o out/bb_target.o
$X/xenon-gcc -m32 -c stubs.S -o out/stubs.o -Wa,-mppc64 -Wa,-mregnames
$X/xenon-ld -m elf32ppc -T link.ld --no-undefined -o out/sfcx_bb.elf out/stubs.o out/bb_engine.o out/bb_target.o
$X/xenon-objcopy -O binary -j .text out/sfcx_bb.elf out/sfcx_bb.bin
$X/xenon-nm out/sfcx_bb.elf > out/sfcx_bb.map
$X/xenon-objdump -d out/sfcx_bb.elf > out/sfcx_bb.lst
python3 gen_blob.py out/sfcx_bb.bin out/sfcx_bb.map ../inc/sfcx_bb_1888_blob.S
