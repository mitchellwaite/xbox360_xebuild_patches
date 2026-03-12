.include "macros.S"

MAKEPATCH 0x42069
0:
   dcbt 0, %r5
   dcbt %r0, %r5
9:
