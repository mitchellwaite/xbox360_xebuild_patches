# Builds SD patches with VFuse support for 64mb small block consoles with XeLL located at 0x9C000

.set vfuses, 1
.set devgl64, 1

.set xell_offset_high, 0xC809
.set xell_offset_low, 0xC000

.set patchengine, 1

.include "sd_12611.S"
