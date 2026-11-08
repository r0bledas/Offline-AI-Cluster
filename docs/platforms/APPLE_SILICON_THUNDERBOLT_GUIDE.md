# The Foolproof Offline AI Cluster Handbook: Dual-Mac M2 Edition

An exhaustive operational guide, troubleshooting manual, edge-case playbook, and architectural reference for clustering an **Apple Silicon M2 MacBook Air (16 GB)** and an **M2 MacBook Pro (8 GB)** into a unified **19.0 GB Usable VRAM** offline inference engine.

---

## 0. Hardware & System Prerequisites

Ensure you have gathered all hardware and verified system tools before taking the cluster into an air-gapped environment:

### Hardware Requirements
* **Node A (Coordinator)**: Apple Silicon M2 MacBook Air (16 GB Unified LPDDR5).
* **Node B (Worker)**: Apple Silicon M2 MacBook Pro (8 GB Unified LPDDR5).
* **Interconnect Cable**: Authentic **Active Thunderbolt 3, TB4, or active USB4 cable** (40 Gbps marked with `⚡`).
  * *Important*: Standard white Apple charging cables are limited to USB 2.0 (480 Mbps) and will severely choke tensor transfer.
* **Alternative Interconnect**: Two USB-C to Ethernet (1GbE / 2.5GbE / 10GbE) adapters with a Cat6/Cat6a patch cable (Auto-MDIX).
* **Power Adapter**: Required for Node B to stay awake with lid closed in headless clamshell mode.
* **Local Storage**: 20–30 GB free NVMe space on Node A for `.gguf` models; ~2 GB free space on Node B.

### Software & Binary Requirements
* **macOS**: macOS 13.0 (Ventura), macOS 14.0 (Sonoma), or macOS 15.0+ (Sequoia).
* **Xcode Command Line Tools**: `xcode-select --install` (provides `clang`, `git`, and Metal headers).
* **CMake**: Version 3.20+ (`brew install cmake` or static binary).
* **Python**: Python 3.10+ (macOS native or `uv`), only if using **Exo** or Python test utilities.
* **Privileges**: Administrator / `sudo` access on both Macs.

### Mandatory Binary Prerequisites on Both Nodes
* **On Node A (MacBook Air 16GB)**:
  * `llama-server` Mach-O arm64 binary (built with `GGML_METAL=ON` and `GGML_RPC=ON`).
  * *Or for Exo*: Installed `exo` and `mlx` Python packages.
* **On Node B (MacBook Pro 8GB)**:
  * `rpc-server` Mach-O arm64 binary (built with `GGML_METAL=ON` and `GGML_RPC=ON`).
  * *Or for Exo*: Installed `exo` and `mlx` Python packages.

> **Single-Compile Portability**: Since both Macs use the identical Apple Silicon M2 ARM64 instruction set, binaries compiled on Node A via `./setup/02_build_llamacpp.sh` run natively on Node B. You can simply copy the `llama.cpp/build/bin/` folder directly to Node B's `bin/` directory over AirDrop, USB drive, or Thunderbolt.

---

## 1. Diagnostic Decision Trees

### 1.1 Network Interconnect Diagnostic Tree

```mermaid
flowchart TD
    Start["Ping 192.168.100.2 from Node A"] --> PingSuccess{"Ping Responds &lt; 0.3ms?"}
    
    PingSuccess -- YES --> PortCheck["nc -z -w 3 192.168.100.2 50052"]
    PingSuccess -- NO --> CableType{"Is the cable authentic Thunderbolt 3/4?"}
    
    CableType -- NO (White Apple USB-C) --> SwapCable["REPLACE CABLE: White Apple charging cable only carries USB 2.0 (480 Mbps). Use an active 40 Gbps Thunderbolt cable."]
    CableType -- YES --> IfconfigCheck["Check 'ifconfig bridge0' on both Macs"]
    
    IfconfigCheck --> IPCheck{"Are static IPs set correctly?"}
    IPCheck -- NO (169.254.x.x) --> RunNetScript["Run 'sudo ./setup/01_thunderbolt_network.sh node-a' on Air<br/>and 'node-b' on Pro."]
    IPCheck -- YES --> FirewallCheck["Disable macOS Application Firewall temporarily:<br/>System Settings > Network > Firewall > OFF"]
    
    PortCheck --> PortOpen{"Port 50052 Open?"}
    PortOpen -- YES --> ReadyNet["Network & RPC Layer: 100% OPERATIONAL"]
    PortOpen -- NO --> WorkerStatus["Check Node B terminal: Is 'start_worker_node_b.sh' running and bound to 192.168.100.2?"]
```

