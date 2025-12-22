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

> [!IMPORTANT]
> Yes, 1888 FreeBoot patches are now a thing! Experience what FreeBoot would have been like if it were available in 2005.
>
> Note that the patch sets are in progress... still a few things that i'd like to tweak, but for now this is what is supported:
>
> - 360 games that require kernel 4552 or lower *seem* to work. The xex minimum version check is patched out, so any game that doesn't use new APIs should work fine.
> - Original xbox backward compatibility works as it should, 1888 doesn't seem to have any issues with the newer xefu files or the hacked xefu file sets. There's really not a good xefu spoofer for 188 though
> - Homebrew that doesn't use newer kernel APIs should be fine- Xexmenu, simple 360 NAND flasher, XeLLLaunch2, etc have zero issues. Some more advanced apps like RetroArch GBA, MilkyTracker, and even early versions of FSD work. 
> - We don't have real dashlaunch, but we do have a substitute that blocks live, patches system link, and toggles the devkit/retail xex fallback key. It's based on Byrom90's bladesDL: https://github.com/mitchellwaite/BladesDL/
> - usbdsec patch has been updated for 1888, see below
>
> ### What doesnt work?
> - HDMI doesn't work, you'll need to use AV cables
> - 256/512mb jasper/tonasket. no BB sfc driver
> - Trinity/corona. no XCGPU driver
> - DashLaunch substitute doesn't support plugins (yet...)
> - Xbox 360 games that require kernel 5xxx or later don't seem to work, they'll crash or throw an unreadable disc error.
> - Any homebrew that requires HV access through methods other than syscall 0. The syscall table in 1888 is a lot smaller and things like HvxSetState, HvxExpansionInstall, and HvxExpansionCall don't exist. Things that use syscall 0 (as you *should* be) work fine
> - Obviously, any homebrew that uses unavailable kernel APIs won't work

- Consoles: All 16mb and 64mb phats
- Hack Type: DevGL and Glitch2m
- 2BL: 6752 (Jasper), 5772 (Falcon, Zephyr, Xenon), 7378 (Elpis)
- 4BL: 9452 (modified to ignore patch slots)
- Kernel: 1888
- Notes: GPU patches are different for each console type. Zephyr with Y1 should create a xenon image. Boards with a Zeus or Kronos should create a jasper image.

### USB Device Patch

Look under `include/usbdsec.S`, it contains a version of the usbdsec patch (i.e. what you select in JRunner to allow 3rd party Xinput devices) that works with 17559, 17489, and 1888 among others.

Original source: https://github.com/InvoxiPlayGames/UsbdSecPatch/blob/master/UsbdSecPatchXeBuild.s

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
