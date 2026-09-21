@echo off
setlocal
rem Double-click me, or run me from a terminal.
rem
rem A thin launcher only: it makes sure PowerShell 7 is present and hands over to
rem setup.ps1. All the real work lives there, so there is one implementation to
rem maintain rather than a batch copy that drifts.

chcp 65001 >nul 2>&1
pushd "%~dp0"
title Harness setup

rem Pause at the end only when double-clicked, so running this from a terminal
rem does not leave a stray "Press any key". cmdcmdline holds /c when launched
rem from Explorer.
set "_PAUSE="
echo %cmdcmdline% | find /i "%~nx0" >nul && set "_PAUSE=1"

where pwsh >nul 2>&1
if errorlevel 1 goto :nopwsh

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
set "_RC=%ERRORLEVEL%"
goto :done

:nopwsh
echo.
echo   PowerShell 7 is not installed, and this setup needs it.
echo.
where winget >nul 2>&1
if errorlevel 1 (
  echo   Install it from https://aka.ms/powershell  then run this again.
  set "_RC=1"
  goto :done
)
echo   Install it now with winget? [Y/N]
choice /c YN /n >nul
if errorlevel 2 (
  echo   Skipped. Install it, then run this again.
  set "_RC=1"
  goto :done
)
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
echo.
echo   PowerShell installed. Close this window, open a new one, and run setup again.
set "_RC=0"

:done
popd
if defined _PAUSE pause
exit /b %_RC%
