# xbox360_xebuild_patches
Repository of glitch2, DevGL, and Glitch2m patch sources for various xbox 360 dashboard versions

## Support Matrix

Unless otherwise noted, DevGL and Glitch2m patch sets use the same patch sets. Creation of 64mb DevGL images requires a version of J-Runner newer than 3.3.0 R4.

| Dashboard      | Hack Type | 2BL   | 4BL   | Kernel | Xenon | Zephyr | Falcon | Jasper | Trinity | Corona | Notes |
|----------------|-----------|-------|-------|--------|-------|--------|--------|--------|---------|--------|-------|
| 17489_RGLoader | Glitch2m  | 14352 | 17489 | 17489  | ✅   | ✅     | ✅     | ✅    | ✅      | ✅    | Requires RGLoader.xex and RGLoader.ini in flash, 16mb requires an appropriate filesystem on the hard drive |
| 17489_RGLoader | DevGL     | 10375 | 17489 | 17489  | ✅   | ✅     | ✅     | ✅    | ✅      | ✅    |       |
| 17489_XDKBuild | Glitch2m  | 14352 | 17489 | 17489  | ✅   | ✅     | ✅     | ✅    | ✅      | ✅    | 16mb requires an appropriate filesystem on the hard drive |
| 17489_XDKBuild | DevGL     | 10375 | 17489 | 17489  | ✅   | ✅     | ✅     | ✅    | ✅      | ✅    |       |


## Credits

- RGLoader.xex - originally by tydye81 and Team Xecuter, source released by Visual Studio
- 0 Fuse Patches - Visual Studio, source; Holofractal, putting 0f RGLoader all together and kitty for helping along the way
- RGLoader Xam Patches  (rglXam.rglp) - JTAG
- XDKBuild VFuse patches and flag fixer: xvistaman2005
- 360hub Discord Server - https://discord.gg/z9r3HMUxp7
- RGLoader Discord Server - https://discord.gg/jTDT4rAh56
- [xvistaman2005/XDKbuild (original XDKbuild repository)](https://github.com/xvistaman2005/XDKbuild)
- [Byrom90/Xbox_360_Research (17559 patch set)](https://github.com/Byrom90/Xbox_360_Research/blob/main/xeBuild_Patches/KHV_17559/17559_KHV_Patchset.s)
- [GoobyCorp/Xbox-360-Crypto (patch decompiler, BL patching code)](https://github.com/GoobyCorp/Xbox-360-Crypto)
- https://web.archive.org/web/20180513003510/http://www.razielconsole.com/forum/guide-e-tutorial-xbox-360/945-[x360-reversing]-chapter-2-cd-patches.html
- https://github.com/g91/XBLS/blob/master/Research/code/1bl_583.c#L9

