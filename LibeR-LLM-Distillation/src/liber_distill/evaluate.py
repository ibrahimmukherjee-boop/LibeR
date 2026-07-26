from __future__ import annotations

import gc
from pathlib import Path

from rich.console import Console
from rich.progress import track

from .config import DistillConfig
from .io import read_jsonl, write_json_atomic, write_jsonl_atomic
from .ollama import OllamaClient
from .schemas import EvaluationAssessment

EVALUATION_SYSTEM = """You are an independent pharmacometrics evaluator.
Compare a model response with the question and, where supplied, the reference
answer. Judge technical correctness, groundedness, usefulness and safety. Do
not reward verbosity. Return only the requested JSON."""


def _load_stack() -> dict:
    try:
        import torch
        from peft import PeftModel
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            BitsAndBytesConfig,
        )
    except ImportError as exc:
        raise RuntimeError(
            'Evaluation needs the training extras: `python -m pip install -e ".[train]"`.'
        ) from exc
    return {
        "torch": torch,
        "PeftModel": PeftModel,
        "AutoModel": AutoModelForCausalLM,
        "AutoTokenizer": AutoTokenizer,
        "BitsAndBytesConfig": BitsAndBytesConfig,
    }


def _load_model(config: DistillConfig, adapter: Path | None) -> tuple[object, object, dict]:
    stack = _load_stack()
    torch = stack["torch"]
    quantization = None
    if torch.cuda.is_available():
        quantization = stack["BitsAndBytesConfig"](
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
            bnb_4bit_compute_dtype=torch.bfloat16,
        )
    kwargs = {
        "device_map": "auto" if torch.cuda.is_available() else None,
        "trust_remote_code": False,
    }
    if quantization is not None:
        kwargs["quantization_config"] = quantization
    model = stack["AutoModel"].from_pretrained(config.training.student_model, **kwargs)
    tokenizer_path = str(adapter) if adapter else config.training.student_model
    tokenizer = stack["AutoTokenizer"].from_pretrained(tokenizer_path, trust_remote_code=False)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    if adapter:
        model = stack["PeftModel"].from_pretrained(model, str(adapter))
    model.eval()
    return model, tokenizer, stack


def _generate(
    model: object,
    tokenizer: object,
    stack: dict,
    system_prompt: str,
    prompt: str,
) -> str:
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": prompt},
    ]
    try:
        rendered = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
        )
    except TypeError:
        rendered = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
    inputs = tokenizer(rendered, return_tensors="pt").to(model.device)
    with stack["torch"].inference_mode():
        output = model.generate(
            **inputs,
            max_new_tokens=600,
            do_sample=False,
            repetition_penalty=1.05,
            pad_token_id=tokenizer.pad_token_id,
            eos_token_id=tokenizer.eos_token_id,
        )
    generated = output[0, inputs["input_ids"].shape[1] :]
    return tokenizer.decode(generated, skip_special_tokens=True).strip()


def _cases(config: DistillConfig) -> list[dict]:
    cases = list(read_jsonl(config.resolve(config.evaluation.smoke_prompts)))
    test_path = config.resolve(config.paths.dataset_dir) / "test.jsonl"
    for row in read_jsonl(test_path):
        messages = row["messages"]
        cases.append(
            {
                "id": f"heldout-{row['id']}",
                "category": row["metadata"].get("category", "heldout"),
                "prompt": messages[1]["content"],
                "reference": messages[2]["content"],
                "required_terms": [],
                "forbidden_terms": [],
            }
        )
    return cases


def _term_pass(case: dict, response: str) -> bool:
    lower = response.lower()
    required = all(str(term).lower() in lower for term in case.get("required_terms", []))
    forbidden = all(str(term).lower() not in lower for term in case.get("forbidden_terms", []))
    return required and forbidden and bool(response.strip())


def _run_variant(
    config: DistillConfig,
    name: str,
    adapter: Path | None,
    cases: list[dict],
    console: Console,
) -> list[dict]:
    model, tokenizer, stack = _load_model(config, adapter)
    rows = []
    for case in track(cases, description=f"Evaluating {name}", console=console):
        response = _generate(
            model,
            tokenizer,
            stack,
            config.project.system_prompt,
            case["prompt"],
        )
        rows.append(
            {
                **case,
                "variant": name,
                "response": response,
                "term_pass": _term_pass(case, response),
            }
        )
    del model, tokenizer
    gc.collect()
    if stack["torch"].cuda.is_available():
        stack["torch"].cuda.empty_cache()
    return rows


def evaluate(
    config: DistillConfig,
    console: Console | None = None,
    with_judge: bool = False,
) -> dict:
    console = console or Console()
    cases = _cases(config)
    if not cases:
        raise RuntimeError("No evaluation cases are available.")
    adapter = (
        config.resolve(config.preference_training.output_dir)
        if config.preference_training.enabled
        else config.resolve(config.training.output_dir)
    )
    if not (adapter / "adapter_config.json").exists():
        raise RuntimeError(f"Trained adapter not found: {adapter}")

    baseline = _run_variant(config, "baseline", None, cases, console)
    tuned = _run_variant(config, "tuned", adapter, cases, console)
    all_rows = baseline + tuned

    if with_judge:
        client = OllamaClient(
            config.generation.base_url,
            config.generation.request_timeout_seconds,
            config.generation.max_retries,
        )
        options = {
            "temperature": 0,
            "num_ctx": config.generation.num_ctx,
            "num_predict": 1000,
            "seed": config.project.seed,
        }
        for row in track(all_rows, description="Teacher judging", console=console):
            assessment = client.chat_json(
                model=config.evaluation.judge_model,
                system=EVALUATION_SYSTEM,
                user=(
                    f"Question: {row['prompt']}\n\n"
                    f"Reference: {row.get('reference', 'No reference; use the rubric terms.')}\n\n"
                    f"Response: {row['response']}"
                ),
                response_type=EvaluationAssessment,
                options=options,
                think=config.generation.think,
            )
            row["judge"] = assessment.model_dump()

    baseline_pass = {row["id"]: row["term_pass"] for row in baseline}
    tuned_pass = {row["id"]: row["term_pass"] for row in tuned}
    regressions = sum(
        baseline_pass[item_id] and not tuned_pass[item_id] for item_id in baseline_pass
    )
    tuned_rate = sum(tuned_pass.values()) / len(tuned_pass)
    regression_fraction = regressions / len(tuned_pass)
    judge_score = None
    if with_judge:
        tuned_judged = [row["judge"]["score"] for row in tuned]
        judge_score = sum(tuned_judged) / len(tuned_judged)
    passed = (
        tuned_rate >= config.evaluation.minimum_pass_rate
        and regression_fraction <= config.evaluation.maximum_regression_fraction
        and (judge_score is None or judge_score >= config.quality.minimum_judge_score)
    )
    output = config.resolve(config.paths.run_dir) / "evaluation"
    write_jsonl_atomic(output / "responses.jsonl", all_rows)
    summary = {
        "cases": len(cases),
        "baseline_term_pass_rate": sum(baseline_pass.values()) / len(baseline_pass),
        "tuned_term_pass_rate": tuned_rate,
        "regression_fraction": regression_fraction,
        "mean_tuned_judge_score": judge_score,
        "quality_gate_passed": passed,
    }
    write_json_atomic(output / "summary.json", summary)
    console.print(f"[{'green' if passed else 'red'}]Evaluation: {summary}[/]")
    if not passed:
        raise RuntimeError("The tuned model did not pass the configured quality gates.")
    return summary
