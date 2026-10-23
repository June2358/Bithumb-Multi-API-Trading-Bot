@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where uv >nul 2>&1
if errorlevel 1 (
    echo uv가 필요합니다. winget install --id astral-sh.uv -e 실행 후 다시 여세요.
    goto :error
)
uv sync --locked --no-dev
if errorlevel 1 goto :error
if not exist api_keys.json (
    echo api_keys.sample.json을 api_keys.json으로 복사하고 API 1.0 키를 입력하세요.
    goto :error
)
echo 실제 시장가 주문을 실행하며 기존 보유 코인을 포함한 사용 가능 잔액 전량을 매도합니다.
choice /c YN /n /m "실거래를 시작하려면 Y, 취소하려면 N을 누르세요: "
if errorlevel 2 exit /b 0
if not errorlevel 1 exit /b 0
uv run --locked --no-dev python coin.py
if errorlevel 1 goto :error
exit /b 0
:error
echo 실행하지 못했습니다. 위 오류를 확인하세요.
pause
exit /b 1
