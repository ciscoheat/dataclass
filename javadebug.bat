@echo off
:start
java -Xdebug -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=y -cp bin/java/obj haxe.root.Tests
goto start