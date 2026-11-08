#!/bin/bash
set -e

echo "=== Setting up Offline-AI-Cluster for Linux ==="

# Auto-detect package manager
if command -v apt-get &> /dev/null; then
    echo "Debian/Ubuntu detected. Installing dependencies..."
    sudo apt-get update && sudo apt-get install -y build-essential cmake git libopenblas-dev
elif command -v pacman &> /dev/null; then
    echo "Arch Linux detected. Installing dependencies..."
    sudo pacman -Syu --needed --noconfirm base-devel cmake git openblas
elif command -v dnf &> /dev/null; then
    echo "Fedora/RHEL detected. Installing dependencies..."
    sudo dnf install -y gcc-c++ make cmake git openblas-devel
elif command -v apk &> /dev/null; then
    echo "Alpine Linux detected. Installing dependencies..."
    apk add --no-cache build-base cmake git openblas-dev linux-headers
fi

if [ ! -d "vendor/llama.cpp" ]; then
    echo "Cloning llama.cpp..."
    mkdir -p vendor
    git clone --recursive --depth 1 https://github.com/ggml-org/llama.cpp.git vendor/llama.cpp
fi

cd vendor/llama.cpp
echo "Configuring CMake with OpenMP and RPC..."
cmake -B build-linux \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_RPC=ON \
    -DGGML_OPENMP=ON

echo "Building targets: llama-server, llama-cli, ggml-rpc-server..."
cmake --build build-linux --config Release -j$(nproc)

echo ""
echo "=== Build Complete! ==="
echo "Binaries located in vendor/llama.cpp/build-linux/bin/"
echo "To start RPC worker: ./vendor/llama.cpp/build-linux/bin/ggml-rpc-server -H 0.0.0.0 -p 50052 -c"
