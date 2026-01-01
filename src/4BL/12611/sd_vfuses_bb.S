# Builds SD patches with VFuse support for big block consoles with XeLL located at 0xB80000

.set vfuses, 1
.set xell_C8B8, 1
.set patchengine, 1

.include "sd_12611.S"