---

### 1.2 VRAM & Memory Allocation Diagnostic Tree

```mermaid
flowchart TD
    StartMem["Load Model on Node A Coordinator"] --> OOMCheck{"Does process crash with Metal buffer / OOM error?"}
    
    OOMCheck -- NO --> InferenceRunning["Inference Runs Smoothly (19.0 GB Pooled VRAM)"]
    OOMCheck -- YES --> CheckSysctl["Run './scripts/vram_mode.sh status' on both Macs"]
    
    CheckSysctl --> SysctlActive{"Is 'iogpu.wired_limit_mb' elevated?"}
    SysctlActive -- NO (Shows 0) --> BoostRAM["Apply VRAM boost:<br/>Node A: sudo ./scripts/vram_mode.sh on node-a (13312 MB)<br/>Node B: sudo ./scripts/vram_mode.sh on node-b (6144 MB)"]
    
    SysctlActive -- YES --> CheckModelSize["Run 'python3 scripts/calculate_split.py --model-gb &lt;size&gt; --ctx &lt;tokens&gt;'"]
    CheckModelSize --> HeadroomCheck{"Is headroom negative or &lt; 0.5 GB?"}
    
    HeadroomCheck -- YES --> ApplyRemedies["REMEDIES:<br/>1. Reduce context size from 32k to 8192 (-c 8192)<br/>2. Quantize KV cache: Add '-ctk q8_0 -ctv q8_0'<br/>3. Switch to Q4_K_M quant instead of Q8_0<br/>4. Close background browser tabs / Electron apps on Node B"]
    HeadroomCheck -- NO --> AdjustSplit["Adjust '--tensor-split': Shift 1 GB from Pro to Air (e.g. '--tensor-split 13.5,5.5')"]
```

---

### 1.3 Thermal & Performance Diagnostic Tree

```mermaid
flowchart TD
    StartPerf["Benchmark Inference Speed (llama-bench)"] --> TPSCheck{"Token Generation Speed &gt; 12 tokens/sec (14B Q4)?"}
    
    TPSCheck -- YES --> ThermalOK["Thermals and bus bandwidth are operating at peak efficiency."]
    TPSCheck -- NO (&lt; 6 tokens/sec) --> SpeedDrop{"Did speed start fast and drop after 5-10 minutes?"}
    
    SpeedDrop -- YES (Thermal Throttling) --> AirThrottle["MacBook Air (Fanless) is heat soaked (~95°C):<br/>1. Place Air on an elevated aluminum stand or mesh riser.<br/>2. Direct an external desk fan at the bottom chassis.<br/>3. Shift layer proportion towards actively-cooled Node B Pro."]
    SpeedDrop -- NO (Always slow) --> MTUCheck{"Check MTU and Cable Bandwidth"}
    
    MTUCheck --> RunIperf["Verify cable isn't operating in USB 2.0 fallback mode.<br/>Verify MTU is set to 9000: 'networksetup -getMTU Thunderbolt\\ Bridge'"]
```

---

## 2. Pre-Flight Air-Gap Checklist (Before Disconnecting the Internet)

Before severing internet connectivity or taking the cluster into the field, execute this 5-point verification:

- [ ] **1. Compile Binaries on Both Machines**:
  Verify that `llama-server`, `rpc-server`, and `llama-bench` exist in `llama.cpp/build/bin/` on both the Air and the Pro. Verify with:
  ```bash
  otool -L llama.cpp/build/bin/llama-server | grep -E 'Metal|Accelerate'
  ```
  *(Must show dynamic linkage to Apple Metal framework).*
- [ ] **2. Download and Verify GGUF Models**:
  Verify model file integrity with `shasum -a 256 <model>.gguf`. Ensure the model resides in `~/mac-ai-cluster/models/` on **Node A only**.
