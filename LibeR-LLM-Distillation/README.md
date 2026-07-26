# LibeR LLM Distillation

This is a standalone, reproducible workspace for teaching a compact Qwen model
the pharmacometrics and LibeR-specific knowledge needed by the LibeR assistant.
It is **not an R package and is not linked to LibeR at runtime**. Only a model
that has passed the configured evaluation gates is intended to be consumed by
LibeRation later.

The default setup uses the locally installed `qwen3.6:27b` Ollama model as the
teacher, `qwen3.5:9b` as an independent judge, and `Qwen/Qwen3-1.7B` as the
student. Every model is configurable. The pipeline performs **response
distillation**: Ollama supplies generated answers, not teacher logits.

Structured generation defaults to `think: false`: some Qwen/Ollama builds put
reasoning in a separate field and can spend the full output budget before
writing the required JSON. Reasoning mode can be enabled in a local overlay for
selected passes when `num_predict` and the timeout are increased accordingly.
`configs/teacher-deliberative.yaml` provides such an opt-in profile; benchmark
its acceptance-rate gain before paying the substantial runtime cost.

## What the pipeline protects

- Every example is derived from a source with an explicit rights basis.
- Source files, chunks, answers and model settings are hashed and recorded.
- Teacher answers require exact evidence spans and a separate adjudication pass.
- Personal data, local paths, low-groundedness answers and near-duplicates are
  rejected.
- Entire documents—not random question rows—are assigned to only one data split,
  reducing evaluation leakage.
- A tuned model is compared with its untouched base model before export.
- Interrupted generation is resumable at the chunk and example level.

Do not add ChatGPT/Codex responses to this dataset. Use material you own, material
with an appropriate licence, public-domain material, or material for which you
have permission. Verify the licence and acceptable-use terms for every teacher
and student model as well.

## Local setup

Python 3.12 is already installed on this machine. The setup deliberately avoids
Python 3.14 because the GPU training ecosystem is not yet a reliable target for
it.

```powershell
cd C:\Users\svdijkman.DESKTOP-4OG10M4\Documents\LibeR\LibeR-LLM-Distillation
.\scripts\setup_windows.ps1
.\.venv\Scripts\Activate.ps1
liber-distill doctor
```

The first command installs only the small generation/test environment. Add the
training stack when ready:

```powershell
.\scripts\setup_windows.ps1 -Training
```

This selects the PyTorch CUDA 12.8 wheel, which is appropriate for the RTX 5060
generation. `bitsandbytes` provides Windows CUDA 12.8 builds with `sm120`
support. If the native Windows stack proves unstable, run the same project under
WSL2 or Linux; dataset generation can remain on Windows because it talks to
Ollama over HTTP.

## Configure sources and models

1. Review [`manifests/sources.yaml`](manifests/sources.yaml). Each source must
   declare its licence, rights basis and redistribution status.
2. Run `liber-distill init-local-config` and edit the ignored
   `configs/local.yaml`, or pass one or more smaller YAML overlays.
3. Confirm that the configured teacher and judge exist in `ollama list`.

The supplied [`configs/hardware/rtx5060-8gb.yaml`](configs/hardware/rtx5060-8gb.yaml)
is an optional overlay:

```powershell
liber-distill --overlay configs/hardware/rtx5060-8gb.yaml doctor
```

The default curriculum concentrates on LibeRation and LibeRtAD. Add
`--overlay configs/ecosystem-sources.yaml` to use the rights-audited
documentation and code from all six LibeR packages.

`Qwen/Qwen3-1.7B` is the balanced default student. The
`configs/student-qwen25-coder-1.5b.yaml` overlay selects a more code-oriented
Qwen2.5 student whose architecture follows WebLLM's established Qwen2 family.
Keep both as benchmark candidates until browser compilation, quality and memory
tests identify the better release model.

## Build the training data

Run each auditable stage separately:

```powershell
liber-distill ingest
liber-distill generate
liber-distill adjudicate
liber-distill build-dataset
```

Or run them together:

```powershell
liber-distill build-training-data
```

Use `--limit 2` on `generate`, `adjudicate`, or `build-training-data` for an
Ollama smoke run. State and error ledgers are stored under `data/work/`; reruns
skip completed items.

Use `adjudicate --force` after changing judge prompts or enabling preference
training. Decisions remain append-only for auditability; the latest decision for
each item is the one used when the dataset is rebuilt.

## Train and validate

```powershell
liber-distill train-sft
liber-distill evaluate --with-judge
liber-distill merge
```

`merge` refuses to produce a release candidate unless the evaluation summary
passes. `merge --allow-unvalidated` exists only for explicitly labelled
development artefacts.

The 8-GB preset uses 4-bit NF4 QLoRA, a batch size of one, gradient checkpointing
and accumulation. Preference optimisation is intentionally off by default. To
use it, enable `preference_training.enabled`, regenerate the adjudicated dataset,
then run:

```powershell
liber-distill train-dpo
```

`evaluate` runs the untouched base and tuned adapter sequentially, so both do
not occupy VRAM at once. Export is blocked in the documented workflow unless
the tuned model meets term-based, regression and optional teacher-judge gates.

## Export

Ollama/GGUF export requires a built
[llama.cpp](https://github.com/ggml-org/llama.cpp) checkout:

```powershell
liber-distill export-ollama --llama-cpp-dir C:\path\to\llama.cpp
```

WebLLM export uses MLC-LLM and a WASM build environment:

```text
liber-distill export-webllm
```

MLC conversion and WebGPU compilation are kept separate from LibeRation. The
export produces weights, a WebGPU model library and a
`webllm-model-record.json` entry that can be copied into LibeRation only after
validation. See [`docs/EXPORT.md`](docs/EXPORT.md).

## Commands

```text
doctor                 Check Python, Ollama, GPU and optional dependencies
ingest                 Hash, licence-audit and chunk source files
generate               Generate questions and grounded teacher answers
adjudicate             Judge, repair and optionally create preference pairs
build-dataset           Filter, deduplicate and group-split JSONL datasets
build-training-data     Run all data-building stages
train-sft              Train the student with QLoRA SFT
train-dpo              Optional preference optimisation
evaluate               Compare base and tuned models against quality gates
merge                  Merge the final adapter into the student
export-ollama           Build GGUF and an Ollama model
export-webllm           Convert and compile for MLC/WebLLM
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/DATA_GOVERNANCE.md`](docs/DATA_GOVERNANCE.md)
- [`docs/HARDWARE.md`](docs/HARDWARE.md)
- [`docs/TRAINING.md`](docs/TRAINING.md)
- [`docs/EXPORT.md`](docs/EXPORT.md)

The infrastructure code is MIT licensed. Source datasets, model weights,
adapters and generated artefacts retain their own licences and must not be
assumed to inherit the infrastructure licence.
