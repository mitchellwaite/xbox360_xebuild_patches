# Builds SB 14352 patch set with "shadowboot" support, a.k.a. fusechecks are fully skipped and the SC/SD sig checks are patched out

.set shadowboot, 1

.include "sb_14352.S"
