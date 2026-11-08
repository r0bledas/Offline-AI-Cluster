# Offline-AI-Cluster Roadmap
### From Air-Gapped Tensor Sharding to Fault-Tolerant Distributed RAG & Multi-Agent Swarms

---

## Vision Statement
**Offline-AI-Cluster** is a public, open-source framework engineered for environments where **zero data leaves your local network**. Whether deployed in air-gapped secure facilities, mobile field units, private enterprise laboratories, or local homelab networks, this project transforms an arbitrary collection of consumer and workstation hardware into a unified, resilient private AI compute mesh with integrated local knowledge retrieval (RAG).

```
   ┌────────────────────────────────────────────────────────────────────────┐
   │                       Offline-AI-Cluster Core                          │
   │                                                                        │
   │  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────┐  │
   │  │   Heterogeneous      │  │    Zero-Cloud        │  │  Resilient   │  │
   │  │   Tensor Splitting   │  │    Offline RAG       │  │  Failover    │  │
   │  │   (GGML RPC Engine)  │  │    (Local Embeddings)│  │  Gateway     │  │
   │  └──────────────────────┘  └──────────────────────┘  └──────────────┘  │
   └────────────────────────────────────────────────────────────────────────┘
```

---

## Milestone 1: Heterogeneous Tensor Sharding Engine (Core Foundation)
*Goal: Pool disparate CPU, GPU, and ARM64 memory across diverse operating systems into a single virtual address space capable of running 32B–70B parameter models without cloud dependencies.*

- [x] **Cross-Platform RPC Protocol Standardization**:
  - Implement and document GGML RPC protocol v8 across macOS (Metal), Windows (MSVC/w64devkit), Linux (Debian, Arch, Fedora, Alpine, openSUSE), and Embedded Edge systems (ARM64 SBCs / Nintendo Switch).
- [x] **Non-Contiguous Memory Chunking**:
  - Unconditional buffer splitting ($\le 512\text{ MB}$ chunks) to eliminate single-allocation heap ceilings on embedded, low-memory, or customized kernels.
- [x] **Proportional Memory Scheduling**:
  - Dynamic calculation of `--tensor-split` weights based on live node memory reports (`RPC_CMD_GET_DEVICE_MEMORY`).
- [ ] **Automated mDNS / Zero-Config Peer Discovery**:
  - Implement Bonjour / Avahi mDNS daemon so worker nodes broadcasting `_ggml-rpc._tcp.local` are automatically discovered and aggregated by the Orchestrator without manual IP entry.
- [ ] **Dynamic Re-quantization On-the-Fly**:
  - Worker-specific quantization scaling (e.g. accelerated GPU nodes execute Q8/FP16 layers, standard CPU nodes execute Q4_K_M, and edge nodes execute compact IQ2/IQ3 layers).

---

## Milestone 2: Low-Latency Transport & High-Speed Interconnects
*Goal: Overcome local network latency bottlenecks to maximize token throughput across heterogeneous machines.*

- [x] **Local Disk Cache Persistence**:
  - Implement client-side disk caching (`-c` flag) storing hashed layer weights under local caches (`$HOME/.cache/llama.cpp/rpc` or `%LOCALAPPDATA%`) to eliminate redundant multi-gigabyte network transfers on launch.
- [ ] **Dual-Tier Network Bridging (Thunderbolt / RoCEv2 + Ethernet)**:
  - Point-to-point high-speed links (20–40 Gbps, $<0.1\text{ ms}$ latency) between high-performance nodes using RDMA (e.g., Apple RDMA over Thunderbolt via `librdma` TN3205 or Linux RoCEv2 via `libibverbs`).
  - Bridge remaining CPU and edge worker nodes over 1 Gbps / 2.5 Gbps Ethernet or 5 GHz Wi-Fi.
- [ ] **TCP Pipelining & Nagle's Algorithm Bypass**:
  - Enable `TCP_NODELAY` and tune socket buffer depths (`SO_RCVBUF`, `SO_SNDBUF` to $\ge 4\text{ MB}$) across all client sockets to prevent packet stall during activation vector back-propagation.
- [ ] **Async Tensor Streaming**:
  - Overlap compute and transfer (double-buffering) so Node $N+1$ pre-fetches input activations while Node $N$ computes its final attention block.

---

## Milestone 3: Zero-Cloud Local RAG Pipeline (Architecture & Engine)
*Goal: Inject thousands of local documents (PDFs, Markdown, source code, manuals) into generation context using 100% offline embedding and vector similarity search.*

