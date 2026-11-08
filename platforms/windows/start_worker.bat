@echo off
setlocal

cd /d "%~dp0\..\.."
set REPO_ROOT=%CD%
set BIN_DIR=%REPO_ROOT%\bin
set RPC_SERVER=%BIN_DIR%\ggml-rpc-server.exe

if not exist "%RPC_SERVER%" (
    if exist "%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp\ggml-rpc-server.exe" (
        set RPC_SERVER=%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp\ggml-rpc-server.exe
        set BIN_DIR=%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp
    ) else (
        echo [!] ggml-rpc-server.exe not found in %BIN_DIR%!
        echo [*] Running updater to download latest binaries...
        call "%REPO_ROOT%\scripts\update_llama_cpp.bat" --update
    )
)

set HOST=0.0.0.0
set PORT=50052
set THREADS=4

echo ========================================================
echo   Offline-AI-Cluster :: Windows Worker Compute Node
echo ========================================================
echo [Info] Engine Path: %RPC_SERVER%
echo [Config] Binding:   %HOST%:%PORT%
echo [Config] Threads:   %THREADS%
echo.
echo [*] Listening for tensor operations from Coordinator...
echo.

set PATH=%BIN_DIR%;%PATH%
"%RPC_SERVER%" -H %HOST% -p %PORT% -t %THREADS%

pause
