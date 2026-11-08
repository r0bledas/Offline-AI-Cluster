#!/usr/bin/env python3
"""
Offline-AI-Cluster Direct Update Manager
Inspired by eLlama's UpdateManager: directly checks, downloads, and updates
llama.cpp engine binaries and cluster components with zero third-party dependencies.
"""

import sys
import os
import json
import re
import platform
import shutil
import zipfile
import tarfile
import urllib.request
import urllib.error
import argparse
from pathlib import Path

GITHUB_LLAMACPP_RELEASES = "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5"
GITHUB_CLUSTER_RELEASES = "https://api.github.com/repos/r0bledas/Offline-AI-Cluster/releases?per_page=5"
USER_AGENT = "Offline-AI-Cluster-Updater/1.0"

def get_platform_info():
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in ["x86_64", "amd64"]:
        arch = "x64"
    elif machine in ["arm64", "aarch64"]:
        arch = "arm64"
    else:
        arch = machine
    return system, arch

def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def parse_build_number(tag_str):
    if not tag_str:
        return 0
    match = re.search(r"b(\d+)", tag_str, re.IGNORECASE)
    if match:
        return int(match.group(1))
    clean = re.sub(r"^[^\d]*", "", tag_str)
    try:
        return int(clean.split(".")[0])
    except ValueError:
        return 0

def get_installed_llamacpp_version(bin_dir):
    version_file = bin_dir / ".llama_cpp_version"
    if version_file.exists():
        try:
            return version_file.read_text().strip()
        except Exception:
            pass
    
    server_binary = bin_dir / ("llama-server.exe" if platform.system() == "Windows" else "llama-server")
    if server_binary.exists():
        try:
            import subprocess
            out = subprocess.check_output([str(server_binary), "--version"], stderr=subprocess.STDOUT, text=True, timeout=5)
            match = re.search(r"version:\s*(\d+|b\d+)", out, re.IGNORECASE)
            if match:
                return f"b{match.group(1)}" if not match.group(1).startswith("b") else match.group(1)
        except Exception:
            pass
    return "unknown"

def find_best_llamacpp_asset(release, system, arch, preferred_backend="vulkan"):
    assets = release.get("assets", [])
    
    candidates = []
    for asset in assets:
        name = asset.get("name", "").lower()
        url = asset.get("browser_download_url")
        size = asset.get("size", 0)
        
        if system == "windows":
            if not name.endswith(".zip") or "win" not in name:
                continue
            if arch == "x64" and "x64" in name:
                if preferred_backend == "vulkan" and "vulkan" in name:
                    return asset
                elif preferred_backend == "cpu" and ("cpu" in name or "avx2" in name) and "vulkan" not in name and "cuda" not in name:
                    candidates.append(asset)
                elif "bin" in name and "cuda" not in name:
                    candidates.append(asset)
            elif arch == "arm64" and "arm64" in name:
                candidates.append(asset)
        elif system == "darwin": # macOS
            if "macos" in name or "osx" in name or "darwin" in name:
                if arch == "arm64" and "arm64" in name:
                    return asset
                elif arch == "x64" and "x64" in name:
                    return asset
                candidates.append(asset)
        elif system == "linux":
            if "ubuntu" in name or "linux" in name:
                if arch == "x64" and ("x64" in name or "amd64" in name):
                    if preferred_backend == "vulkan" and "vulkan" in name:
                        return asset
                    candidates.append(asset)
                elif arch == "arm64" and "arm64" in name:
                    candidates.append(asset)
                    
    if candidates:
        return candidates[0]
    return None

