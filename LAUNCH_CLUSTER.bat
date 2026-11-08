@echo off
setlocal enabledelayedexpansion
title Offline AI Cluster — Master Hub
color 0b

:MENU
cls
echo ======================================================================
echo           OFFLINE AI CLUSTER — DISTRIBUTED EDGE AI
echo ======================================================================
echo   Coordinator: ThinkPad T470 (8 GB DDR4)   [192.168.1.2  / 100.77.73.92]
echo   Worker Node: ThinkPad T450 (16 GB DDR3L) [192.168.1.18 / 100.79.207.24]
echo ======================================================================
echo.
echo   [1] Check Cluster Status & Telemetry (Both Nodes)
echo   [2] Send Quick Inference Prompt (CLI Benchmark)
echo   [3] Open Web Chat Interface (http://localhost:8000)
echo   [4] Start Remote Worker on T450 (ggml-rpc-server)
echo   [5] Start Master Coordinator on T470 (llama-server)
echo   [6] Launch 1-Click Remote Desktop (RDP to T450)
echo   [7] Check & Update Binaries from GitHub Upstream
echo   [8] Open Cluster Terminal (PowerShell with cluster CLI)
echo   [9] Exit
echo.
echo ======================================================================
set /p CHOICE="Select an option (1-9) [Default: 1]: "

if "%CHOICE%"=="" set CHOICE=1
if "%CHOICE%"=="1" goto STATUS
if "%CHOICE%"=="2" goto PROMPT
if "%CHOICE%"=="3" goto WEBUI
if "%CHOICE%"=="4" goto WORKER
if "%CHOICE%"=="5" goto COORD
if "%CHOICE%"=="6" goto RDP
if "%CHOICE%"=="7" goto UPDATE
if "%CHOICE%"=="8" goto SHELL
if "%CHOICE%"=="9" goto EXIT

echo [!] Invalid selection.
timeout /t 2 >nul
goto MENU

:STATUS
cls
call "%~dp0cluster.cmd" status
echo.
pause
goto MENU

:PROMPT
cls
echo ======================================================================
echo   SEND INFERENCE PROMPT TO DISTRIBUTED CLUSTER
echo ======================================================================
echo.
set /p USER_PROMPT="Enter your prompt (or hit Enter for default): "
cls
if "%USER_PROMPT%"=="" (
    call "%~dp0cluster.cmd" prompt
) else (
    call "%~dp0cluster.cmd" prompt "%USER_PROMPT%"
)
echo.
pause
goto MENU

:WEBUI
cls
echo [*] Opening Web Chat UI in browser...
start http://localhost:8000
echo [✓] Opened http://localhost:8000
timeout /t 2 >nul
goto MENU

:WORKER
cls
call "%~dp0cluster.cmd" worker-start
echo.
pause
goto MENU

:COORD
cls
echo [*] Starting Master Coordinator in a dedicated window...
start "Offline AI Cluster - Coordinator" cmd /c "%~dp0platforms\windows\start_coordinator.bat"
echo [✓] Master Coordinator launched on port 8000.
timeout /t 3 >nul
goto MENU

:RDP
cls
call "%~dp0cluster.cmd" rdp
echo.
pause
goto MENU

:UPDATE
cls
call "%~dp0cluster.cmd" update
echo.
pause
goto MENU

:SHELL
cls
echo [*] Launching PowerShell in cluster environment...
start powershell -NoExit -Command "cd '%~dp0'; Write-Host 'Offline AI Cluster environment loaded. Run `cluster help` for commands.' -ForegroundColor Cyan"
goto MENU

:EXIT
exit /b 0
