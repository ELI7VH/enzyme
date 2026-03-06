# NZYM Model Training Pipeline

> Train a small LLM to grok YOUR codebase using NZYM digests. Runs on Apple Silicon or consumer GPUs.

**Status: Aspirational.** This document describes a planned training pipeline that has not been tested in production. The architecture is sound and the tooling exists, but no fine-tuned NZYM models have been produced yet. Treat this as a roadmap, not a recipe.

## Architecture

```
                NZYM CLI                    Training Pipeline
                --------                    -----------------
~/repos/* ──→ .enzyme digests ──→ QA pair generation ──→ LoRA fine-tune
                                                              │
                                                              ▼
                                                      GGUF export
                                                              │
                                                              ▼
                                                    LM Studio / Ollama
                                                              │
                                                              ▼
                                          Claude Code / GroundControl
```

## Step 1: Generate Training Data from Digests

NZYM digests are the training corpus. Each `.enzyme` file becomes training samples.

### QA Pair Generation

For each `.enzyme` digest, generate question-answer pairs:

```python
# nzym-training/generate_qa.py
import json, glob, os

def generate_qa_pairs(enzyme_path):
    """Generate training QA pairs from a .enzyme digest."""
    with open(enzyme_path) as f:
        digest = f.read()

    folder = os.path.basename(os.path.dirname(enzyme_path))

    # Template questions per digest
    pairs = [
        {
            "messages": [
                {"role": "system", "content": "You are a code analyst. Answer questions about codebases using NZYM digests."},
                {"role": "user", "content": f"Here is a NZYM digest:\n\n{digest}\n\nWhat is this project/folder about?"},
                {"role": "assistant", "content": ""}  # Fill from Claude or manually
            ]
        },
        {
            "messages": [
                {"role": "system", "content": "You are a code analyst. Answer questions about codebases using NZYM digests."},
                {"role": "user", "content": f"Here is a NZYM digest:\n\n{digest}\n\nWhat are the key files and their purposes?"},
                {"role": "assistant", "content": ""}
            ]
        },
        {
            "messages": [
                {"role": "system", "content": "You are a code analyst. Answer questions about codebases using NZYM digests."},
                {"role": "user", "content": f"Here is a NZYM digest:\n\n{digest}\n\nWhat patterns and conventions does this codebase follow?"},
                {"role": "assistant", "content": ""}
            ]
        },
        {
            "messages": [
                {"role": "system", "content": "You are a code analyst. Answer questions about codebases using NZYM digests."},
                {"role": "user", "content": f"Here is a NZYM digest:\n\n{digest}\n\nIf I wanted to add a new feature following the existing patterns, what files would I create and what conventions should I follow?"},
                {"role": "assistant", "content": ""}
            ]
        },
    ]
    return pairs

# Collect all .enzyme files
digests = glob.glob("/Users/elijahlucian/repos/**/.enzyme", recursive=True)
all_pairs = []
for d in digests:
    all_pairs.extend(generate_qa_pairs(d))

# Save as JSONL for fine-tuning
with open("nzym_training_data.jsonl", "w") as f:
    for pair in all_pairs:
        f.write(json.dumps(pair) + "\n")

print(f"Generated {len(all_pairs)} training pairs from {len(digests)} digests")
```

### Bootstrap Answers with Claude

Use Claude to generate gold-standard answers for the training pairs:

```bash
# Use claude CLI to generate answers
for pair in training_pairs:
    # Send digest + question to Claude
    # Capture the response as the training answer
    # This creates a "distillation" dataset: Claude's knowledge → small model
```

## Step 2: Fine-Tune with MLX (Apple Silicon)

```bash
# Install MLX-LM
pip install mlx-lm

# Download base model
mlx_lm.download --model Qwen/Qwen2.5-Coder-1.5B-Instruct

# Fine-tune with LoRA
mlx_lm.lora \
  --model Qwen/Qwen2.5-Coder-1.5B-Instruct \
  --data ./nzym_training_data.jsonl \
  --train \
  --batch-size 2 \
  --lora-layers 8 \
  --iters 200 \
  --learning-rate 1e-5 \
  --adapter-path ./nzym-adapter

# Merge adapter into model
mlx_lm.fuse \
  --model Qwen/Qwen2.5-Coder-1.5B-Instruct \
  --adapter-path ./nzym-adapter \
  --save-path ./nzym-coder-1.5b

# Convert to GGUF for LM Studio
mlx_lm.convert \
  --model ./nzym-coder-1.5b \
  --quantize q4_k_m \
  --output ./nzym-coder-1.5b.gguf
```

