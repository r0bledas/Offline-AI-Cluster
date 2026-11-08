@echo off
setlocal enabledelayedexpansion
title Offline AI Cluster — Automated Setup
color 0b

echo ======================================================================
echo        OFFLINE AI CLUSTER — AUTOMATED 1-CLICK NEW PC SETUP
echo ======================================================================
echo   Host: %COMPUTERNAME% (%OS%)
echo   Path: %CD%
echo ======================================================================
echo.

:: 1. Check Node.js
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] Node.js was not detected in PATH.
    echo [*] Node.js is recommended for the unified CLI controller and bridge.
    echo [*] Download Node.js from https://nodejs.org or install via winget:
    echo     winget install OpenJS.NodeJS.LTS
    echo.
) else (
    for /f "delims=" %%v in ('node -v') do echo [✓] Node.js detected: %%v
)

:: 2. Initialize cluster.config.json
if not exist "cluster.config.json" (
    echo [*] Creating local cluster.config.json from template...
    copy "cluster.config.example.json" "cluster.config.json" >nul
    echo [✓] Created cluster.config.json (Customize worker IPs here).
) else (
    echo [✓] Local cluster.config.json already exists.
)

:: 3. Download & Install Native llama.cpp Binaries
echo.
echo [*] Checking native llama.cpp execution binaries in bin/...
if not exist "bin\llama-server.exe" (
    echo [!] llama-server.exe missing. Fetching official release from GitHub upstream...
    call "%~dp0scripts\update_llama_cpp.bat" --update
) else (
    echo [✓] llama-server.exe and GGML binaries present in bin/.
)

:: 4. Check for Models
echo.
if not exist "models" mkdir "models"
set MODEL_FOUND=0
if exist "models\*.gguf" set MODEL_FOUND=1
if exist "%~dp0models\*.gguf" set MODEL_FOUND=1
if exist "D:\llms\*.gguf" set MODEL_FOUND=1
if exist "C:\llms\*.gguf" set MODEL_FOUND=1

if %MODEL_FOUND% EQU 0 (
    echo [!] No GGUF models found in models\ or standard folders.
    echo.
    echo   [1] Download verified starter model (Llama-3.2-1B-Instruct-Q4_K_M, 807 MB)
    echo   [2] Skip model download (I will provide my own GGUF in models\)
    echo.
    set /p MODEL_CHOICE="Select (1-2) [Default: 1]: "
    if "!MODEL_CHOICE!"=="" set MODEL_CHOICE=1
    if "!MODEL_CHOICE!"=="1" (
        echo [*] Downloading Llama-3.2-1B-Instruct-Q4_K_M.gguf from Hugging Face...
        curl -L "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf" -o "models\Llama-3.2-1B-Instruct-Q4_K_M.gguf"
        if exist "models\Llama-3.2-1B-Instruct-Q4_K_M.gguf" (
            echo [✓] Model downloaded successfully to models\Llama-3.2-1B-Instruct-Q4_K_M.gguf
        )
    )
) else (
    echo [✓] GGUF models detected in local repository or models directory.
)

:: 5. Add to User PATH
echo.
echo [*] Registering cluster CLI in User PATH...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($p -notlike '*%CD%*') { [Environment]::SetEnvironmentVariable('Path', $p + ';%CD%', 'User'); Write-Host '  [+] Added to PATH' } else { Write-Host '  [✓] Already in PATH' }"

:: 6. Create Desktop Shortcut
echo.
echo [*] Creating Desktop launcher shortcut...
set DESKTOP_PATH=%USERPROFILE%\Desktop
if exist "%DESKTOP_PATH%" (
    copy "%~dp0LAUNCH_CLUSTER.bat" "%DESKTOP_PATH%\Offline AI Cluster.bat" >nul
    echo [✓] Desktop launcher placed: "%DESKTOP_PATH%\Offline AI Cluster.bat"
)

:: 7. Complete
echo.
echo ======================================================================
echo   SETUP COMPLETE! The Offline AI Cluster is ready.
echo ======================================================================
echo.
echo   To manage the cluster at any time:
echo     - Double click 'Offline AI Cluster' on your Desktop
echo     - Or run: cluster status / cluster prompt "..."
echo.
set /p LAUNCH_NOW="Launch the Cluster Hub now? (Y/N) [Default: Y]: "
if /i "%LAUNCH_NOW%"=="" set LAUNCH_NOW=Y
if /i "%LAUNCH_NOW%"=="Y" (
    call "%~dp0LAUNCH_CLUSTER.bat"
)