- [ ] **3. Pre-Package Offline Python Wheels (If using Exo)**:
  Run while online:
  ```bash
  ./setup/bundle_offline_dependencies.sh download
  ```
  Verify that `.whl` files exist in `offline_wheels/`.
- [ ] **4. Pre-Cache Hugging Face Models (If using Exo)**:
  Run while online:
  ```bash
  ./setup/bundle_offline_dependencies.sh cache-model mlx-community/Qwen2.5-14B-Instruct-4bit
  ```
- [ ] **5. Test Thunderbolt Cable Hardware Negotiation**:
  Plug the cable into both Macs and run on either Mac:
  ```bash
  system_profiler SPThunderboltDataType | grep -A 5 "Link Status"
  ```
  *(Must show `Link Status: 0x2` or `Speed: Up to 40 Gb/s`).*

---

## 3. Exhaustive Troubleshooting & "What If It Doesn't Work?"

### Issue 1: "Thunderbolt Bridge" does not appear in Network Settings
* **Symptom**: `networksetup -listallnetworkservices` does not list `Thunderbolt Bridge`, or the adapter is marked red/inactive.
* **Root Cause**: macOS unloads the Thunderbolt Bridge profile when neither an external display nor a peer Mac is detected during boot.
* **Foolproof Solution**:
  1. Unplug the cable, wait 3 seconds, plug firmly into the left-side Thunderbolt port of both Macs.
  2. Manually initialize the service via terminal:
     ```bash
     sudo networksetup -createnetworkservice "Thunderbolt Bridge" bridge0
     ```
  3. Run `sudo ./setup/01_thunderbolt_network.sh node-a` (or `node-b`).

---

### Issue 2: Ping Fails or Destination Host Unreachable (`192.168.100.2`)
* **Symptom**: `ping 192.168.100.2` returns `Request timeout for icmp_seq 0` or `Host is down`.
* **Root Cause**: IP address collision with an existing local router subnet, or the macOS packet filter is blocking non-Wi-Fi interfaces.
* **Foolproof Solution**:
  1. Flush ARP tables and cycle the virtual bridge interface:
     ```bash
     sudo arp -d -a
     sudo ifconfig bridge0 down
     sudo ifconfig bridge0 up
     ```
  2. Verify that both machines are on the identical subnet:
     * Node A must be `192.168.100.1` netmask `255.255.255.0`
     * Node B must be `192.168.100.2` netmask `255.255.255.0`
  3. Disable macOS Application Firewall:
     * System Settings > Network > Firewall > Toggle OFF (isolated Thunderbolt cables present zero network security risk).

---

### Issue 3: `llama-server` Fails with `GGML_ASSERT(gpu_mem >= required_mem)` or Metal Out-of-Memory
* **Symptom**: Coordinator starts, loads 20 layers, then crashes with an error allocating Metal buffers on the remote RPC worker.
* **Root Cause**: Node B (M2 Pro 8GB) has ~1.5 GB less free memory than expected due to background apps (Discord, Chrome, Slack, WindowServer), causing its allocated layer share to exceed physical VRAM.
* **Foolproof Solution**:
  1. Purge memory on Node B:
     ```bash
     sudo purge
     ```
  2. Run the dynamic memory optimizer to lift the 75% cap to 6.0 GB:
     ```bash
     sudo ./scripts/vram_mode.sh on node-b
     ```
  3. Re-calculate your split and shift 1–2 layers back to Node A:
     ```bash
     # Instead of 13.0,6.0:
     ./scripts/start_coordinator_node_a.sh ~/mac-ai-cluster/models/qwen.gguf 8192 13.5,5.5
     ```
  4. Enable quantized KV cache to slash context memory by 50–75%:
     * Pass `-ctk q8_0 -ctv q8_0` to the launch command.

---

