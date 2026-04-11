# Builds SD patches with VFuse support for small block consoles (and corona) with patches located at 0xE0000 XeLL located at 0xF0000

.set vfuses, 1
.set jtag_vfuses, 1
.set devgl64, 1

.set xell_offset_high, 0xC809
.set xell_offset_low, 0x5060

.set patchengine, 0

.include "sd_17489.S"
