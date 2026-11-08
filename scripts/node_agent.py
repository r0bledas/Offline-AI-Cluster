#!/usr/bin/env python3
"""
Offline-AI-Cluster: Portable Single-Script Worker Agent
Grabs the local ggml-rpc-server binary, auto-detects system RAM and accelerator,
launches the RPC worker, and automatically discovers & registers with the Orchestrator.
Zero external pip dependencies required.
"""

import os
import sys
import time
import socket
import json
import platform
import subprocess
import argparse
import urllib.request
import urllib.error

BEACON_PORT = 50050
RPC_PORT = 50052

def detect_system_ram_gb():
    """Returns total physical RAM in GB using native OS interfaces without pip."""
    sys_name = platform.system()
    try:
        if sys_name == "Windows":
            import ctypes
            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]
            stat = MEMORYSTATUSEX()
            stat.dwLength = ctypes.sizeof(stat)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat))
            return round(stat.ullTotalPhys / (1024**3), 1)
        elif sys_name == "Darwin":
            out = subprocess.check_output(["sysctl", "-n", "hw.memsize"]).decode().strip()
            return round(int(out) / (1024**3), 1)
        else: # Linux / POSIX
            with open("/proc/meminfo") as f:
                for line in f:
                    if "MemTotal" in line:
                        kb = int(line.split()[1])
                        return round(kb / (1024**2), 1)
    except Exception:
        return 8.0

def detect_accelerator():
    sys_name = platform.system()
    machine = platform.machine()
    if sys_name == "Darwin" and ("arm" in machine or "m1" in machine or "m2" in machine):
        return "metal_apple_silicon"
    # Check for NVIDIA CUDA
    try:
        devnull = subprocess.DEVNULL
        if subprocess.call(["nvidia-smi"], stdout=devnull, stderr=devnull) == 0:
            return "nvidia_cuda"
    except Exception:
        pass
    if "arm" in machine.lower() or "aarch64" in machine.lower():
        return "arm64_neon"
    return "cpu_avx2"

def find_rpc_binary():
    """Locates the ggml-rpc-server binary in common local build directories."""
    binary_names = ["ggml-rpc-server", "ggml-rpc-server.exe"]
    search_dirs = [
        ".",
        "bin",
        "build/bin",
        "build-metal/bin",
        "build-linux/bin",
        "build-win/bin/Release",
        "build-win/bin",
        "vendor/llama.cpp/build/bin",
        "vendor/llama.cpp/build-metal/bin",
        "vendor/llama.cpp/build-linux/bin",
        "vendor/llama.cpp/build-win/bin/Release",
        "../vendor/llama.cpp/build/bin"
    ]
    for d in search_dirs:
        for b in binary_names:
            p = os.path.join(d, b)
            if os.path.exists(p) and os.path.isfile(p):
                return os.path.abspath(p)
    return None

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) == 0

