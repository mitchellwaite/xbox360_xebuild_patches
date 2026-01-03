@echo off

echo ***************************************
echo * Xbox 360 XeBuild Patch Set Building *
echo ***************************************
echo.

if exist output rmdir /S /Q output

mkdir output

echo Building kernel patch files...

call:buildPatchSection src\KHV\17489_RGLoader khv_vfuses_sb
call:buildPatchSection src\KHV\17489_RGLoader khv_vfuses_jasperbb
call:buildPatchSection src\KHV\17489_RGLoader khv_vfuses_trinitybb
call:buildPatchSection src\KHV\17489_RGLoader khv_vfuses_coronabb
call:buildPatchSection src\KHV\17489_RGLoader khv_vfuses_devkit

call:buildPatchSection src\KHV\17489_XDKBuild khv_vfuses_sb
call:buildPatchSection src\KHV\17489_XDKBuild khv_vfuses_jasperbb
call:buildPatchSection src\KHV\17489_XDKBuild khv_vfuses_trinitybb
call:buildPatchSection src\KHV\17489_XDKBuild khv_vfuses_coronabb
call:buildPatchSection src\KHV\17489_XDKBuild khv_vfuses_devkit

call:buildPatchSection src\KHV\17559 khv_17559_vfuses

call:buildPatchSection src\KHV\1888 khv_1888_vfuses
call:buildPatchSection src\KHV\1888 khv_1888_vfuses_rhea
call:buildPatchSection src\KHV\1888 khv_1888_vfuses_zeus

call:buildPatchSection src\KHV\1838 khv_1838_vfuses
call:buildPatchSection src\KHV\1838 khv_1838_vfuses_devkit

echo Done!

echo.
echo Building 4BL patch files...

call:buildPatchSection src\4BL\17489 sd_vfuses_bb
call:buildPatchSection src\4BL\17489 sd_vfuses_sb
call:buildPatchSection src\4BL\17489 sd_vfuses_devkit
call:buildPatchSection src\4BL\17489 sd_shadowboot

call:buildPatchSection src\4BL\12611 sd_vfuses_sb_1838
call:buildPatchSection src\4BL\12611 sd_vfuses_devkit_1838
call:buildPatchSection src\4BL\12611 sd_shadowboot

call:buildPatchSection src\4BL\9452 cd_9452_vfuses
call:buildPatchSection src\4BL\9452 cd_9452_glitch2_rgl

echo Done!

echo.
echo Building 2BL patch files...

call:buildPatchSection src\2BL\14352 sb_vfuses
call:buildPatchSection src\2BL\14352 sb_shadowboot

call:buildPatchSection src\2BL\5772 cbb_5772_vfuses
call:buildPatchSection src\2BL\6752 cbb_6752_vfuses

call:buildPatchSection src\2BL\7378 cbb_7378_vfuses

echo Done!

echo.
echo Assembling XeBuild patch sets...

echo.
echo 17489 RGLoader...

mkdir output\17489_RGLoader

REM *** For RGLoader, the patch sets for 16mb machines are all identical as they use the same loaders and kernel
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_sb.bin + src\KHV\17489_RGLoader\khv_vfuses_sb.bin output\17489_RGLoader\patches_g2mjasper.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mxenon.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mxenon_ELPIS.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mzephyr.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mfalcon.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mtrinity.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mcorona.bin

REM *** BB consoles all have different patch sets. C'est la vie.
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_bb.bin + src\KHV\17489_RGLoader\khv_vfuses_jasperbb.bin output\17489_RGLoader\patches_g2mjasper_flash.bin
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_bb.bin + src\KHV\17489_RGLoader\khv_vfuses_trinitybb.bin output\17489_RGLoader\patches_g2mtrinity_flash.bin
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_sb.bin + src\KHV\17489_RGLoader\khv_vfuses_coronabb.bin output\17489_RGLoader\patches_g2mcorona_flash.bin

REM *** This is a bit hacky for a devkit image...
REM *** Corona BB KHV patches are the same as SB minus the HDD redirection (i.e. fuses and patches are at 0xE0000)
REM *** The "devkit" SD patch looks for XeLL at 0xF4000 because XeBuild can't be consistent in where the start
REM *** of the filesystem in a small block image is. SB patches are ignored pretty much.. just here to make sure
REM *** the sections in the patch file are correct and xeBuild doesn't freak out (plz open source xebuild)
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_devkit.bin + src\KHV\17489_RGLoader\khv_vfuses_devkit.bin output\17489_RGLoader\patches_devjasper.bin
copy output\17489_RGLoader\patches_devjasper.bin output\17489_RGLoader\patches_devxenon.bin
copy output\17489_RGLoader\patches_devjasper.bin output\17489_RGLoader\patches_devzephyr.bin
copy output\17489_RGLoader\patches_devjasper.bin output\17489_RGLoader\patches_devfalcon.bin

echo Done!

echo 17489 XDKBuild...

mkdir output\17489_XDKBuild

REM *** For XDKBuild, the patch sets for 16mb machines are all identical as they use the same loaders and kernel
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_sb.bin + src\KHV\17489_XDKBuild\khv_vfuses_sb.bin output\17489_XDKBuild\patches_g2mjasper.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mxenon.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mxenon_ELPIS.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mzephyr.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mfalcon.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mtrinity.bin
copy output\17489_XDKBuild\patches_g2mjasper.bin output\17489_XDKBuild\patches_g2mcorona.bin