def download_file(url, dest_path):
    print(f"[*] Downloading {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dest_path, "wb") as f:
        total = int(resp.headers.get("content-length", 0))
        downloaded = 0
        chunk_size = 1024 * 1024
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                percent = (downloaded / total) * 100
                sys.stdout.write(f"\r    -> {downloaded / 1024 / 1024:.1f} MB / {total / 1024 / 1024:.1f} MB ({percent:.1f}%)")
                sys.stdout.flush()
    print("\n[+] Download complete.")

def extract_archive(archive_path, extract_dir):
    print(f"[*] Extracting {archive_path.name} to {extract_dir} ...")
    extract_dir.mkdir(parents=True, exist_ok=True)
    temp_dir = extract_dir / "_temp_extract"
    temp_dir.mkdir(parents=True, exist_ok=True)

    try:
        if archive_path.suffix.lower() == ".zip":
            with zipfile.ZipFile(archive_path, "r") as z:
                z.extractall(temp_dir)
        elif archive_path.name.lower().endswith((".tar.gz", ".tgz")):
            with tarfile.open(archive_path, "r:gz") as t:
                t.extractall(temp_dir)
        else:
            raise ValueError(f"Unsupported archive format: {archive_path.name}")

        # Flatten nested directory if the archive contains a single root folder
        items = list(temp_dir.iterdir())
        source_dir = items[0] if (len(items) == 1 and items[0].is_dir()) else temp_dir

        for item in source_dir.rglob("*"):
            if item.is_file():
                rel_path = item.relative_to(source_dir)
                dest_file = extract_dir / rel_path
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, dest_file)

        print("[+] Extraction and binary installation successful.")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def check_llamacpp_update(bin_dir, backend="vulkan"):
    system, arch = get_platform_info()
    current = get_installed_llamacpp_version(bin_dir)
    print(f"[*] Platform: {system}-{arch} | Target backend: {backend}")
    print(f"[*] Installed llama.cpp build: {current}")

    try:
        releases = fetch_json(GITHUB_LLAMACPP_RELEASES)
    except Exception as e:
        print(f"[-] Error querying GitHub releases: {e}")
        return False, current, None, None

    if not releases:
        print("[-] No releases returned from GitHub.")
        return False, current, None, None

    latest_release = releases[0]
    tag = latest_release.get("tag_name", "")
    current_build_num = parse_build_number(current)
    latest_build_num = parse_build_number(tag)

    print(f"[*] Latest upstream llama.cpp build: {tag} (build #{latest_build_num})")

    asset = find_best_llamacpp_asset(latest_release, system, arch, backend)
    has_update = (latest_build_num > current_build_num) if (current_build_num > 0 and latest_build_num > 0) else (current == "unknown")
    
    return has_update, current, tag, asset

def update_llamacpp(bin_dir, backend="vulkan", force=False):
    has_update, current, tag, asset = check_llamacpp_update(bin_dir, backend)
    
    if not has_update and not force:
        print(f"[✓] llama.cpp is already up to date ({current}).")
        return True

    if not asset:
        print(f"[-] Could not find a matching binary asset for {platform.system()}-{platform.machine()} with backend {backend}.")
        return False

    url = asset.get("browser_download_url")
    asset_name = asset.get("name", "llama-bin.zip")
    archive_dest = bin_dir / asset_name

    download_file(url, archive_dest)
    try:
        extract_archive(archive_dest, bin_dir)
        (bin_dir / ".llama_cpp_version").write_text(tag)
        print(f"[✓] Successfully upgraded llama.cpp to {tag} in {bin_dir}!")
        return True
    finally:
        if archive_dest.exists():
            archive_dest.unlink()

def main():
    parser = argparse.ArgumentParser(description="Offline-AI-Cluster Direct Update Manager")
    parser.add_argument("--check", action="store_true", help="Check for available updates without installing")
    parser.add_argument("--update", action="store_true", help="Download and install updates")
    parser.add_argument("--force", action="store_true", help="Force re-download even if already up to date")
    parser.add_argument("--backend", choices=["vulkan", "cpu"], default="vulkan", help="Hardware accelerator backend (default: vulkan)")
    parser.add_argument("--bin-dir", default=None, help="Target directory for binaries (default: repo root / bin)")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    bin_dir = Path(args.bin_dir).resolve() if args.bin_dir else (repo_root / "bin")
    bin_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print(" Offline-AI-Cluster Update Manager")
    print(" Inspired by eLlama's Direct-Update Architecture")
    print("=" * 60)

    if args.check:
        has_update, current, tag, asset = check_llamacpp_update(bin_dir, args.backend)
        if has_update:
            print(f"[!] Update AVAILABLE: {current} -> {tag}")
            if asset:
                print(f"    Asset: {asset.get('name')} ({asset.get('size', 0) / 1024 / 1024:.1f} MB)")
        else:
            print(f"[✓] Everything is up to date ({current}).")
    else:
        # Default or --update
        update_llamacpp(bin_dir, args.backend, args.force)

if __name__ == "__main__":
    main()
