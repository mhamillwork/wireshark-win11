@echo off
setlocal EnableExtensions
set LOG=C:\OEM\wireshark-setup.log
echo %DATE% %TIME% OEM setup>"%LOG%"

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v Wireshark /t REG_SZ /d "cmd.exe /c C:\OEM\launch-wireshark.cmd >> C:\OEM\wireshark-launch.log 2>&1" /f >>"%LOG%" 2>&1

if not exist "C:\Users\Public\Desktop" mkdir "C:\Users\Public\Desktop"
copy /Y "C:\OEM\wireshark.cmd" "C:\Users\Public\Desktop\Wireshark.cmd" >>"%LOG%" 2>&1
copy /Y "C:\OEM\build-wireshark-installer.cmd" "C:\Users\Public\Desktop\Build Wireshark Installer.cmd" >>"%LOG%" 2>&1

call C:\OEM\launch-wireshark.cmd >>"%LOG%" 2>&1
exit /b 0