def discover_orchestrator(timeout=3.0):
    """Sends UDP broadcast to find the Orchestrator on the local subnet."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(timeout)

    payload = json.dumps({
        "event": "discover",
        "name": socket.gethostname(),
        "rpc_port": RPC_PORT,
        "memory_gb": detect_system_ram_gb(),
        "accelerator": detect_accelerator()
    }).encode("utf-8")

    print(f"[AutoDiscovery] Broadcasting on UDP port {BEACON_PORT} for Orchestrator...")
    try:
        sock.sendto(payload, ("<broadcast>", BEACON_PORT))
        data, addr = sock.recvfrom(2048)
        reply = json.loads(data.decode("utf-8"))
        print(f"[AutoDiscovery] Found Orchestrator at {addr[0]}!")
        return addr[0]
    except socket.timeout:
        return None
    finally:
        sock.close()

def register_via_http(orchestrator_ip, http_port=8000):
    """Direct HTTP registration fallback."""
    url = f"http://{orchestrator_ip}:{http_port}/cluster/register"
    data = json.dumps({
        "name": socket.gethostname(),
        "rpc_port": RPC_PORT,
        "memory_gb": detect_system_ram_gb(),
        "accelerator": detect_accelerator()
    }).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

def main():
    parser = argparse.ArgumentParser(description="Portable Worker Node Agent for Offline-AI-Cluster")
    parser.add_argument("--orchestrator", "-o", help="Explicit Orchestrator IP address (skips auto-discovery)")
    parser.add_argument("--port", "-p", type=int, default=RPC_PORT, help="RPC worker listening port")
    parser.add_argument("--binary", "-b", help="Path to ggml-rpc-server executable")
    args = parser.parse_args()

    ram_gb = detect_system_ram_gb()
    accel = detect_accelerator()
    hostname = socket.gethostname()

    print("=" * 65)
    print("      OFFLINE-AI-CLUSTER: PORTABLE WORKER NODE AGENT")
    print("=" * 65)
    print(f"Hostname:    {hostname}")
    print(f"System RAM:  {ram_gb} GB")
    print(f"Accelerator: {accel}")
    print(f"RPC Port:    {args.port}")
    print("-" * 65)

    # 1. Verify or launch ggml-rpc-server
    if is_port_in_use(args.port):
        print(f"[RPC Server] Port {args.port} is already active. Using running instance.")
    else:
        rpc_bin = args.binary or find_rpc_binary()
        if not rpc_bin:
            print(f"\n[Error] Could not find 'ggml-rpc-server' binary!")
            print("Please build it first or specify --binary <path/to/ggml-rpc-server>.")
            print("To build: run ./scripts/setup_macos.sh, setup_linux.sh, or setup_windows.bat")
            sys.exit(1)

        print(f"[RPC Server] Starting binary: {rpc_bin}")
        cmd = [rpc_bin, "-H", "0.0.0.0", "-p", str(args.port), "-c"]
        try:
            # Spawn background RPC worker process
            subprocess.Popen(cmd)
            time.sleep(1.0)
            print(f"[RPC Server] Worker listening on 0.0.0.0:{args.port} (Cache enabled)")
        except Exception as e:
            print(f"[Error] Failed to launch RPC binary: {e}")
            sys.exit(1)

    # 2. Connect to Orchestrator
    orchestrator_ip = args.orchestrator
    if not orchestrator_ip:
        orchestrator_ip = discover_orchestrator()

    if not orchestrator_ip:
        print("\n[AutoDiscovery] No response from UDP broadcast beacon.")
        print("Please enter the Orchestrator IP manually, or start 'python scripts/gateway.py' on the Orchestrator.")
        try:
            orchestrator_ip = input("Orchestrator IP [e.g. 192.168.1.100]: ").strip()
        except KeyboardInterrupt:
            sys.exit(0)

    if not orchestrator_ip:
        print("[Error] No Orchestrator specified. Worker running independently on port", args.port)
        sys.exit(1)

    # 3. Complete Handshake & Registration
    try:
        reg_result = register_via_http(orchestrator_ip)
        print(f"\n[Handshake Success] Registered with Orchestrator at {orchestrator_ip}!")
        print(f"Cluster Total Nodes: {reg_result.get('cluster_total_nodes', 'unknown')}")
        print(f"Active launch flags on Orchestrator:")
        print(f"  {reg_result.get('orchestrator_flags', '')}")
    except Exception as e:
        print(f"[Warning] HTTP registration with {orchestrator_ip} returned: {e}")
        print("Worker is listening on port", args.port, "and can still receive RPC connections directly.")

    print("\n" + "=" * 65)
    print("Worker active. Ready for tensor execution. Press Ctrl+C to disconnect.")
    print("=" * 65)

    try:
        while True:
            time.sleep(10)
    except KeyboardInterrupt:
        print("\nWorker stopped.")

if __name__ == "__main__":
    main()
