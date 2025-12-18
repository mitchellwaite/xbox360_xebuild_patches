# xbox360_xebuild_patches
Repository of glitch2, DevGL, and Glitch2m patch sources for various xbox 360 dashboard versions

## What's Supported?

Unless otherwise noted, DevGL and Glitch2m patch sets use the same patch sets. Creation of 64mb DevGL images requires a version of J-Runner newer than 3.3.0 R4.

### 17489 XDKBuild

- Consoles: All
- Hack Type: DevGL and Glitch2m
- 2BL: 14352 (Glitch2m), 10375 (DevGL)
- 4BL: 17489
- Kernel: 17489
- Notes: 16mb consoles require the XDKBuild filesystem folder on the root of the hard drive

### 17489 RGLoader

- Consoles: All
- Hack Type: DevGL and Glitch2m
- 2BL: 14352 (Glitch2m), 10375 (DevGL)
- 4BL: 17489
- Kernel: 17489
- Notes: Requires [RGLoader.xex](https://github.com/mitchellwaite/RGLoader-XEX) and ini in flash. 16mb consoles require the 17489-dev folder under HDD:\filesystems.

### 17559

- Consoles: All phats
- Hack Type: DevGL and Glitch2m
- 2BL: 6752 (Jasper), 5772 (Falcon, Zephyr, Xenon), 7378 (Elpis)
- 4BL: 9452
- Kernel: 17559
- Notes:

### 1888

Yes, 1888 FreeBoot patches are now a thing!  

> [!IMPORTANT]
> 1888 patches are in progress. There's a few things that don't work yet, namely:
> * 3rd party hard drives (auth patch causes console to hang when a drive is plugged in, even an original one)
> * Provide a solution for xbox games. atm no way to toggle the memory protection, might need to make a version of https://github.com/FreeMyXe/FreeMyXe/tree/master/extras/OGXboxPrep with the correct memory protection address
> * usbdsec patch
> * devkit encrypted xex support
> * Need to port Byrom's dashlaunch substitute so we can have nice things like plugins and memory protection toggling

- Consoles: All phats
- Hack Type: DevGL and Glitch2m
- 2BL: 6752 (Jasper), 5772 (Falcon, Zephyr, Xenon), 7378 (Elpis)
- 4BL: 9452 (modified to ignore patch slots)
- Kernel: 1888
- Notes: GPU patches are different for each console type. Zephyr with Y1 should create a xenon image. Boards with a Zeus or Kronos should create a jasper image.

## Credits

- wurthless-electroniks for modern_loadfare CB patching project and the xeBuild patch diff tool
- sk1080 for the GPU patches and basic kernel/hv patch set which was a great starting point
- dotprofile for the *mostly* labelled 1888 kernel/HV
- XDKbuild and RGLoader for their open source SB/SD/Kernel patches, which are a great reference.
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
- 15432 for posting the pre-made glitch2m images on the 360hub discord. Without this, my ffffffalcon would be fffffried and only able to run XDKbuild. The patches are mostly based on what is included in those images.
- Unknown???? Whoever created the DevGL patches for 17559 that are currently floating around. I'll add credits here if i figure out who wrote them
