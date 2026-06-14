# Builds 1839 kernel patch set with vfuse support

.set vfuses, 1

.include "khv_1839.S"
.include "RGLoader-1839_VdInit.S"

#============================================================================
      .long 0xFFFFFFFF
      .end
#============================================================================
