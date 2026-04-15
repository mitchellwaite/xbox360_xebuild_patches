# Builds 8453 CD patch set for JTAG machines but load the 5BL from after the JTAG 4BL rather than CE 1888 from the NAND
# RGLoader uses this

.set skip_patch_slots, 1

.include "cd_8453.S"