REM *** BB consoles all have different patch sets. C'est la vie.
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_bb.bin + src\KHV\17489_XDKBuild\khv_vfuses_jasperbb.bin output\17489_XDKBuild\patches_g2mjasper_flash.bin
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_bb.bin + src\KHV\17489_XDKBuild\khv_vfuses_trinitybb.bin output\17489_XDKBuild\patches_g2mtrinity_flash.bin
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_sb.bin + src\KHV\17489_XDKBuild\khv_vfuses_coronabb.bin output\17489_XDKBuild\patches_g2mcorona_flash.bin

REM *** This is a bit hacky for a devkit image...
REM *** Corona BB KHV patches are the same as SB minus the HDD redirection (i.e. fuses and patches are at 0xE0000)
REM *** The "devkit" SD patch looks for XeLL at 0xF4000 because XeBuild can't be consistent in where the start
REM *** of the filesystem in a small block image is. SB patches are ignored pretty much.. just here to make sure
REM *** the sections in the patch file are correct and xeBuild doesn't freak out (plz open source xebuild)
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_devkit.bin + src\KHV\17489_XDKBuild\khv_vfuses_devkit.bin output\17489_XDKBuild\patches_devjasper.bin
copy output\17489_XDKBuild\patches_devjasper.bin output\17489_XDKBuild\patches_devxenon.bin
copy output\17489_XDKBuild\patches_devjasper.bin output\17489_XDKBuild\patches_devzephyr.bin
copy output\17489_XDKBuild\patches_devjasper.bin output\17489_XDKBuild\patches_devfalcon.bin

echo Done!

echo 17559 FreeBoot...

mkdir output\17559

copy /b src\2BL\6752\cbb_6752_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\17559\khv_17559_vfuses.bin output\17559\patches_g2mjasper.bin
copy /b src\2BL\5772\cbb_5772_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\17559\khv_17559_vfuses.bin output\17559\patches_g2mfalcon.bin
copy /b src\2BL\7378\cbb_7378_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\17559\khv_17559_vfuses.bin output\17559\patches_g2mxenon_ELPIS.bin

REM *** Xenon and Zephyr use the 5772 CB_B, same as falcon, so the patch sets are the same
copy output\17559\patches_g2mfalcon.bin output\17559\patches_g2mxenon.bin
copy output\17559\patches_g2mfalcon.bin output\17559\patches_g2mzephyr.bin

echo Done!


echo 1888 FreeBoot...

mkdir output\1888

copy /b src\2BL\6752\cbb_6752_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\1888\khv_1888_vfuses_zeus.bin output\1888\patches_g2mjasper.bin
copy /b src\2BL\5772\cbb_5772_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\1888\khv_1888_vfuses_rhea.bin output\1888\patches_g2mfalcon.bin
copy /b src\2BL\5772\cbb_5772_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\1888\khv_1888_vfuses.bin output\1888\patches_g2mxenon.bin

REM *** Zephyr uses the 5772 CB_B and zephyr B/C use the same GPU as falcon, so the patch sets are the same
copy output\1888\patches_g2mfalcon.bin output\1888\patches_g2mzephyr.bin

REM *** Zephyr A with Y1 uses the same GPU and 5772 CB as Xenon. If an elpis has been installed... bascially just a zephyr C
copy output\1888\patches_g2mxenon.bin output\1888\patches_g2mzephyr_y1.bin

REM *** Elpis is basically just a fancy Rhea GPU, so the kernel patch can be the same. Use 7378 loader to avoid Samsung + Rhea hwinit issues
copy /b src\2BL\7378\cbb_7378_vfuses.bin + src\4BL\9452\cd_9452_vfuses.bin + src\KHV\1888\khv_1888_vfuses_rhea.bin output\1888\patches_g2mxenon_ELPIS.bin


echo 1838 XDKBuild...

mkdir output\1838

REM *** 1838 is a bit weird with the patches- ordinarily, you'd thing we'd patch the GPU driver like we do for 1888
REM *** However, the GPU is LESS stable with the ASIC ID and EDRAM patches. So, we'll leave it alone and let 1838
REM *** run in a "low performance" backup mode that's better, but still a bit glitchy. You'll need a Y1 for 1838
REM *** to be useable for anything other than simple demos or looking at the dashboard

copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\12611\sd_vfuses_sb_1838.bin + src\KHV\1838\khv_1838_vfuses.bin output\1838\patches_g2mxenon.bin
copy output\1838\patches_g2mxenon.bin output\1838\patches_g2mzephyr.bin
copy output\1838\patches_g2mxenon.bin output\1838\patches_g2mfalcon.bin
copy output\1838\patches_g2mxenon.bin output\1838\patches_g2mjasper.bin

copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\12611\sd_vfuses_devkit_1838.bin + src\KHV\1838\khv_1838_vfuses_devkit.bin output\1838\patches_devxenon.bin
copy output\1838\patches_devxenon.bin output\1838\patches_devzephyr.bin
copy output\1838\patches_devxenon.bin output\1838\patches_devfalcon.bin
copy output\1838\patches_devxenon.bin output\1838\patches_devjasper.bin

echo Done!

echo.
echo SHA256 hashes:
echo.
certutil -hashfile "output\1888\patches_g2mjasper.bin" SHA256
echo.
certutil -hashfile "output\1888\patches_g2mfalcon.bin" SHA256
echo.

echo.
echo All Done!

pause
goto:eof

:buildPatchSection
bin\xenon-as.exe %~1\%~2.S -I include -I %~1\inc -o %~1\%~2.bin
bin\xenon-objcopy.exe %~1\%~2.bin -O binary
goto:eof
