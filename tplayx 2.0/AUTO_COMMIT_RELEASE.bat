@echo off
rem  Build + deploy + commit + push + GitHub release in one go.
rem  Double-click this, or run from a terminal with extra args, e.g.:
rem    AUTO_COMMIT_RELEASE.bat -Message "fix: whatever" -SkipRelease
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AUTO_COMMIT_RELEASE.ps1" %*
pause
