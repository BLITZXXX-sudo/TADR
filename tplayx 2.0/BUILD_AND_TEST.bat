@echo off
rem One-click: build tplayx.dll, gate warnings, deploy to the game, launch and verify.
rem Extra switches are passed through, e.g.  BUILD_AND_TEST.bat -Debug  -Strict  -KeepRunning
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_AND_TEST.ps1" %*
echo.
if errorlevel 1 (echo *** BUILD/TEST FAILED - see _build\last_result.txt ***) else (echo *** BUILD/TEST PASSED ***)
pause
