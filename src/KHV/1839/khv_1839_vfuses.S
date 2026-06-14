# Builds 1839 kernel patch set with vfuse support and HDD redirection

.set vfuses, 1
.set hdd, 1

.include "khv_1839.S"
.include "RGLoader-1839_VdInit.S"

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
