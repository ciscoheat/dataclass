@echo off
IF [%1] == [] GOTO noargs
fnr --cl --dir "%CD%" --find "%1" --replace "%2" --fileMask "*.*" --excludeFileMask "*.exe"
fnr --cl --dir "%CD%\bin" --find "%1" --replace "%2" --fileMask "*.*" --excludeFileMask "*.exe" --excludeFileMask "renameproject.bat"
rename "%1.hxml" "%2.hxml"
rename "%1.hxproj" "%2.hxproj"
rename "%1.sublime-project" "%2.sublime-project"
rename "%1.sublime-workspace" "%2.sublime-workspace"
GOTO end
:noargs
echo Usage: renameproject.bat oldname newname
echo Initial 'oldname' is 'nodeproject'.
:end