## Step 3: Fine-Tune with Unsloth (NVIDIA GPU)

If the Windows machine has an NVIDIA GPU:

```python
from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="Qwen/Qwen2.5-Coder-1.5B-Instruct",
    max_seq_length=4096,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=16,
    lora_dropout=0,
)

# Train with your NZYM QA pairs
from trl import SFTTrainer
trainer = SFTTrainer(
    model=model,
    train_dataset=dataset,
    max_seq_length=4096,
    # ... standard SFT config
)
trainer.train()

# Export to GGUF
model.save_pretrained_gguf("nzym-coder", tokenizer, quantization_method="q4_k_m")
```

## Step 4: Deploy to LM Studio

```bash
# Copy GGUF to LM Studio models directory
cp nzym-coder-1.5b.gguf ~/.lmstudio/models/nzym/

# Or use LM Studio CLI
lms load nzym-coder-1.5b --gpu max
```

The model is now available at `localhost:1234` as any other LM Studio model.

## Step 5: Integrate with GroundControl

GroundControl already has LM Studio auto-bucketing. The NZYM-tuned model becomes a specialized endpoint:

```javascript
// In GroundControl, route NZYM queries to the fine-tuned model
const NZYM_MODEL = "nzym-coder-1.5b";

async function queryNZYM(digest, question) {
  const response = await fetch("http://localhost:1234/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: NZYM_MODEL,
      messages: [
        { role: "system", content: "You are a code analyst trained on this developer's codebase patterns." },
        { role: "user", content: `${digest}\n\n${question}` }
      ],
      temperature: 0.3,
    }),
  });
  return response.json();
}
```

## Recommended Models

| Use Case | Model | Size | RAM (Q4) | Notes |
|----------|-------|------|----------|-------|
| Fine-tune base (M3) | Qwen2.5-Coder-1.5B | 1.5B | ~3GB | Best size/quality for M3 LoRA |
| Fine-tune base (GPU) | Qwen2.5-Coder-3B | 3B | ~5GB | More capacity, needs NVIDIA |
| Inference (compact) | Qwen2.5-Coder-0.5B | 0.5B | ~1GB | Already in LM Studio |
| Inference (quality) | Qwen3-Coder-30B-A3B | 3B active | ~18GB | MoE, fills M3 RAM |
| Embeddings | Nomic CodeRankEmbed | 137M | <1GB | Code-specific similarity search |
| Embeddings (heavy) | Nomic Embed Code 7B | 7B | ~5GB | SOTA code retrieval |

## ESP32 Context Transport

For moving NZYM digests between machines (including from peripheral ESP32 nodes to the GPU workstation):

```
ESP32 node ──WiFi──→ MQTT broker ──→ GroundControl ──→ LM Studio
    │                                      │
    └── generates .enzyme                  └── routes to best model
        for local sensors/config               based on query type
```

The ESP32 doesn't run inference — it generates minimal `.enzyme`-style digests of its own config/state and ships them to the central brain. The central machine (M3 or Windows GPU) runs inference. The ESP32 is a context SOURCE, not a compute node.

## Training Data Iteration Loop

```
1. Run NZYM on all repos → .enzyme digests
2. Generate QA pairs from digests
3. Bootstrap answers with Claude (distillation)
4. Fine-tune small model on QA pairs
5. Test: can the model answer new questions about your codebase?
6. If quality is low → add more QA pairs, increase LoRA rank
7. If quality is good → deploy to LM Studio
8. Periodically regenerate digests and retrain (codebase evolves)
```

The key insight: you're not training the model on raw code. You're training it on NZYM's compressed semantic representation of your code. This means the model learns YOUR patterns, YOUR naming conventions, YOUR architectural decisions — distilled through NZYM's lens.
