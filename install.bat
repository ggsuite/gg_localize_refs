@echo off
REM Delete the .dart_tool folder
rmdir /S /Q .dart_tool

REM Activate the package from local source
dart pub global activate --source path .

REM Add any additional commands below if needed
