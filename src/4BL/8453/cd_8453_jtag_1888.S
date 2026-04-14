# Builds 8453 CD patch set for JTAG machines. Skip the patch slots after loading CE 1888 from flash

.set skip_patch_slots, 1
.set jtag_5bl_offset, 0x6500

.include "cd_8453.S"
