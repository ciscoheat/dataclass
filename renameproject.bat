@echo off
IF [%1] == [] GOTO usage
fnr --cl --dir "%CD%" --find "nodeproject" --replace "%1" --fileMask "*.*" --excludeFileMask "renameproject.bat"
fnr --cl --dir "%CD%\bin" --find "nodeproject" --replace "%1" --fileMask "*.*" --excludeFileMask "renameproject.bat"
rename "nodeproject.hxml" "%1.hxml"
rename "nodeproject.hxproj" "%1.hxproj"
rename "nodeproject.sublime-project" "%1.sublime-project"
rename "nodeproject.sublime-workspace" "%1.sublime-workspace"
del fnr.exe
del renameproject.bat
GOTO end
:usage
echo Usage: renameproject.bat newname
:end
