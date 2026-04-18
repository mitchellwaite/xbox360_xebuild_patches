.ifdef kdnetJtag
# ============================================================================
# For JTAGs only, we need to patch KDNet, otherwise the system will panic
# Thanks to @kavkazsila on discord for pointing it out in the 16537 patch
# ============================================================================

# ==================================================================
# SfcxEncodeECC hook, replaces the stwbrx r9, r7, r4
# ==================================================================
KMAKEPATCH 0x800C20B8
0:
	KMAKEBRANCH 0x801D0F70
9:

KMAKEPATCH 0x801D0F70
0:
   li        %r12, 0x350
   lis       %r11, -0x69ED
   ori       %r11, %r11, 0xF6C0
   cmplw     %r11, %r9
   beq       SLOT0
   lis       %r11, 0x7E5B
   ori       %r11, %r11, 0x6280
   cmplw     %r11, %r9
   beq       SLOT1

done:
   # do what we patched and branch back
   stwbrx    %r9, %r7, %r4
   KMAKEBRANCH 0x800C20BC

   SLOT0:
   lis       %r11, 0xE4
   ori       %r11, %r11, 0x9AA2
   sth       %r12, 0x1A(%r4)
   stw       %r11, 0x1C(%r4)
   b         done


   SLOT1:
   lis       %r11, 0x4070
   ori       %r11, %r11, 0xD24A
   sth       %r12, 0x1A(%r4)
   stw       %r11, 0x1C(%r4)
   b         done
9:


# ==================================================================
# SfcxFinishFlashPassThrough hook, replaces the lwz r11, 0x10(r28)
# ==================================================================
KMAKEPATCH 0x800BCB90
0:
	KMAKEBRANCH 0x801D0940
9:

KMAKEPATCH 0x801D0940
0:
	lwz %r3, 0(%r31)
	cmplwi %r3, 0
	bne loc_924
	li %r4, 0x10
	andc %r25, %r25, %r4

loc_924:
	# Do what we patched and branch back to the next instruction
	lwz %r11, 0x10(%r28)
	KMAKEBRANCH 0x800BCB94
9:


# ==================================================================
# SfcxSynchronousWriteInternal
# ==================================================================
KMAKEPATCH 0x800B7578
0:
    nop
9:

KMAKEPATCH 0x800B758C
0:
    nop
9:

.endif