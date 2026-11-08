@echo off
setlocal
cd /d "%~dp0\.."

echo ========================================================
echo   Offline-AI-Cluster :: Direct llama.cpp Updater
echo   (eLlama-style automated binary synchronization)
echo ========================================================
echo.

where node >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    node "%~dp0updater.js" %*
    goto done
)

where python >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python "%~dp0updater.py" %*
    goto done
)

where py >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    py -3 "%~dp0updater.py" %*
    goto done
)

echo [ERROR] Neither Node.js nor Python 3 was detected on your PATH.
echo Please install Node.js (recommended) or Python 3 to run automatic updates.
pause
exit /b 1

:done
echo.
pause
