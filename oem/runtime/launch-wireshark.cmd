@echo off
setlocal EnableExtensions EnableDelayedExpansion
set LOG=C:\OEM\wireshark-launch.log
echo %DATE% %TIME% launch>>"%LOG%"

if exist "C:\Program Files\Wireshark\Wireshark.exe" goto run

set INSTALLER=
for %%F in ("C:\OEM\Wireshark-*-x64.exe") do (
  if exist "%%~fF" set "INSTALLER=%%~fF"
)
for %%F in ("C:\Users\Public\Desktop\Shared\Wireshark-*-x64.exe") do (
  if exist "%%~fF" set "INSTALLER=%%~fF"
)
for %%F in ("C:\Users\Docker\Desktop\Shared\Wireshark-*-x64.exe") do (
  if exist "%%~fF" set "INSTALLER=%%~fF"
)
for %%F in ("Z:\Wireshark-*-x64.exe") do (
  if exist "%%~fF" set "INSTALLER=%%~fF"
)

if not defined INSTALLER (
  echo Installer not found.>>"%LOG%"
  echo Wireshark installer was not found.
  echo Run automation\build-windows-installer.sh on the host, then open Wireshark.cmd again.
  exit /b 1
)

echo Installing "!INSTALLER!">>"%LOG%"
"!INSTALLER!" /S
set RC=!ERRORLEVEL!
echo Installer exit !RC!>>"%LOG%"
if not "!RC!"=="0" exit /b !RC!

:run
if not exist "C:\Program Files\Wireshark\Wireshark.exe" (
  echo Wireshark.exe is missing after install.>>"%LOG%"
  exit /b 1
)
start "" "C:\Program Files\Wireshark\Wireshark.exe"
exit /b 0
