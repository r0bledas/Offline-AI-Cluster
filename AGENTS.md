# AI Agent Guidelines & Architecture Manual for Offline-AI-Cluster

> [!IMPORTANT]
> This repository is strictly dedicated to **100% offline, air-gapped, zero-cloud distributed AI inference and local RAG**. Any proposed change that introduces external cloud dependencies, telemetry, or remote API requirements violates the core design principles of this project.

---

## 1. Core Architectural Invariants

Every AI agent, automated tool, or human contributor modifying this codebase must adhere to the following non-negotiable rules:

1. **Zero External Network Dependencies**:
   - The cluster must function entirely without an internet connection.
   - All models (LLMs, embedding models, rerankers) are stored and executed locally in GGUF format via `llama.cpp` or GGML backends.
   - No external vector SaaS (Pinecone, Weaviate Cloud, Milvus Cloud). Use local in-memory or SQLite vector storage.
2. **Cross-Platform Parity**:
   - Code, scripts, and documentation must maintain equal first-class support across:
     - **macOS** (Apple Silicon Metal & Intel)
     - **Windows** (MSVC, w64devkit, and WSL2)
     - **Linux** (Debian, Arch, Fedora, openSUSE, Alpine)
     - **Embedded / Edge** (ARM64 SBCs, Raspberry Pi, Nintendo Switch / LlamaNX)
3. **Zero-Bloat / Standard Library Preference**:
   - For tooling in `scripts/`, prefer the Python 3 standard library (`urllib.request`, `http.server`, `socket`, `sqlite3`, `json`, `math`, `argparse`) over heavy third-party packages (`langchain`, `transformers`, `torch`, `chromadb`).
   - If an external library is truly required, it must be strictly optional with a clean standard-library fallback.
4. **Memory Chunking & Heap Safety**:
   - Never assume infinite contiguous heap space. On embedded devices or customized kernels, single large allocations can fail due to virtual memory fragmentation. Always respect non-contiguous buffer chunking ($\le 512\text{ MB}$ chunks).
5. **Fail-Safe & Circuit Breaking**:
   - Distributed nodes will sleep, lose battery, or drop Wi-Fi packets. Every network call between the Orchestrator, Gateway, and Worker nodes must incorporate explicit timeouts, retry limits, and graceful failover logic.

---

## 2. Code & Style Standards for Agents

To maintain clean Git diffs and ensure maximum cross-platform compatibility:

- **Character Set**:
  - Use standard ASCII characters in code and comments.
  - Avoid unicode punctuation: use `-` instead of em-dash (`—`), `->` instead of unicode arrows (`→`), and `x` instead of multiplication symbols (`×`).
- **Comments & Documentation**:
  - Keep inline code comments brief (1–2 lines), explaining *why* an architectural choice was made, not *what* the syntax does.
  - Avoid redundant boilerplate comments before writing code.
- **Paths & Portability**:
  - Always use `os.path.join()` or forward slashes for filesystem paths so scripts run seamlessly across POSIX and Windows.
  - Respect newline standards: Git handles CRLF/LF translation, but scripts should read files with universal newline handling (`replace('\r\n', '\n')` or `newline=None`).

---

## 3. Component Architecture & Agent Playbook

### Component 1: Cluster Gateway (`scripts/gateway.py`)
- **Role**: Multi-threaded reverse proxy exposing a standard OpenAI-compatible API (`/v1/chat/completions`) on port `8000`.
- **Invariants**:
  - Never block indefinitely on an uncommunicative node. All socket calls to upstream workers must enforce `timeout=1.5` for health checks and reasonable timeouts for generation.
  - Support preflight CORS (`OPTIONS`) with `Access-Control-Allow-Origin: *` to allow local web dashboards to connect without browser security errors.
  - When modifying `gateway.py`, test both healthy proxying and mid-stream node disconnect failover.

### Component 2: Offline RAG Pipeline (`scripts/rag_engine.py`)
- **Role**: Air-gapped document ingestion, recursive chunking, embedding generation, vector indexing, and prompt augmentation.
- **Invariants**:
  - Support standard llama.cpp embedding endpoints (`/v1/embeddings` on port `8081`).
  - Always maintain a deterministic local fallback (e.g. hash-based term vectorizer) so RAG testing functions even if the embedding model server is temporarily stopped.
  - Strict grounding: The generated prompt must instruct the model to answer *only* from the retrieved local context, explicitly rejecting hallucinations when facts are missing.

### Component 3: Configuration (`config/cluster.json`)
- **Role**: Defines cluster nodes, IP addresses, ports, priority tiers, and tensor weights.
- **Invariants**:
  - Must remain strictly generic and template-based (e.g. `GPU-Compute-Node`, `High-Memory-CPU-Node`, `Edge-Embedded-Node`).
  - Do not introduce personal hardware identifiers, usernames, or private internal credentials.

---

## 4. Verification & Testing Checklist for Agents

Before completing any task or committing changes:

1. **Syntax & Import Validation**:
   - Run `python -m py_compile scripts/gateway.py scripts/rag_engine.py examples/query_cluster.py` to ensure clean syntax across all Python scripts.
2. **RAG Pipeline Test**:
   - Ingest sample document:
     ```bash
     python scripts/rag_engine.py ingest --file examples/ingest_sample.txt
     ```
   - Query index and verify top-$k$ similarity hits:
     ```bash
     python scripts/rag_engine.py query "Which node processes tail layers?"
     ```
3. **Gateway Health Test**:
   - Verify status endpoint formatting:
     ```bash
     python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/cluster/status').read().decode())"
     ```
4. **Git Discipline**:
   - Ensure changes are atomic, well-described, and do not commit temporary artifacts or cache directories (`__pycache__`, `data/vector_store.json`).
