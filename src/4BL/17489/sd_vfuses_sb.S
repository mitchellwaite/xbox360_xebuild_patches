# Builds SD patches with VFuse support for small block consoles (and corona) with patches located at 0xE0000 XeLL located at 0xF0000

.set vfuses, 1
.set xell_C80F, 1
.set patchengine, 1

.include "sd_17489.S"
