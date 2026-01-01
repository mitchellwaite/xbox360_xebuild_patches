# Builds SD patches with VFuse support for 64mb small block consoles with patches at 0xE4000 and XeLL located at 0xF4000

.set vfuses, 1
.set devgl64, 1
.set patchengine, 1

.include "sd_12611.S"