```mermaid
flowchart LR
    Docs["Local Docs (PDF/MD/TXT)"] --> Chunker["Recursive Chunker (512 tokens)"]
    Chunker --> Embedder["Offline Embedder (bge-small GGUF)"]
    Embedder --> VDB[("Local Vector Index (Cosine / SQLite)")]
    
    UserQuery["User Query"] --> EmbedderQuery["Embed Query"]
    EmbedderQuery --> Retriever["Hybrid Retriever (BM25 + Cosine)"]
    VDB --> Retriever
    Retriever --> Context["Top-K Context Chunks"]
    Context --> Orchestrator["Cluster Orchestrator (32B/70B Model)"]
    Orchestrator --> Answer["Verified Response with Citations"]
```

- [x] **Standalone Offline Embedding Engine**:
  - Support for local GGUF embedding models (`bge-small-en-v1.5`, `nomic-embed-text-v1.5`, `all-MiniLM-L6-v2`) running via local llama.cpp instance on port `8081`.
- [x] **Zero-Dependency Vector Store**:
  - Pure Python + NumPy/SQLite cosine similarity index requiring zero cloud API keys, zero Docker daemons, and zero external vector service subscriptions.
- [ ] **Hybrid Search (Lexical BM25 + Dense Semantic)**:
  - Reciprocal Rank Fusion (RRF) combining exact keyword hits (error codes, function names, serial numbers) with dense semantic search.
- [ ] **Local Document Parsing Suite**:
  - Offline parser for `.pdf`, `.docx`, `.md`, `.txt`, `.json`, `.csv`, and code repositories with AST-aware code chunking.
- [ ] **Context-Aware Reranking**:
  - Integrate local cross-encoder reranker model (`bge-reranker-base`) to score top-20 retrieved candidates down to the top-3 highest-relevance passages.

---

## Milestone 4: Fault Tolerance, Circuit Breaking & Self-Healing
*Goal: Ensure the cluster operates continuously ("faillessly") even when laptops sleep, batteries run low, or network packets drop.*

- [x] **Circuit-Breaking Reverse Proxy**:
  - Multi-threaded Python cluster gateway (`scripts/gateway.py`) with active heartbeat polling (`/api/status` & `/health`).
- [x] **Sub-Second Failover**:
  - In-flight request detection: If a worker node disconnects during generation, reroute the query to the highest-priority surviving node in $<500\text{ ms}$.
- [ ] **Graceful Node Eviction & Layer Rebalancing**:
  - Dynamic layer re-allocation: When worker node departure is detected, the Orchestrator recalculates `--tensor-split` without restarting the process.
- [ ] **Power-Aware Load Shedding**:
  - Monitor battery level and thermal throttling on mobile/edge nodes; dynamically offload compute to AC-powered desktop nodes when battery drops below 20%.

---

## Milestone 5: Distributed Multi-Agent Swarm & Physical Consoles
*Goal: Evolve from simple Q&A inference into a cooperative multi-model swarm where each machine executes specialized roles.*

```mermaid
flowchart TD
    Task["Complex User Task"] --> Planner["Coordinator Workstation<br/>Role: Orchestrator & Planner (14B/32B/70B)"]
    
    Planner --> CodeSub["High-Speed GPU Worker<br/>Role: High-Speed Coder (Qwen-Coder / Mistral)"]
    Planner --> RAGSub["Dedicated CPU Host<br/>Role: Vector Search & Embeddings Engine"]
    Planner --> ToolSub["Secondary Host<br/>Role: Sandboxed Tool & Code Execution"]
    Planner --> ConsoleSub["Edge / Console Node<br/>Role: Physical Status Console & Telemetry Monitor"]
    
    CodeSub --> Planner
    RAGSub --> Planner
    ToolSub --> Planner
    ConsoleSub --> Planner
```

- [ ] **Role-Specialized Clustering**:
  - Assign dedicated models to nodes:
    - **Primary Host**: Reasoning & Planning (`Qwen-2.5-14B/32B` or `Llama-3.1-70B`).
    - **GPU Accelerator Node**: Fast Speculative Drafter / Coder (30–60 tokens/sec).
    - **High-Memory CPU Host**: Vector Store & Document Ingestion worker.
    - **Secondary CPU Host**: Headless Tool execution sandbox.
    - **Edge / Console Node**: Physical live dashboard displaying token velocity, cluster RAM graphs, and status telemetry.
- [ ] **Speculative Distributed Decoding**:
  - Use a small local GPU model as the draft model and the cluster-wide pooled model as the verifier, cutting overall generation latency by $2\times$ to $3\times$.

---

## Version History
- **v0.1.0**: Heterogeneous GGML RPC architecture validation across macOS, Windows, Linux, and embedded targets.
- **v0.2.0**: Zero-cloud RAG pipeline prototype (`scripts/rag_engine.py`) and offline gateway (`scripts/gateway.py`).
- **v0.3.0** (Next): mDNS discovery daemon and automatic `--tensor-split` negotiator.
- **v1.0.0**: Production-ready air-gapped distributed swarm with failover and live memory rebalancing.
