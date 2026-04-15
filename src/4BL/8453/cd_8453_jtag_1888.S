# Builds 8453 CD patch set for JTAG machines. Skip the patch slots after loading CE 1888 from flash

.set skip_patch_slots, 1

.include "cd_8453.S"
