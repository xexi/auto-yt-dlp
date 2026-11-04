@echo off
setlocal
rem Double-click entry point for install.ps1 (bypasses the default execution policy).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "rc=%ERRORLEVEL%"
rem Keep the window open when launched from Explorer (cmd was started with /c).
echo %cmdcmdline% | findstr /i /c:"/c" >nul && pause
exit /b %rc%
