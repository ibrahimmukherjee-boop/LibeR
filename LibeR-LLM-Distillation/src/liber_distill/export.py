from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

from rich.console import Console

from .config import DistillConfig
from .io import write_json_atomic


def _run(command: list[str], console: Console) -> None:
    console.print("[dim]" + " ".join(command) + "[/dim]")
    subprocess.run(command, check=True)


def export_ollama(
    config: DistillConfig,
    llama_cpp_dir: Path,
    console: Console | None = None,
    create_model: bool = True,
) -> Path:
    console = console or Console()
    merged = config.resolve(config.export.merged_dir)
    if not (merged / "config.json").exists():
        raise RuntimeError("Merged model not found. Run `liber-distill merge` first.")
    converter = llama_cpp_dir / "convert_hf_to_gguf.py"
    quantizer_candidates = [
        llama_cpp_dir / "llama-quantize.exe",
        llama_cpp_dir / "build" / "bin" / "Release" / "llama-quantize.exe",
        llama_cpp_dir / "build" / "bin" / "llama-quantize",
        llama_cpp_dir / "llama-quantize",
    ]
    quantizer = next((path for path in quantizer_candidates if path.exists()), None)
    if not converter.exists() or quantizer is None:
        raise FileNotFoundError(
            "llama.cpp converter/quantizer not found. Build llama.cpp and pass its root "
            "with `--llama-cpp-dir`."
        )

    output = config.resolve(config.export.gguf_dir)
    output.mkdir(parents=True, exist_ok=True)
    f16 = output / "liber-pmx-assistant-f16.gguf"
    quantized = output / (f"liber-pmx-assistant-{config.export.gguf_quantization.lower()}.gguf")
    _run(
        [
            sys.executable,
            str(converter),
            str(merged),
            "--outfile",
            str(f16),
            "--outtype",
            "f16",
        ],
        console,
    )
    _run(
        [str(quantizer), str(f16), str(quantized), config.export.gguf_quantization],
        console,
    )
    modelfile = output / "Modelfile"
    modelfile.write_text(
        f'FROM "{quantized.as_posix()}"\n'
        f"PARAMETER num_ctx {config.export.mlc_context_window_size}\n"
        "PARAMETER temperature 0.2\n"
        f'SYSTEM """{config.project.system_prompt}"""\n',
        encoding="utf-8",
    )
    if create_model:
        if shutil.which("ollama") is None:
            raise RuntimeError("Ollama is not on PATH; GGUF and Modelfile were still created.")
        _run(
            [
                "ollama",
                "create",
                config.export.ollama_model_name,
                "-f",
                str(modelfile),
            ],
            console,
        )
    write_json_atomic(
        output / "ollama_export_manifest.json",
        {
            "model_name": config.export.ollama_model_name,
            "gguf": str(quantized),
            "quantization": config.export.gguf_quantization,
            "modelfile": str(modelfile),
        },
    )
    return quantized


def export_mlc(
    config: DistillConfig,
    console: Console | None = None,
    compile_library: bool = True,
) -> Path:
    console = console or Console()
    if shutil.which("mlc_llm") is None:
        raise RuntimeError(
            "mlc_llm is not on PATH. WebGPU export requires an MLC-LLM source build "
            "and the Emscripten/WASM environment."
        )
    merged = config.resolve(config.export.merged_dir)
    if not (merged / "config.json").exists():
        raise RuntimeError("Merged model not found. Run `liber-distill merge` first.")
    output = config.resolve(config.export.mlc_dir)
    output.mkdir(parents=True, exist_ok=True)
    library = output / "liber-pmx-assistant-webgpu.wasm"
    quantization = config.export.mlc_quantization
    _run(
        [
            "mlc_llm",
            "convert_weight",
            str(merged),
            "--quantization",
            quantization,
            "-o",
            str(output),
        ],
        console,
    )
    _run(
        [
            "mlc_llm",
            "gen_config",
            str(merged),
            "--quantization",
            quantization,
            "--context-window-size",
            str(config.export.mlc_context_window_size),
            "--prefill-chunk-size",
            str(config.export.mlc_prefill_chunk_size),
            "-o",
            str(output),
        ],
        console,
    )
    if compile_library:
        _run(
            [
                "mlc_llm",
                "compile",
                str(output / "mlc-chat-config.json"),
                "--device",
                "webgpu",
                "-o",
                str(library),
            ],
            console,
        )
    webllm_entry = {
        "model": output.as_uri(),
        "model_id": "LibeR-PMX-Assistant-q4f16_1-MLC",
        "model_lib": library.as_uri() if compile_library else "<hosted model library URL>",
        "vram_required_MB": 1800,
        "low_resource_required": True,
        "overrides": {
            "context_window_size": config.export.mlc_context_window_size,
            "prefill_chunk_size": config.export.mlc_prefill_chunk_size,
        },
    }
    (output / "webllm-model-record.json").write_text(
        json.dumps(webllm_entry, indent=2) + "\n", encoding="utf-8"
    )
    return output
