# llama.cpp Official Documentation Index

This directory contains the complete official upstream documentation for **`llama.cpp`** (from [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)), bundled locally for 100% offline reference during cluster operation.

---

## Document Catalog

| Document | Primary Topics | Application to Dual-Mac Cluster |
| :--- | :--- | :--- |
| **[`rpc.md`](rpc.md)** | Remote Procedure Call architecture, `rpc-server`, network backends | **Core Cluster Guide**: Explains how tensors and memory are offloaded across TCP/Thunderbolt links. |
| **[`server.md`](server.md)** | `llama-server` endpoints (`/v1/chat/completions`, `/slots`, `/metrics`), parameters, prompt caching | **Coordinator Manual**: Complete reference for all flags passed to `start_coordinator_node_a.sh`. |
| **[`multi-gpu.md`](multi-gpu.md)** | Multi-GPU inference, layer splitting, `--tensor-split`, unified memory offloading | **Memory Tuning**: Reference for splitting layers across heterogeneous VRAM pools (16GB + 8GB). |
| **[`build.md`](build.md)** | CMake compilation, Apple Silicon Metal flags (`-DGGML_METAL=ON`, `-DGGML_RPC=ON`) | **Build Manual**: Reference for compilation on macOS and other operating systems. |
| **[`cli.md`](cli.md)** | `llama-cli` interactive flags, sampling hyperparameters, system prompts | **Terminal Chat**: Guide for running interactive chats directly from the CLI. |
| **[`llama-bench.md`](llama-bench.md)** | Microbenchmarking prompt processing (`pp512`) and generation (`tg128`) | **Benchmark Reference**: Used by `scripts/cluster_benchmark.sh` to measure inter-node throughput. |
| **[`quantize.md`](quantize.md)** | GGUF quantization formats (`Q4_K_M`, `Q8_0`, `IQ4_XS`, etc.) and perplexity benchmarks | **Model Selection**: Guides choosing the right quantization for the cluster's 19.0 GB VRAM limit. |
| **[`performance_tips.md`](performance_tips.md)** | CPU thread pinning, Flash Attention (`-fa`), batch sizes (`-b`, `-ub`), KV cache quantization | **Optimization**: Explains how to maximize tokens/second on Apple Silicon. |
| **[`function-calling.md`](function-calling.md)** | JSON schema parsing, grammar constraints, tools integration | **Agentic Workflows**: How to execute tool calling through the local OpenAI endpoint. |
| **[`speculative.md`](speculative.md)** | Speculative decoding with draft models | **Latency Acceleration**: How to run a draft model alongside the main model. |
| **[`gguf-split.md`](gguf-split.md)** | Splitting giant multi-gigabyte models across files | **File Sharding**: Techniques for handling models larger than FAT32/exFAT limits. |
| **[`README.md`](README.md)** | Main llama.cpp overview and feature summary | **Overview**: Master project overview from upstream. |
