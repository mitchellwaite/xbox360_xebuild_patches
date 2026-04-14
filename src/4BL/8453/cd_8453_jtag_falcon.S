# Builds 8453 CD patch set for JTAG falcon
# Jasper uses 6C40, xenon and zephyr tbd but it's probably similar. 2BL are all different sizes

.set jtag_5bl_offset, 0x6500

.include "cd_8453.S"
