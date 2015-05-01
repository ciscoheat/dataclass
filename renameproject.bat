@echo off
IF [%1] == [] GOTO noargs
fnr --cl --dir "%CD%" --find "%1" --replace "%2" --fileMask "*.*" --excludeFileMask "*.exe"
fnr --cl --dir "%CD%\bin" --find "%1" --replace "%2" --fileMask "*.*" --excludeFileMask "*.exe" --excludeFileMask "renameproject.bat"
rename "%1.hxml" "%2.hxml"
rename "%1.hxproj" "%2.hxproj"
GOTO end
:noargs
echo Usage: renameproject.bat oldname newname
:end
