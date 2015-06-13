@echo off
del dataclass.zip >nul 2>&1

cd src
copy ..\README.md .
zip -r ..\dataclass.zip .
del README.md
cd ..

haxelib submit dataclass.zip
del dataclass.zip
