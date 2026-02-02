# Fuck if I know if this is accurate :)

.include "macros.S"

# Skips a bunch of code that results in panics. Console type, 2BL
# 0xB0 (VERIFY_CONSOLE_TYPE), 0xA0(VERIFY_SECOTP_6 2BL revocation), 0x9F (VERIFY_SECOTP_5), 0x9E (VERIFY_SECOTP_4), 0x9D (VERIFY_SECOTP_4)
MAKEPATCH 0x00005048
0:
	MAKEBRANCH 0x51B0
9:

# Patches out SMC header check that results in panic 0xA2, 0xA3, 0xA4 (VERIFY_SECOTP_8/9/10)
MAKEPATCH 0x00005240
0:
	nop
9:

# Patches out panic 0xAB (VERIFY_HEADER_4BL)
MAKEPATCH 0x000058AC
0:
	nop
9:

# Patches out panic 0xAD (SHA_VERIFY_4BL)
MAKEPATCH 0x000059B8
0:
	nop
9:

# Note: the standard 13121 patch set included with XeBuild for glitch2m is no good.
# All it does is patch out panic 0xAD (in a really weird way at that) and add vfuse Patches
# Thus, the glitch2m patch set produced here *will* be different (and actually work)
.ifdef vfuses

MAKEPATCH 0x00000420
0:
	li %r4, 0x601
9:

MAKEPATCH 0x00004F84
0:
	ld %r3, 0x258(%r29)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL 0x5A90
9:

MAKEPATCH 0x00005388
0:
	ld %r3, 0x258(%r26)
	lwz %r4, 0x64(%r3)
	lwz %r5, 0x70(%r3)
	add %r3, %r3, %r4
	add %r4, %r3, %r5
	mr %r3, %r10
	li %r5, 0xc
	MAKEBRANCHL 0x5A90
9:
.endif

# done with patch section

#============================================================================
	.long 0xFFFFFFFF
	.end
#============================================================================
