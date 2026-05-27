@echo off
setlocal
cd /d "%~dp0"

echo Zero Parades - Traducao PT-BR
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar_PTBR.ps1"

echo.
pause
