#!/usr/bin/env python3
"""
calculate_split.py - Optimal Memory & Tensor-Split Calculator for Dual Mac M2 Cluster
Accounts for macOS base overhead and the sysctl iogpu.wired_limit_mb tuning.
Node A: M2 MacBook Air (16 GB RAM)
Node B: M2 MacBook Pro (8 GB RAM)
"""

import sys
import argparse

def calculate_cluster_budget(
    node_a_total_gb=16.0,
    node_b_total_gb=8.0,
    optimized_vram=True,
    node_a_os_overhead_gb=None,
    node_b_os_overhead_gb=None,
    model_size_gb=9.0,
    context_length=8192,
    kv_cache_type="f16",
    num_layers=48
):
    if optimized_vram:
        # sysctl iogpu.wired_limit_mb applied:
        # Node A: 13,312 MB = ~13.0 GB
        # Node B: 6,144 MB  = ~6.0 GB
        node_a_usable = 13.0 if node_a_os_overhead_gb is None else max(0.0, node_a_total_gb - node_a_os_overhead_gb)
        node_b_usable = 6.0  if node_b_os_overhead_gb is None else max(0.0, node_b_total_gb - node_b_os_overhead_gb)
    else:
        # macOS dynamic default (~75% Metal cap)
        default_a_os = 4.5 if node_a_os_overhead_gb is None else node_a_os_overhead_gb
        default_b_os = 2.8 if node_b_os_overhead_gb is None else node_b_os_overhead_gb
        node_a_usable = max(0.0, node_a_total_gb - default_a_os)
        node_b_usable = max(0.0, node_b_total_gb - default_b_os)

    total_cluster_vram = node_a_usable + node_b_usable

    # KV Cache Estimation
    bytes_per_elem = 2.0 if kv_cache_type == "f16" else (1.0 if kv_cache_type == "q8_0" else 0.5)
    kv_cache_gb = (model_size_gb * 0.04) * (context_length / 2048.0) * (bytes_per_elem / 2.0)
    total_required_memory = model_size_gb + kv_cache_gb

    ratio_a = node_a_usable / total_cluster_vram
    ratio_b = node_b_usable / total_cluster_vram

    layers_node_b = int(round(num_layers * ratio_b))
    layers_node_a = num_layers - layers_node_b

    fits = total_required_memory <= total_cluster_vram
    headroom = total_cluster_vram - total_required_memory

    return {
        "optimized_vram": optimized_vram,
        "node_a_usable": node_a_usable,
        "node_b_usable": node_b_usable,
        "total_cluster_vram": total_cluster_vram,
        "model_size_gb": model_size_gb,
        "context_length": context_length,
        "kv_cache_gb": kv_cache_gb,
        "total_required_memory": total_required_memory,
        "ratio_a": ratio_a,
        "ratio_b": ratio_b,
        "tensor_split_arg": f"{node_a_usable:.1f},{node_b_usable:.1f}",
        "tensor_split_normalized": f"{ratio_a:.2f},{ratio_b:.2f}",
        "layers_node_a": layers_node_a,
        "layers_node_b": layers_node_b,
        "fits": fits,
        "headroom": headroom
    }

def print_report(res):
    print("=" * 65)
    print(" DUAL M2 MAC CLUSTER: MEMORY & TENSOR-SPLIT ANALYSIS")
    mode_str = "OPTIMIZED (sysctl iogpu.wired_limit_mb)" if res['optimized_vram'] else "DEFAULT (Unoptimized ~75% limit)"
    print(f" VRAM Mode                       : {mode_str}")
    print("=" * 65)
    print(f"Node A (M2 Air 16GB) Usable VRAM : {res['node_a_usable']:.2f} GB")
    print(f"Node B (M2 Pro 8GB)  Usable VRAM : {res['node_b_usable']:.2f} GB")
    print(f"Total Available Cluster VRAM     : {res['total_cluster_vram']:.2f} GB")
    print("-" * 65)
    print(f"Model Weights (GGUF)             : {res['model_size_gb']:.2f} GB")
    print(f"Context Window                   : {res['context_length']} tokens")
    print(f"Estimated KV Cache Memory        : {res['kv_cache_gb']:.2f} GB")
    print(f"Total Cluster Memory Required    : {res['total_required_memory']:.2f} GB")
    print(f"Cluster Memory Headroom          : {res['headroom']:+.2f} GB")
    print("-" * 65)

    if res['fits']:
        print("[STATUS: SUCCESS] The model comfortably fits in the cluster VRAM!")
        if res['headroom'] < 1.0:
            print("  [!] Caution: Headroom is under 1 GB. Keep background applications closed.")
    else:
        print("[STATUS: OVERCOMMIT WARNING] Model + context exceeds available cluster VRAM!")
        print(f"  Deficit: {abs(res['headroom']):.2f} GB. Risk of swapping or out-of-memory crash.")
        print("  Suggested fixes: Reduce context window, use Q4_K_M instead of Q8, or set cache-type-k/v to q8_0/q4_0.")

    print("-" * 65)
    print("RECOMMENDED LLAMA.CPP INVOCATION PARAMETERS:")
    print(f"  --tensor-split {res['tensor_split_arg']}")
    print(f"  (or normalized: --tensor-split {res['tensor_split_normalized']})")
    print(f"  Estimated Layer Split: {res['layers_node_a']} layers on Air, {res['layers_node_b']} layers on Pro")
    print("=" * 65)

def main():
    parser = argparse.ArgumentParser(description="Calculate memory and split for dual Mac cluster.")
    parser.add_argument("--model-gb", type=float, default=9.0, help="GGUF model file size in GB (e.g. 9.0 for 14B Q4_K_M)")
    parser.add_argument("--ctx", type=int, default=8192, help="Context length in tokens (default: 8192)")
    parser.add_argument("--layers", type=int, default=48, help="Total model layers (default: 48)")
    parser.add_argument("--kv-type", choices=["f16", "q8_0", "q4_0"], default="f16", help="KV cache quantization")
    parser.add_argument("--unoptimized", action="store_true", help="Use unoptimized default macOS 75% limits instead of iogpu.wired_limit_mb")
    parser.add_argument("--air-os", type=float, default=None, help="Custom OS overhead on Air 16GB (in GB)")
    parser.add_argument("--pro-os", type=float, default=None, help="Custom OS overhead on Pro 8GB (in GB)")

    args = parser.parse_args()
    res = calculate_cluster_budget(
        model_size_gb=args.model_gb,
        context_length=args.ctx,
        kv_cache_type=args.kv_type,
        num_layers=args.layers,
        optimized_vram=not args.unoptimized,
        node_a_os_overhead_gb=args.air_os,
        node_b_os_overhead_gb=args.pro_os
    )
    print_report(res)

if __name__ == "__main__":
    main()
