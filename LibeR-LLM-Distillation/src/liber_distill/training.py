from __future__ import annotations

import inspect
import json
from pathlib import Path

from rich.console import Console

from .config import DistillConfig
from .io import sha256_file, write_json_atomic


def _require_training_stack() -> dict:
    try:
        import accelerate
        import bitsandbytes
        import datasets
        import peft
        import torch
        import transformers
        import trl
    except ImportError as exc:
        raise RuntimeError(
            "Training dependencies are missing. Install with "
            '`python -m pip install -e ".[train]"` in a Python 3.11 environment.'
        ) from exc
    return {
        "accelerate": accelerate,
        "bitsandbytes": bitsandbytes,
        "datasets": datasets,
        "peft": peft,
        "torch": torch,
        "transformers": transformers,
        "trl": trl,
    }


def _supported_kwargs(callable_object: object, values: dict) -> dict:
    parameters = inspect.signature(callable_object).parameters
    return {key: value for key, value in values.items() if key in parameters}


def _quantization_config(stack: dict, enabled: bool) -> object | None:
    if not enabled:
        return None
    torch = stack["torch"]
    return stack["transformers"].BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.bfloat16,
    )


def train_sft(
    config: DistillConfig,
    console: Console | None = None,
    resume: bool | str = False,
) -> dict:
    console = console or Console()
    stack = _require_training_stack()
    torch = stack["torch"]
    if config.training.load_in_4bit and not torch.cuda.is_available():
        raise RuntimeError("4-bit QLoRA requires a CUDA device; no CUDA device is available.")

    dataset_dir = config.resolve(config.paths.dataset_dir)
    train_path = dataset_dir / "train.jsonl"
    validation_path = dataset_dir / "validation.jsonl"
    if not train_path.exists() or train_path.stat().st_size == 0:
        raise RuntimeError("Training data is empty. Run `liber-distill build-dataset` first.")

    data_files = {"train": str(train_path)}
    if validation_path.exists() and validation_path.stat().st_size:
        data_files["validation"] = str(validation_path)
    dataset = stack["datasets"].load_dataset("json", data_files=data_files)
    output_dir = config.resolve(config.training.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    quantization = _quantization_config(stack, config.training.load_in_4bit)
    dtype = (
        torch.bfloat16
        if config.training.bf16
        else (torch.float16 if config.training.fp16 else torch.float32)
    )
    model_kwargs = {
        "torch_dtype": dtype,
        "device_map": "auto" if torch.cuda.is_available() else None,
        "trust_remote_code": False,
    }
    if quantization is not None:
        model_kwargs["quantization_config"] = quantization
    model = stack["transformers"].AutoModelForCausalLM.from_pretrained(
        config.training.student_model, **model_kwargs
    )
    model.config.use_cache = False
    tokenizer = stack["transformers"].AutoTokenizer.from_pretrained(
        config.training.student_model, trust_remote_code=False
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    lora = stack["peft"].LoraConfig(
        r=config.training.lora_rank,
        lora_alpha=config.training.lora_alpha,
        lora_dropout=config.training.lora_dropout,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=config.training.target_modules,
    )
    sft_values = {
        "output_dir": str(output_dir),
        "num_train_epochs": config.training.epochs,
        "learning_rate": config.training.learning_rate,
        "per_device_train_batch_size": config.training.per_device_train_batch_size,
        "per_device_eval_batch_size": config.training.per_device_eval_batch_size,
        "gradient_accumulation_steps": config.training.gradient_accumulation_steps,
        "gradient_checkpointing": True,
        "warmup_ratio": config.training.warmup_ratio,
        "weight_decay": config.training.weight_decay,
        "logging_steps": config.training.logging_steps,
        "eval_steps": config.training.eval_steps,
        "save_steps": config.training.save_steps,
        "save_total_limit": 3,
        "bf16": config.training.bf16,
        "fp16": config.training.fp16,
        "optim": "paged_adamw_8bit" if config.training.load_in_4bit else "adamw_torch",
        "lr_scheduler_type": "cosine",
        "report_to": "none",
        "seed": config.project.seed,
        "data_seed": config.project.seed,
        "packing": True,
        "assistant_only_loss": True,
        "max_length": config.training.max_sequence_length,
        "max_seq_length": config.training.max_sequence_length,
        "eval_strategy": "steps" if "validation" in dataset else "no",
        "evaluation_strategy": "steps" if "validation" in dataset else "no",
    }
    sft_args = stack["trl"].SFTConfig(**_supported_kwargs(stack["trl"].SFTConfig, sft_values))
    trainer = stack["trl"].SFTTrainer(
        model=model,
        args=sft_args,
        train_dataset=dataset["train"],
        eval_dataset=dataset.get("validation"),
        processing_class=tokenizer,
        peft_config=lora,
    )
    console.print(
        f"[cyan]Training {config.training.student_model} with QLoRA in {output_dir}[/cyan]"
    )
    train_result = trainer.train(resume_from_checkpoint=resume)
    trainer.save_model(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    metrics = dict(train_result.metrics)
    if "validation" in dataset:
        metrics["evaluation"] = trainer.evaluate()
    write_json_atomic(output_dir / "training_metrics.json", metrics)
    console.print(f"[green]SFT complete:[/green] {metrics}")
    return metrics


def train_dpo(
    config: DistillConfig,
    console: Console | None = None,
    resume: bool | str = False,
) -> dict:
    console = console or Console()
    if not config.preference_training.enabled:
        raise RuntimeError(
            "Preference training is disabled. Set preference_training.enabled to true, "
            "then regenerate/adjudicate the dataset to create rejected answers."
        )
    stack = _require_training_stack()
    torch = stack["torch"]
    dataset_dir = config.resolve(config.paths.dataset_dir)
    train_path = dataset_dir / "train_preferences.jsonl"
    validation_path = dataset_dir / "validation_preferences.jsonl"
    if not train_path.exists() or train_path.stat().st_size == 0:
        raise RuntimeError("No preference pairs exist. Re-run adjudication and dataset build.")
    data_files = {"train": str(train_path)}
    if validation_path.exists() and validation_path.stat().st_size:
        data_files["validation"] = str(validation_path)
    dataset = stack["datasets"].load_dataset("json", data_files=data_files)

    sft_dir = config.resolve(config.training.output_dir)
    output_dir = config.resolve(config.preference_training.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    quantization = _quantization_config(stack, config.training.load_in_4bit)
    load_kwargs = {
        "is_trainable": True,
        "device_map": "auto" if torch.cuda.is_available() else None,
    }
    if quantization is not None:
        load_kwargs["quantization_config"] = quantization
    model = stack["peft"].AutoPeftModelForCausalLM.from_pretrained(str(sft_dir), **load_kwargs)
    tokenizer = stack["transformers"].AutoTokenizer.from_pretrained(str(sft_dir))
    dpo_values = {
        "output_dir": str(output_dir),
        "num_train_epochs": config.preference_training.epochs,
        "learning_rate": config.preference_training.learning_rate,
        "beta": config.preference_training.beta,
        "per_device_train_batch_size": config.training.per_device_train_batch_size,
        "per_device_eval_batch_size": config.training.per_device_eval_batch_size,
        "gradient_accumulation_steps": config.training.gradient_accumulation_steps,
        "gradient_checkpointing": True,
        "logging_steps": config.training.logging_steps,
        "eval_steps": config.training.eval_steps,
        "save_steps": config.training.save_steps,
        "bf16": config.training.bf16,
        "fp16": config.training.fp16,
        "report_to": "none",
        "seed": config.project.seed,
        "max_length": config.training.max_sequence_length,
        "eval_strategy": "steps" if "validation" in dataset else "no",
        "evaluation_strategy": "steps" if "validation" in dataset else "no",
    }
    args = stack["trl"].DPOConfig(**_supported_kwargs(stack["trl"].DPOConfig, dpo_values))
    trainer = stack["trl"].DPOTrainer(
        model=model,
        ref_model=None,
        args=args,
        train_dataset=dataset["train"],
        eval_dataset=dataset.get("validation"),
        processing_class=tokenizer,
    )
    result = trainer.train(resume_from_checkpoint=resume)
    trainer.save_model(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    metrics = dict(result.metrics)
    if "validation" in dataset:
        metrics["evaluation"] = trainer.evaluate()
    write_json_atomic(output_dir / "training_metrics.json", metrics)
    console.print(f"[green]DPO complete:[/green] {metrics}")
    return metrics


def merge_adapter(
    config: DistillConfig,
    console: Console | None = None,
    adapter_path: Path | None = None,
    allow_unvalidated: bool = False,
) -> Path:
    console = console or Console()
    stack = _require_training_stack()
    evaluation_path = config.resolve(config.paths.run_dir) / "evaluation" / "summary.json"
    evaluation = None
    if evaluation_path.exists():
        evaluation = json.loads(evaluation_path.read_text(encoding="utf-8"))
    if not allow_unvalidated and not (evaluation and evaluation.get("quality_gate_passed") is True):
        raise RuntimeError(
            "Refusing to merge an unvalidated adapter. Run `liber-distill evaluate` "
            "successfully, or use `merge --allow-unvalidated` for a development artefact."
        )
    adapter = adapter_path or (
        config.resolve(config.preference_training.output_dir)
        if config.preference_training.enabled
        else config.resolve(config.training.output_dir)
    )
    output = config.resolve(config.export.merged_dir)
    output.mkdir(parents=True, exist_ok=True)
    console.print(f"[cyan]Merging adapter {adapter} into base weights...[/cyan]")
    model = stack["peft"].AutoPeftModelForCausalLM.from_pretrained(
        str(adapter), device_map="cpu", torch_dtype=stack["torch"].float32
    )
    merged = model.merge_and_unload()
    merged.save_pretrained(str(output), safe_serialization=True, max_shard_size="2GB")
    tokenizer = stack["transformers"].AutoTokenizer.from_pretrained(str(adapter))
    tokenizer.save_pretrained(str(output))
    model_card = (
        f"# {config.project.name}\n\n"
        "Compact LibeR pharmacometrics assistant produced by provenance-aware "
        "response distillation.\n\n"
        f"- Base model: `{config.training.student_model}`\n"
        f"- Teacher: `{config.generation.teacher_model}`\n"
        f"- Judge: `{config.generation.judge_model}`\n"
        f"- Quality gate passed: "
        f"{bool(evaluation and evaluation.get('quality_gate_passed'))}\n"
        f"- Evaluation: {evaluation}\n\n"
        "## Intended use\n\nResearch and teaching assistance for LibeR and "
        "pharmacometrics. The model must not invent unavailable project evidence "
        "or act as an autonomous clinical decision maker.\n\n"
        "## Licence\n\nThe infrastructure is MIT licensed. The base model, source "
        "datasets and resulting weights retain their own terms; verify all terms "
        "before redistribution.\n"
    )
    (output / "README.md").write_text(model_card, encoding="utf-8")
    dataset_manifest = config.resolve(config.paths.dataset_dir) / "reproducibility_manifest.json"
    artifact_hashes = {
        path.relative_to(output).as_posix(): sha256_file(path)
        for path in sorted(output.rglob("*"))
        if path.is_file() and path.name != "liber_export_manifest.json"
    }
    write_json_atomic(
        output / "liber_export_manifest.json",
        {
            "base_model": config.training.student_model,
            "adapter": str(adapter),
            "merged_model": str(output),
            "system_prompt": config.project.system_prompt,
            "evaluation": evaluation,
            "dataset_manifest_sha256": (
                sha256_file(dataset_manifest) if dataset_manifest.exists() else None
            ),
            "artifacts_sha256": artifact_hashes,
        },
    )
    console.print(f"[green]Merged model written to {output}[/green]")
    return output