### Issue 4: MacBook Pro Sleeps in Clamshell Mode (Worker Drops Connection)
* **Symptom**: You start the worker on the MacBook Pro, close the lid to use it as a headless server, and Node A immediately loses connection.
* **Root Cause**: macOS requires specific power and display assertions to stay awake with the lid closed.
* **Foolproof Solution**:
  1. The MacBook Pro **must be connected to AC power** (MagSafe or USB-C PD). macOS will never stay awake in clamshell mode on battery.
  2. Enforce sleep prevention flags:
     ```bash
     sudo pmset -a disablesleep 1
     sudo pmset -a sleep 0
     sudo pmset -a tcpkeepalive 1
     ```
  3. If you want permanent clamshell operation without terminal intervention, install the provided LaunchDaemon:
     ```bash
     cp services/com.cluster.rpcworker.plist ~/Library/LaunchAgents/
     launchctl load ~/Library/LaunchAgents/com.cluster.rpcworker.plist
     ```

---

### Issue 5: MacBook Air Thermally Throttles (Performance Drops 50%+)
* **Symptom**: Prompt ingestion starts at 60 tokens/sec, but generation slows from 18 t/s down to 7 t/s after 10 minutes of continuous chat.
* **Root Cause**: The M2 MacBook Air has a fanless passive cooling design. The aluminum chassis can only dissipate ~10–12W passively before reaching 95°C and reducing GPU clocks. The MacBook Pro has an active fan and can sustain 25W indefinitely.
* **Foolproof Solution**:
  1. **Asymmetric Offload**: Give the MacBook Pro (Node B) a slightly higher share of compute layers (e.g. `--tensor-split 12.0,6.0` instead of `13.5,5.5`).
  2. **Physical Elevation**: Lift the bottom chassis of the MacBook Air off the desk using an aluminum stand. Even 1 inch of bottom airflow reduces temperatures by 8–12°C.
  3. **Thread Clamping**: Keep CPU threads set to `-t 4` (Performance cores only). Spilling onto efficiency cores generates excess heat with near-zero inference speedup.

---

### Issue 6: `llama.cpp` Rejects `--rpc` Flag with "unrecognized option"
* **Symptom**: Executing `llama-server --rpc 192.168.100.2:50052` prints `unknown argument: --rpc`.
* **Root Cause**: `llama.cpp` was compiled with standard flags without enabling the RPC backend.
* **Foolproof Solution**:
  Recompile using our turnkey build script:
  ```bash
  cd ~/mac-ai-cluster
  ./setup/02_build_llamacpp.sh
  ```
  *(This explicitly enforces `-DGGML_RPC=ON -DGGML_METAL=ON`).*

---

### Issue 7: Exo Fails Offline with `huggingface_hub` Connectivity Errors
* **Symptom**: Running `exo` while offline prints:
  `requests.exceptions.ConnectionError: Could not reach huggingface.co`.
* **Root Cause**: Exo attempts to query the Hugging Face repository API to verify tokenizer files and metadata.
* **Foolproof Solution**:
  1. Enforce strict offline environment variables:
     ```bash
     export HF_HUB_OFFLINE=1
     export TRANSFORMERS_OFFLINE=1
     export HF_DATASETS_OFFLINE=1
     ```
  2. Pre-cache the exact model while online using:
     ```bash
     ./setup/bundle_offline_dependencies.sh cache-model mlx-community/Qwen2.5-14B-Instruct-4bit
     ```

---

### Issue 8: Ethernet Fallback Packet Drops / Slow Speed
* **Symptom**: Connecting via USB-C Ethernet adapters results in stuttering responses or `Connection reset by peer`.
* **Root Cause**: MTU mismatch. Node A is set to MTU 9000 (Jumbo Frames), while the USB adapter on Node B only supports MTU 1500, causing packet fragmentation and drops.
* **Foolproof Solution**:
  Synchronize MTU to 1500 across both Ethernet adapters:
  ```bash
  # On Node A:
  sudo networksetup -setMTU "USB 10/100/1000 LAN" 1500
  # On Node B:
  sudo networksetup -setMTU "USB 10/100/1000 LAN" 1500
  ```

---

## 4. Offline Integration Guide: Connecting Frontends

Because the coordinator serves an OpenAI-compatible REST API at `http://192.168.100.1:8080/v1` (or `http://localhost:8080/v1` on Node A), you can connect any offline UI:

### 4.1 OpenWebUI (Docker or Native)
1. In OpenWebUI Settings > Connections:
   * **OpenAI API Base URL**: `http://192.168.100.1:8080/v1`
   * **API Key**: `sk-no-key-required`
