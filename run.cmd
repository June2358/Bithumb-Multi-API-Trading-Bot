@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0" || exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0coin.ps1"
set "bot_exit_code=%errorlevel%"
popd
if "%bot_exit_code%"=="0" exit /b 0
echo 실행하지 못했습니다. 위 오류를 확인하세요.
echo 계속하려면 아무 키나 누르세요.
pause >nul
exit /b %bot_exit_code%
