# Builds 5771 cb patch set for JTAGs running devkit kernels
# Realistically the only difference is that the SMC hash check
# and the entriety of the fusecheck is patched out  

.set vfuses, 1
.set loadfare, 1

.include "cbb_5771.S"
