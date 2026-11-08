# Offline AI Cluster — Redistribution & Portability Dependencies

This folder contains pre-packaged runtimes and libraries needed to run the **Offline AI Cluster** on a fresh, out-of-the-box Windows install with **zero internet connection** and **no admin rights required**.

---

## Files Included

| File | Purpose | Size | Where to Place / Install |
| :--- | :--- | :--- | :--- |
| `VC_redist.x64.exe` | Microsoft Visual C++ 2015–2022 Redistributable Installer | ~24.4 MB | **Option A (System-Wide Install):** Double-click and install (or run `VC_redist.x64.exe /passive /norestart`). Requires admin. |
| `msvcp140.dll` | C++ Standard Library Runtime | 540 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `msvcp140_1.dll` | C++ Standard Library Concurrency Runtime | 34 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `msvcp140_2.dll` | C++ Standard Library Parallel Algorithms | 272 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `vcruntime140.dll` | Visual C++ Runtime | 120 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `vcruntime140_1.dll` | Visual C++ Exception Handling Runtime | 46 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `vcomp140.dll` | Visual C++ OpenMP Runtime | 208 KB | **Option B (Zero-Admin / Portable):** Copy to `bin/` directory alongside `llama-server.exe`. |
| `node.exe` | Portable Node.js v24.x LTS (Single Standalone Binary) | ~89 MB | Copy to `bin/node.exe`. Provides cluster CLI and telemetry bridge with zero installation. |

---

## 1-Click Quick Deploy (Zero-Admin Portable Mode)

If you are on a restricted machine or don't want to run system installers, you can copy all portable dependencies directly into `bin/` with a single command:

```cmd
cd /d D:\Offline-AI-Cluster
copy redist\*.dll bin\
copy redist\node.exe bin\
```

Once copied into `bin/`:
1. `bin\llama-server.exe` and `bin\ggml-rpc-server.exe` will find `vcruntime140.dll` and `msvcp140.dll` in their own folder and run with zero system dependencies.
2. `cluster.cmd` will automatically use `bin\node.exe` if Node.js is not installed on the system PATH.
