# Zero-Cloud Offline RAG Architecture
### Complete Design & Engineering Manual for Air-Gapped Retrieval-Augmented Generation

---

## 1. The Offline Imperative: Why Traditional RAG Fails Air-Gapped Systems

Commercial RAG architectures rely on cloud dependencies:
- **Cloud Embedding APIs**: OpenAI `text-embedding-3`, Cohere Embed.
- **Hosted Vector Databases**: Pinecone, Milvus Cloud, Weaviate Cloud.
- **Web Crawlers**: Firecrawl, Tavily.

In an air-gapped or localized environment, any external API call breaks the perimeter. Furthermore, commercial vector databases introduce gigabytes of Docker dependencies, Java runtimes, or network overhead that overtax consumer hardware like ThinkPads or Nintendo Switches.

```
   TRADITIONAL CLUSTER (Fragile, Cloud-Tethered):
   Local Machine ===[ Internet ]===> OpenAI Embeddings ===[ Internet ]===> Pinecone VDB
   
   OFFLINE-AI-CLUSTER (100% Air-Gapped, Local Hardware):
   Local Document ---> Local GGUF Embedder ---> In-Memory Cosine/SQLite Index ---> Cluster
```

---

## 2. Local Embedding Models & Hardware Sizing

For offline RAG, the embedding model must run locally on one of your machines (e.g., MacBook Pro M2 or ThinkPad T450).

### Recommended GGUF Embedding Models:
| Model Name | Embedding Dimensions | Context Window | GGUF Size | RAM Footprint | Best Hardware Placement |
|---|---|---|---|---|---|
| **`bge-small-en-v1.5`** | **384** | 512 tokens | ~67 MB (Q8) | **~120 MB** | ThinkPad T470 / Switch / M2 Mac |
| **`all-MiniLM-L6-v2`** | **384** | 256 tokens | ~45 MB (Q8) | **~90 MB** | Ultra-lightweight edge nodes |
| **`nomic-embed-text-v1.5`**| **768** | **8,192 tokens** | ~270 MB (Q8) | **~450 MB** | ThinkPad T450 / MacBook Air M2 |
| **`bge-base-en-v1.5`** | **768** | 512 tokens | ~218 MB (Q8) | **~380 MB** | MacBook Pro M2 (Metal) |

### Running the Local Embedding Service:
Using `llama.cpp`'s native embedding server:
```bash
# Start on ThinkPad T450 or MacBook Pro (port 8081)
./llama-server -m models/bge-small-en-v1.5-q8_0.gguf --port 8081 --embeddings -c 2048
```
This exposes the standard `/v1/embeddings` endpoint locally without sending a single byte across the internet.

---

## 3. Mathematical Foundations of Offline Vector Retrieval

### 1. Cosine Similarity Formula
Given a query vector $\vec{q} \in \mathbb{R}^d$ and a stored document chunk vector $\vec{d}_i \in \mathbb{R}^d$:

$$\text{Cosine Similarity}(\vec{q}, \vec{d}_i) = \frac{\vec{q} \cdot \vec{d}_i}{\|\vec{q}\|_2 \|\vec{d}_i\|_2} = \frac{\sum_{k=1}^{d} q_k d_{i,k}}{\sqrt{\sum_{k=1}^{d} q_k^2} \sqrt{\sum_{k=1}^{d} d_{i,k}^2}}$$

When vectors are normalized during indexing ($\|\vec{v}\|_2 = 1$), the cosine similarity reduces directly to the dot product $\vec{q} \cdot \vec{d}_i$, requiring only $d$ multiply-accumulate operations per chunk. On modern AVX2 x86 and ARM NEON hardware, scoring 10,000 chunks takes under $2\text{ ms}$.

### 2. Reciprocal Rank Fusion (RRF) for Hybrid Retrieval
Pure vector similarity can miss exact serial numbers, hexadecimal registers, or code identifiers. The hybrid search algorithm fuses dense vector ranks and sparse BM25 ranks:

$$RRF\_Score(d) = \sum_{m \in \{\text{Dense}, \text{BM25}\}} \frac{1}{k + \text{Rank}_m(d)}$$

Where $k \approx 60$.

---

## 4. Context Window Allocation & Budgeting

In distributed clusters operating with a 4,096-token context limit, memory must be partitioned strictly:

```text
┌────────────────────────────────────────────────────────────────────────┐
│ TOTAL CONTEXT WINDOW: 4,096 TOKENS                                     │
├───────────────────┬───────────────────┬────────────────────────────────┤
│ System Prompt     │ Retrieved RAG     │ Generation Headroom            │
│ & User Query      │ Chunks (Top-3)    │ (Assistant Response)           │
│ ~512 Tokens (12%) │ ~1,536 Tokens(38%)│ ~2,048 Tokens (50%)            │
└───────────────────┴───────────────────┴────────────────────────────────┘
```

1. **System Prompt (128 Tokens)**: Strict grounding instructions ("Answer using only the provided context. If unknown, say so.").
2. **User Query (128–384 Tokens)**: The user's prompt or multi-turn chat history.
3. **Retrieved Context (3 Chunks $\times$ 512 Tokens = 1,536 Tokens)**: The top-3 highest-scoring factual passages.
4. **Generation Space (2,048 Tokens)**: Full headroom for code generation, summaries, or analytical breakdowns.

---

## 5. Ingestion & Document Pipeline

The local ingestion pipeline (`scripts/rag_engine.py`) performs 4 stages:

1. **Extraction**:
   - Plaintext, Markdown, Source Code (.c, .cpp, .py, .rs, .json, .csv).
   - Extracts semantic sections without stripping indentation or code blocks.
2. **Recursive Sliding Chunking**:
   - Window size: 512 words / tokens.
   - Overlap: 64 words to preserve cross-boundary semantics.
3. **Local Vectorization**:
   - Dispatches chunk batches to `http://localhost:8081/v1/embeddings`.
4. **Persistent JSON / SQLite Storage**:
   - Stored in `data/vector_store.json` (portable across macOS, Windows, Linux, and Switch).

---

## 6. Verification & Anti-Hallucination Guardrails

To prevent the LLM from hallucinating facts not present in your offline documents:

1. **Citation Injection**:
   Every retrieved chunk is tagged with its source file:
   ```text
   --- Document Source: manual_v2.pdf (Relevance Score: 0.892) ---
   [Extracted text content]
   ```
2. **Strict System Prompt Framing**:
   ```text
   You are an offline assistant operating within an air-gapped system.
   You must answer using ONLY the verified facts contained in the [VERIFIED LOCAL CONTEXT] below.
   Never extrapolate or hypothesize beyond what is stated in the context.
   If the answer cannot be determined from the context, respond:
   "The requested information is not documented in the local offline knowledge base."
   ```
