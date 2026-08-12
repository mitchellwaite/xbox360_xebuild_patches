.include "macros.S"

# Patches E76 to reboot the system
# yolo to see if Eggy's machine is helped.... cold boot it E76es but apparently on a reboot it doesnt????
KMAKEPATCH 0x800D5790
0:
   li %r3, 0x1
   KMAKEBRANCHL 0x800682A0
9:
