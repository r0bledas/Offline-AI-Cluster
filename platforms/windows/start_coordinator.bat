@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0\..\.."
set REPO_ROOT=%CD%
set BIN_DIR=%REPO_ROOT%\bin
set LLAMA_SERVER=%BIN_DIR%\llama-server.exe

if not exist "%LLAMA_SERVER%" (
    if exist "%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp\llama-server.exe" (
        set LLAMA_SERVER=%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp\llama-server.exe
        set BIN_DIR=%USERPROFILE%\Downloads\eLlama-Portable-v1.2.0-win-x64\llama.cpp
    ) else (
        echo [!] llama-server.exe not found in %BIN_DIR%!
        echo [*] Running updater to download latest binaries...
        call "%REPO_ROOT%\scripts\update_llama_cpp.bat" --update
    )
)

echo ========================================================
echo   Offline-AI-Cluster :: Windows Master Coordinator
echo ========================================================
echo [Info] Engine Path: %LLAMA_SERVER%
echo.

set MODEL_PATH=%~1
if "%MODEL_PATH%"=="" (
    if exist "D:\llms\Llama-3.2-1B-Instruct-Q4_K_M.gguf" (
        set MODEL_PATH=D:\llms\Llama-3.2-1B-Instruct-Q4_K_M.gguf
    ) else if exist "D:\llms\qwen2.5-0.5b-instruct-q4_k_m.gguf" (
        set MODEL_PATH=D:\llms\qwen2.5-0.5b-instruct-q4_k_m.gguf
    ) else if exist "D:\llms\Qwen3.8-27B-Q4_K_M.gguf" (
        set MODEL_PATH=D:\llms\Qwen3.8-27B-Q4_K_M.gguf
    ) else (
        echo [ERROR] No model GGUF specified or found in D:\llms\.
        echo Usage: start_coordinator.bat [path_to_model.gguf] [worker_ip:port]
        pause
        exit /b 1
    )
)

set WORKER_RPC=%~2
if "%WORKER_RPC%"=="" (
    set WORKER_RPC=192.168.1.18:50052
)

set HOST=0.0.0.0
set PORT=8000
set CTX=2048
set THREADS=4

echo [Config] Model:   %MODEL_PATH%
echo [Config] Workers: %WORKER_RPC%
echo [Config] API:     http://%HOST%:%PORT%/v1
echo [Config] Threads: %THREADS%
echo.
echo [*] Launching Master Orchestrator with cross-node tensor splitting...
echo.

set PATH=%BIN_DIR%;%PATH%
"%LLAMA_SERVER%" -m "%MODEL_PATH%" --rpc "%WORKER_RPC%" -c %CTX% -t %THREADS% --host %HOST% --port %PORT%

pause
