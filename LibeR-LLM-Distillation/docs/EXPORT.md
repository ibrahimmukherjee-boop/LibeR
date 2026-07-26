# Export

## Hugging Face model directory

`liber-distill merge` combines the final PEFT adapter with the base Qwen weights
and writes a self-contained Transformers directory plus
`liber_export_manifest.json`. The base model licence continues to apply.

## Ollama

`liber-distill export-ollama --llama-cpp-dir ...`:

1. converts the merged Transformers model to F16 GGUF;
2. quantises it to the configured `Q4_K_M`;
3. writes an Ollama `Modelfile`;
4. optionally calls `ollama create`.

Use `--no-create` to produce artefacts without modifying the local Ollama model
registry.

## MLC/WebLLM

`liber-distill export-webllm` follows MLC’s three-stage model process:

1. `mlc_llm convert_weight` creates `q4f16_1` model weights;
2. `mlc_llm gen_config` writes tokeniser/config assets with the configured
   context and prefill limits;
3. `mlc_llm compile --device webgpu` creates the WASM model library.

WebGPU compilation requires an MLC-LLM source build and Emscripten/WASM
environment. `--weights-only` performs conversion/configuration without the
model-library build.

The generated `webllm-model-record.json` is a staging record, not a deployed
URL. Host the weights and WASM with correct CORS/cache headers, replace local
URIs with immutable HTTPS URLs, then run LibeRation browser stress tests before
changing its model catalogue. The user’s browser downloads the resulting model
once and may cache it according to browser storage policy.
