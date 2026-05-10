# Builds 1888 kernel patch set with vfuse support

.set vfuses, 1

# While it's not technically needed for Y1, the GPU patch
# covers all phat GPUs (including Elpis/Rhea/Gunga/etc.)
.set patch_gpu, 1

.include "khv_1888.S"