2. Save connection. All loaded cluster models appear immediately in the model dropdown.

### 4.2 Obsidian Smart Connections / DeepSeek Journal
In Obsidian's local AI plugin settings:
* **Custom API URL**: `http://192.168.100.1:8080/v1/chat/completions`
* **Model Name**: Enter the exact filename of your GGUF (e.g. `qwen2.5-14b-instruct-q4_k_m.gguf`).

### 4.3 VS Code / Continue.dev (Offline Coding Copilot)
In `~/.continue/config.json`:
```json
{
  "models": [
    {
      "title": "M2 Mac Cluster (Qwen 14B Coder)",
      "provider": "openai",
      "model": "qwen2.5-coder-14b-instruct",
      "apiBase": "http://192.168.100.1:8080/v1"
    }
  ]
}
```

### 4.4 eLlama Native Desktop Integration
You can use the local **eLlama** native desktop application (from `C:\Users\T450\Utilities\eLlama`) on macOS:
1. Open eLlama on macOS.
2. In Settings > Backend, point eLlama to use `llama-server`.
3. In Advanced Arguments, add `--rpc 192.168.100.2:50052 --tensor-split 13.0,6.0`.
4. Launch any GGUF model directly with native macOS UI controls!

---

## 5. Frequently Asked Questions (FAQ)

#### Q1: Can I connect an M1 or M3/M4 Mac to this M2 cluster?
**Yes.** `llama.cpp` RPC and `exo` are completely architecture-heterogeneous. You can pool an M1 MacBook Air (8 GB) with an M4 Max (64 GB). The `--tensor-split` parameter simply divides the layer tensors proportionally according to each node's available memory.

#### Q2: Why does the model file only need to be stored on the MacBook Air?
`llama.cpp` RPC implements remote tensor execution, not remote file serving. Node A loads the entire GGUF file from its local SSD into memory, partitions the computation graph, and transfers Node B's layers across the 40 Gbps Thunderbolt connection during the initial 3-second startup phase. Node B does not require local disk space for the weights.

#### Q3: What happens if the Thunderbolt cable is accidentally unplugged during generation?
`llama-server` on Node A will encounter a broken TCP pipe error on port 50052 and abort the current generation. It will **not** corrupt your model file or damage your macOS system. Once re-plugged, simply re-run `start_worker_node_b.sh` and restart the coordinator.

#### Q4: Why can't I use Wi-Fi instead of Thunderbolt?
Wi-Fi 6 latency hovers between 8 ms and 25 ms with high jitter. Because autoregressive token generation requires an inter-node network round-trip for *every single token generated*, a 15 ms network penalty per token caps generation speed at roughly 1–2 tokens per second regardless of how fast the M2 GPUs are. Thunderbolt's < 0.15 ms latency maintains full native GPU generation speeds (> 18–25 tokens/sec).

#### Q5: Can I run this cluster entirely on battery power in a park or airplane?
**Yes.** Both the M2 Air and M2 Pro are laptops. With a direct Thunderbolt 3/4 cable connected between them, the link establishes peer-to-peer with zero router, modem, or internet required. *Note: Battery life will be approximately 2–3.5 hours under continuous heavy inference.*

#### Q6: Does closing the terminal window on Node B stop the worker?
If running interactively via `./scripts/start_worker_node_b.sh`, closing the window terminates the process and triggers the auto-cleanup trap. If you install the LaunchAgent [`com.cluster.rpcworker.plist`](file:///C:/Users/T450/.gemini/antigravity/scratch/mac-ai-cluster/services/com.cluster.rpcworker.plist), Node B runs permanently in the background even if no terminal is open.

#### Q7: How do I change the model without restarting the worker on Node B?
You do **not** need to touch Node B! The worker is a stateless compute engine. To change models, simply terminate `start_coordinator_node_a.sh` on Node A (`Ctrl+C`) and re-run pointing to a different GGUF model:
```bash
./scripts/start_coordinator_node_a.sh ~/mac-ai-cluster/models/gemma-2-27b-it-q3_k_m.gguf 8192
```
Node A will automatically clear Node B's previous tensors and stream the new model's layers.
