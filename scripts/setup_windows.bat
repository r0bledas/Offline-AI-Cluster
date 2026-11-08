@echo off
echo ============================================================
echo   Setting up Offline-AI-Cluster for Windows (MSVC / CMake)
echo ============================================================

where cmake >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] CMake not found. Please install CMake and add it to PATH.
    pause
    exit /b 1
)

if not exist "vendor\llama.cpp" (
    echo Cloning llama.cpp...
    if not exist "vendor" mkdir vendor
    git clone --recursive --depth 1 https://github.com/ggml-org/llama.cpp.git vendor\llama.cpp
)

cd vendor\llama.cpp
echo Configuring CMake for Windows x64 with RPC...
cmake -B build-win -G "Visual Studio 17 2022" -A x64 -DGGML_RPC=ON -DGGML_OPENMP=ON
if %ERRORLEVEL% neq 0 (
    echo Fallback: Attempting default generator...
    cmake -B build-win -DGGML_RPC=ON
)

echo Building Release binaries...
cmake --build build-win --config Release -j %NUMBER_OF_PROCESSORS%

echo.
echo ============================================================
echo   Build Complete!
echo   Binaries: vendor\llama.cpp\build-win\bin\Release\
echo   Run RPC:  build-win\bin\Release\ggml-rpc-server.exe -H 0.0.0.0 -p 50052 -c
echo ============================================================
cd ..\..
pause
