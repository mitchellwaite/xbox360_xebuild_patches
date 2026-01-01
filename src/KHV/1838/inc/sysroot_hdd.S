# ============================================================================
#	Set SystemRoot to HDD
# note: empty space
# ============================================================================
.set Paddr, 0x10A120
.set strLen,  (2f - 1f)
.set RootPatch, (Paddr + 0x80000000)	
		
MAKEPATCH 0x10A120
0:
	.word strLen-2  #//length
	.word strLen-1  #//maxlength
	
	.long (RootPatch+8) #//ptr to string
	
1:
	.string "\\Device\\Harddisk0\\Partition1\\1838-fs\0"
2:
	.align 2
9:

KMAKEPATCH 0x80060A3C
0:
	nop              #  nop out the hardware flags check
	lis   %r11, RootPatch@h
	ori  %r4, %r11, RootPatch@l
9:

# ============================================================================
#	System root panic function 
# ============================================================================
KMAKEPATCH 0x80060AA0
0:
	KMAKEBRANCH 0x80060A60
9:

KMAKEPATCH 0x80060AC0
0:
	KMAKEBRANCH 0x80060A60
9:

KMAKEPATCH 0x80060AEC
0:
	KMAKEBRANCH 0x80060A60
9:

KMAKEPATCH 0x80060B2C
0:
	KMAKEBRANCH 0x80060A60
9:



