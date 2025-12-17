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

echo Done!

echo.
echo Building 4BL patch files...

call:buildPatchSection src\4BL\17489 sd_vfuses_bb
call:buildPatchSection src\4BL\17489 sd_vfuses_sb
call:buildPatchSection src\4BL\17489 sd_vfuses_devkit
call:buildPatchSection src\4BL\17489 sd_shadowboot

echo Done!

echo.
echo Building 2BL patch files...

call:buildPatchSection src\2BL\14352 sb_vfuses
call:buildPatchSection src\2BL\14352 sb_shadowboot

echo Done!

echo.
echo Assembling XeBuild patch sets...

echo.
echo 17489 RGLoader...

mkdir output\17489_RGLoader

REM *** For RGLoader, the patch sets for 16mb machines are all identical as they use the same loaders and kernel
copy /b src\2BL\14352\sb_vfuses.bin + src\4BL\17489\sd_vfuses_sb.bin + src\KHV\17489_RGLoader\khv_vfuses_sb.bin output\17489_RGLoader\patches_g2mjasper.bin
copy output\17489_RGLoader\patches_g2mjasper.bin output\17489_RGLoader\patches_g2mxenon.bin
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

echo Done!

echo.
echo SHA256 hashes:
echo.
certutil -hashfile "output\17489_RGLoader\patches_g2mjasper.bin" SHA256
echo.
certutil -hashfile "output\17489_RGLoader\patches_g2mjasper_flash.bin" SHA256
echo.
certutil -hashfile "output\17489_RGLoader\patches_g2mtrinity_flash.bin" SHA256
echo.
certutil -hashfile "output\17489_RGLoader\patches_g2mcorona_flash.bin" SHA256
echo.
certutil -hashfile "output\17489_RGLoader\patches_devjasper.bin" SHA256
echo.

echo.
echo All Done!

pause
goto:eof

:buildPatchSection
bin\xenon-as.exe %~1\%~2.S -I include -I %~1\inc -o %~1\%~2.bin
bin\xenon-objcopy.exe %~1\%~2.bin -O binary
goto:eof