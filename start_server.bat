@echo off
setlocal
title GTA HTTP GPU server
cd /d "%~dp0"

echo === GTA HTTP GPU server ===
echo.

rem --- find Python 3 -----------------------------------------------------------
set "PY="
where py >nul 2>&1 && (py -3 -c "import sys" >nul 2>&1 && set "PY=py -3")
if not defined PY (where python >nul 2>&1 && (python -c "import sys; assert sys.version_info >= (3, 9)" >nul 2>&1 && set "PY=python"))
if not defined PY (
    echo Python 3 was not found.
    echo Install it from https://www.python.org/downloads/windows/  and tick "Add python.exe to PATH", then run this file again.
    echo.
    pause
    exit /b 1
)
for /f "delims=" %%v in ('%PY% -c "import sys; print(sys.version.split()[0])"') do echo Python %%v

rem --- first run: install the Python packages ------------------------------------
%PY% -c "import playwright, PIL, numpy, zstandard" >nul 2>&1
if errorlevel 1 (
    echo Installing Python packages (first run only)...
    %PY% -m pip install --upgrade pip >nul
    %PY% -m pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo Package install failed - see the error above.
        pause
        exit /b 1
    )
)

rem --- Microsoft Edge is used as the headless GPU browser ------------------------
if not exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" if not exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" (
    echo Microsoft Edge was not found; the game will render on the CPU (very slow).
    echo Install Edge from https://www.microsoft.com/edge for GPU rendering.
    echo Downloading a fallback browser...
    %PY% -m playwright install chromium
    echo.
)

rem --- stop an old server / leftover capture browsers -----------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue };" ^
  "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe' OR Name='chrome.exe'\" | Where-Object { $_.CommandLine -match 'playwright_chromiumdev_profile|\\.capture-profile' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

echo.
echo Server: http://127.0.0.1:8765/
echo Now open the Roblox place in Studio and press Play. Keep this window open while playing.
echo (Ctrl+C or closing this window stops the stream.)
echo.
%PY% -X faulthandler -u serve.py
echo.
echo serve.py exited with code %errorlevel%
pause
