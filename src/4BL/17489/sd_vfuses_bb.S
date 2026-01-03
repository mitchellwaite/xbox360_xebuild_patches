# Builds SD patches with VFuse support for big block consoles with XeLL located at 0xB80000

.set vfuses, 1
.set xell_offset, 0xC8B8
.set patchengine, 1

.include "sd_17489.S"
