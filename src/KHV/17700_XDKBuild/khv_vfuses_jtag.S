# Builds KHV patches with VFuse support and HDD file redirection for small block JTAGs

.set vfuses, 1
.set hdd, 1
.set consoletype_jtag, 1

.include "khv_17700.S"
