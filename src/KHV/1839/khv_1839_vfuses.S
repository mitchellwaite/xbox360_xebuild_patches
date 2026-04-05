# Builds 1839 kernel patch set with vfuse support and HDD redirection

#
# Note: the same tricks we use on 1888 to add support for Rhea/Zeus do NOT
# work on 1839- spoofing the ASIC id and edram timing make it MORE unstable.
# Without the ASIC ID patch it falls back into a compatibility mode, and even
# then the edram doesn't really work well enough to do anything other than
# simple demos or messing around with the dashboard. You really do need a
# Y1 GPU to get a good experience on the 1839 kernel
#

.set vfuses, 1
.set hdd, 1

.include "khv_1839.S"
