
# ============================================================================
#	Set SystemRoot to HDD
# note: empty space
# ============================================================================
.set Paddr, 0x1c1850
.set strLen,  (2f - 1f)
.set RootPatch, (Paddr + 0x80000000)	
   
MAKEPATCH 0x1C1850
0:
   .word strLen-2  #//length
   .word strLen-1  #//maxlength

   .long (RootPatch+8) #//ptr to string
   
1:
   .string "\\Device\\Harddisk0\\Partition1\\17700-dev\0"
2:
   .align 2
9:

KMAKEPATCH 0x80061034
0:
   nop #  nop out the hardware flags check
   lis   %r11, RootPatch@h
   ori  %r4, %r11, RootPatch@l
9:

# ============================================================================
# 17700 kernel doesn't have any of the normal panic functions so we have
# to make our own :)
#
# We've patched out UsbdIsDeviceAuthenticated so we've got some space at
# 0x800D87A8
# ============================================================================
KMAKEPATCH 0x80061128
0:
   # Patch what was ObCreateSymbolicLink
   KMAKEBRANCH 0x800D87A8
9:

KMAKEPATCH 0x800D87A8
0:
   # Call the func we patched ;)
   KMAKEBRANCHL ObCreateSymbolicLink
   cmpwi %r3, 0

   # If ObCreateSymbolicLink was successful,
   # branch back to the next instruction in ExpSetSystemRoot
   KMAKEBGE 0x8006112C

   # If ObCreateSymbolicLink failed, fall back to the flash
   # as SystemRoot
   KMAKEBRANCH 0x80061058
9:


