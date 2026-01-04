# Builds SD patches with VFuse support for small block consoles (and corona) with patches located at 0xE0000 XeLL located at 0xF0000

.set vfuses, 1
.set xell_offset, 0xC80A
.set patchengine, 1

.include "sd_12611.S"
