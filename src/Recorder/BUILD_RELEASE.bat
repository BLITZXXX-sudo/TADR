@echo off
setlocal
title TPLAYX release build - BLITZ CLAN
cd /d "%~dp0"
echo Building the RELEASE TPLAYX (optimised, no debug info, symbols stripped)...
echo.
if exist tplayx_release.dll del tplayx_release.dll
"C:\lazarus\lazbuild.exe" tplayx_release.lpi > build_release_log.txt 2>&1
if not exist tplayx_release.dll (
  echo BUILD FAILED - see build_release_log.txt
  findstr /i /c:"Error" /c:"Fatal" build_release_log.txt
  pause
  exit /b 1
)
set "OUT=RELEASE_2026.09.30"
if not exist "%OUT%" mkdir "%OUT%"
copy /y tplayx_release.dll "%OUT%\TPLAYX.dll" >nul
if exist tplayx_release.map move /y tplayx_release.map "%OUT%\TPLAYX_private_symbols.map" >nul
echo.
echo Built: %CD%\%OUT%\TPLAYX.dll
for %%A in ("%OUT%\TPLAYX.dll") do echo Size : %%~zA bytes
certutil -hashfile "%OUT%\TPLAYX.dll" MD5 | findstr /v /i "hash certutil"
echo.
echo Give players ONLY TPLAYX.dll. Keep TPLAYX_private_symbols.map yourself
echo (it lets crash addresses be turned back into function names).
pause
