# Builds 17559 kernel patch set with vfuse support

.set vfuses, 1

# The RGH3 glitch2m image for jasper/falcon has some extra patches
# if this causes issues for normal glitch2m i guess we'll change it
.set rgh3_patches, 1

.include "khv_17559.S"
