from __future__ import annotations

import importlib.metadata
import platform
import shutil
import subprocess
import sys

from rich.console import Console

from .config import DistillConfig
from .io import write_json_atomic
from .ollama import OllamaClient


def _version(package: str) -> str | None:
    try:
        return importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        return None


def _gpu_status() -> dict:
    nvidia_smi = shutil.which("nvidia-smi")
    if not nvidia_smi:
        return {"available": False, "reason": "nvidia-smi not found"}
    command = [
        nvidia_smi,
        "--query-gpu=name,memory.total,driver_version,compute_cap",
        "--format=csv,noheader,nounits",
    ]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=15)
        fields = [part.strip() for part in result.stdout.strip().split(",")]
        return {
            "available": True,
            "name": fields[0] if fields else "",
            "memory_mb": int(fields[1]) if len(fields) > 1 else None,
            "driver": fields[2] if len(fields) > 2 else None,
            "compute_capability": fields[3] if len(fields) > 3 else None,
        }
    except (subprocess.SubprocessError, ValueError) as exc:
        return {"available": False, "reason": str(exc)}


def run_doctor(config: DistillConfig, console: Console | None = None) -> dict:
    console = console or Console()
    python_ok = (3, 11) <= sys.version_info[:2] <= (3, 12)
    report = {
        "platform": platform.platform(),
        "python": platform.python_version(),
        "python_supported": python_ok,
        "gpu": _gpu_status(),
        "disk_free_gb": round(shutil.disk_usage(config.project_root).free / 1024**3, 1),
        "executables": {
            name: shutil.which(name) for name in ("ollama", "git", "mlc_llm", "nvidia-smi")
        },
        "packages": {
            name: _version(name)
            for name in (
                "httpx",
                "pydantic",
                "torch",
                "transformers",
                "datasets",
                "peft",
                "trl",
                "bitsandbytes",
            )
        },
    }
    try:
        models = OllamaClient(
            config.generation.base_url, timeout_seconds=10, max_retries=0
        ).list_models()
        report["ollama"] = {
            "available": True,
            "models": models,
            "teacher_available": config.generation.teacher_model in models,
            "judge_available": config.generation.judge_model in models,
        }
    except Exception as exc:
        report["ollama"] = {"available": False, "reason": str(exc)}

    training_installed = all(
        report["packages"][name]
        for name in ("torch", "transformers", "datasets", "peft", "trl", "bitsandbytes")
    )
    report["ready_for_dataset_generation"] = (
        python_ok
        and report["ollama"].get("available", False)
        and report["ollama"].get("teacher_available", False)
        and report["ollama"].get("judge_available", False)
    )
    report["ready_for_training"] = (
        python_ok and report["gpu"].get("available", False) and training_installed
    )
    write_json_atomic(config.resolve(config.paths.work_dir) / "doctor_report.json", report)

    for key in ("python_supported", "ready_for_dataset_generation", "ready_for_training"):
        value = report[key]
        console.print(f"{'[green]PASS[/green]' if value else '[yellow]NOT READY[/yellow]'} {key}")
    console.print(report)
    return report
