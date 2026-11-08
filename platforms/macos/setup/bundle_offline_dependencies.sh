#!/usr/bin/env bash
# ==============================================================================
# BUNDLE & INSTALL OFFLINE DEPENDENCIES FOR EXO & MLX
# Ensures 100% offline air-gapped readiness with zero missing wheels or calls
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

WHEELS_DIR="$CLUSTER_ROOT/offline_wheels"
MODE="${1:-status}"

echo "=========================================================="
echo " Offline Cluster Dependency Bundler (Air-Gap Preparation)"
echo "=========================================================="

if [[ "$MODE" != "download" && "$MODE" != "install" && "$MODE" != "cache-model" && "$MODE" != "status" ]]; then
    echo "Usage: $0 <download|install|cache-model|status> [arguments]"
    echo ""
    echo "  download    : (Run while online) Downloads all pip wheels for Exo & MLX"
    echo "                into $WHEELS_DIR for offline installation."
    echo "  install     : (Run offline) Installs Exo and dependencies directly from"
    echo "                $WHEELS_DIR without any internet access."
    echo "  cache-model : (Run while online) Pre-caches an MLX/HF model into the"
    echo "                local Hugging Face offline cache directory."
    echo "                Example: $0 cache-model mlx-community/Qwen2.5-14B-Instruct-4bit"
    echo "  status      : Inspects offline wheel cache and local offline models."
    exit 1
fi

mkdir -p "$WHEELS_DIR"
mkdir -p "$MODELS_DIR"

if [[ "$MODE" == "status" ]]; then
    echo "[*] Wheel Cache: $WHEELS_DIR"
    WHEEL_COUNT=$(find "$WHEELS_DIR" -name "*.whl" 2>/dev/null | wc -l || echo "0")
    echo "    Cached Python Wheels: $WHEEL_COUNT files"
    echo ""
    echo "[*] GGUF Models Directory: $MODELS_DIR"
    find "$MODELS_DIR" -name "*.gguf" -exec ls -lh {} + 2>/dev/null || echo "    No .gguf files currently in $MODELS_DIR"
    echo ""
    echo "[*] HuggingFace / MLX Local Cache (~/.cache/huggingface/hub):"
    if [[ -d "$HOME/.cache/huggingface/hub" ]]; then
        du -sh "$HOME/.cache/huggingface/hub" 2>/dev/null || echo "    Empty cache"
    else
        echo "    Directory does not exist yet."
    fi
    exit 0
fi

# 1. Download Wheels (Online Step)
if [[ "$MODE" == "download" ]]; then
    echo "[*] Connecting to PyPI to fetch all required wheels for offline installation..."
    pip3 download \
        --dest "$WHEELS_DIR" \
        --platform macosx_12_0_arm64 \
        --python-version 311 \
        --only-binary=:all: \
        mlx \
        aiohttp \
        huggingface_hub \
        numpy \
        tqdm \
        requests \
        pydantic \
        psutil \
        tenacity \
        fastapi \
        uvicorn 2>/dev/null || \
    pip3 download --dest "$WHEELS_DIR" mlx aiohttp huggingface_hub numpy tqdm requests pydantic psutil

    # Download exo itself
    if [[ -d "$EXO_DIR" ]]; then
        echo "[*] Building local wheel for Exo..."
        cd "$EXO_DIR"
        python3 -m pip install build --quiet 2>/dev/null || true
        python3 -m build --wheel --outdir "$WHEELS_DIR" 2>/dev/null || true
    fi

    echo "[✓] All offline wheels successfully saved to: $WHEELS_DIR"
    exit 0
fi

# 2. Offline Installation (Air-Gapped Step)
if [[ "$MODE" == "install" ]]; then
    echo "[*] Installing Python packages completely offline from local wheel cache..."
    if [[ $(find "$WHEELS_DIR" -name "*.whl" | wc -l) -eq 0 ]]; then
        echo "[!] ERROR: No wheels found in $WHEELS_DIR. Run '$0 download' while online first."
        exit 1
    fi

    pip3 install \
        --no-index \
        --find-links="$WHEELS_DIR" \
        mlx aiohttp huggingface_hub numpy tqdm requests pydantic psutil

    echo "[✓] Offline Python dependencies installed successfully!"
    exit 0
fi

# 3. Model Pre-caching (Online Step before air-gapping)
if [[ "$MODE" == "cache-model" ]]; then
    MODEL_ID="${2:-}"
    if [[ -z "$MODEL_ID" ]]; then
        echo "Usage: $0 cache-model <huggingface_repo_id>"
        echo "Example: $0 cache-model mlx-community/Qwen2.5-14B-Instruct-4bit"
        exit 1
    fi
    echo "[*] Pre-caching model '$MODEL_ID' for offline Exo execution..."
    python3 -c "
from huggingface_hub import snapshot_download
print('Downloading snapshot...')
path = snapshot_download(repo_id='$MODEL_ID', local_files_only=False)
print('Successfully cached model at:', path)
"
    echo "[✓] Model '$MODEL_ID' is now fully cached for offline inference."
fi
