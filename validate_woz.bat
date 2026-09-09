@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate_woz.ps1" %*
exit /b %ERRORLEVEL%
