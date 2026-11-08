#!/bin/bash
set -e

echo "=== Setting up Offline-AI-Cluster for macOS (Apple Silicon Metal) ==="

if ! command -v cmake &> /dev/null; then
    echo "CMake not found. Installing via Homebrew..."
    brew install cmake ninja git
fi

if [ ! -d "vendor/llama.cpp" ]; then
    echo "Cloning llama.cpp submodule..."
    mkdir -p vendor
    git clone --recursive --depth 1 https://github.com/ggml-org/llama.cpp.git vendor/llama.cpp
fi

cd vendor/llama.cpp
echo "Configuring CMake with Metal and RPC..."
cmake -B build-metal -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DGGML_RPC=ON

echo "Building targets: llama-server, llama-cli, ggml-rpc-server..."
cmake --build build-metal --config Release -j$(sysctl -n hw.ncpu)

echo ""
echo "=== Build Complete! ==="
echo "Binaries located in vendor/llama.cpp/build-metal/bin/"
echo "To start RPC worker: ./vendor/llama.cpp/build-metal/bin/ggml-rpc-server -H 0.0.0.0 -p 50052 -c"
