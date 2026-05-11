# Builds 1838 kernel patch set with vfuse support and HDD redirection

.set vfuses, 1
.set hdd, 1

.include "khv_1838.S"
.include "RGLoader-1838_VdInit.S"

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
