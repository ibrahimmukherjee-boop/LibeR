# Hardware profile

The local system has an NVIDIA RTX 5060 with approximately 8 GB VRAM. The
default student, `Qwen/Qwen3-1.7B`, is deliberately small enough for 4-bit QLoRA
with a 2,048-token training sequence on this device.

## Local division of labour

- **Teacher and judge:** Ollama inference. Only one large model needs to be
  resident at a time; the client uses a 15-minute keep-alive to avoid needless
  reloads.
- **Student:** PyTorch + PEFT + TRL + bitsandbytes, using NF4 double
  quantisation, BF16 compute, gradient checkpointing and accumulation.
- **Evaluation:** base and adapter models are loaded sequentially to avoid
  doubling VRAM use.
- **Web export:** MLC compilation is a separate build task. It does not run
  during dataset generation or training.

## Expected constraints

The 27B teacher is much larger than VRAM, so Ollama may split work between GPU
and system memory. That affects speed but not the student training design.
Teacher generation should be run as a resumable overnight batch.

If student training runs out of memory, reduce these settings in order:

1. `training.max_sequence_length` from 2048 to 1536 or 1024;
2. `training.lora_rank` from 32 to 16;
3. disable evaluation during training and run it afterward;
4. use `Qwen/Qwen3-0.6B` for a smoke model.

Do not increase the per-device batch size on an 8-GB card before measuring peak
memory. Increase `gradient_accumulation_steps` to preserve the effective batch.

## Platform

The project supports generation and tests on Windows. Current bitsandbytes
wheels cover Windows CUDA 12.8 and the RTX 50 compute target. WSL2/Linux remains
the fallback if a particular PyTorch, Triton or MLC build is unstable on native
Windows. WebGPU model-library compilation normally requires building MLC-LLM
from source with the WASM environment.
